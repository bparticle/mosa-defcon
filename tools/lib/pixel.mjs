// Badge sprites: 16x24 pixel art, up to 15 colours plus clear, binary alpha.
//
// Two sources, one format:
//   art/pixel/<collection>/<piece>.png   hand-made pixel art (wins when present)
//   the piece's cover render             pixelized automatically (the fallback)
//
// `pixelize` turns any image (a cover, a ChatGPT/PixelLab output at 1024 px with
// fake pixels, a photo) into a clean sprite: background removal when there is
// no alpha, a mode filter per cell (crisp colours, no averaged mud), a small
// k-means palette, and a despeckle pass. `validateSprite` holds hand art to the
// badge's rules exactly, so what an artist draws is what the badge shows.
import sharp from 'sharp';

export const W = 16, H = 24, MAX_COLOURS = 15;
const CELL = 8; // source pixels per sprite pixel when pixelizing

export const rgb565 = (r, g, b) => ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
const dist = (a, b) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;

/** Tiny k-means seeded by frequency. pixels: [[r,g,b], ...]. */
export function quantize(pixels, k) {
  const freq = new Map();
  for (const p of pixels) {
    const key = ((p[0] >> 4) << 8) | ((p[1] >> 4) << 4) | (p[2] >> 4);
    freq.set(key, (freq.get(key) ?? 0) + 1);
  }
  let centres = [...freq.entries()].sort((a, b) => b[1] - a[1]).slice(0, k)
    .map(([key]) => [((key >> 8) & 15) * 17, ((key >> 4) & 15) * 17, (key & 15) * 17]);
  const nearest = (p) => {
    let bi = 0, bd = Infinity;
    centres.forEach((c, i) => { const d = dist(p, c); if (d < bd) { bd = d; bi = i; } });
    return bi;
  };
  for (let iter = 0; iter < 12; iter++) {
    const acc = centres.map(() => [0, 0, 0, 0]);
    for (const p of pixels) { const a = acc[nearest(p)]; a[0] += p[0]; a[1] += p[1]; a[2] += p[2]; a[3]++; }
    centres = centres.map((c, i) => (acc[i][3] ? acc[i].slice(0, 3).map((v) => Math.round(v / acc[i][3])) : c));
  }
  return { centres, nearest };
}

/** Clear the background of an image with no alpha: flood from the corners. */
function clearBackground(data, w, h) {
  const at = (x, y) => (y * w + x) * 4;
  const corners = [at(0, 0), at(w - 1, 0), at(0, h - 1), at(w - 1, h - 1)];
  if (corners.some((i) => data[i + 3] < 128)) return; // it already has alpha
  const seen = new Uint8Array(w * h);
  for (const ci of corners) {
    const ref = [data[ci], data[ci + 1], data[ci + 2]];
    const stack = [ci / 4];
    while (stack.length) {
      const p = stack.pop();
      if (seen[p]) continue;
      const i = p * 4;
      if (dist([data[i], data[i + 1], data[i + 2]], ref) > 40 * 40) continue;
      seen[p] = 1;
      data[i + 3] = 0;
      const x = p % w, y = (p / w) | 0;
      if (x > 0) stack.push(p - 1);
      if (x < w - 1) stack.push(p + 1);
      if (y > 0) stack.push(p - w);
      if (y < h - 1) stack.push(p + w);
    }
  }
}

/** Any image → { idx: Uint8Array(W*H) with 0 = clear, centres: [[r,g,b]...] }. */
export async function pixelize(buf, { colours = 7 } = {}) {
  const big = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  clearBackground(big.data, big.info.width, big.info.height);
  const { data } = await sharp(big.data, { raw: big.info })
    .trim({ threshold: 1 })
    .resize(W * CELL, H * CELL, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 }, kernel: 'mitchell' })
    .raw()
    .toBuffer({ resolveWithObject: true });
  const SW = W * CELL;
  // Mode filter: each sprite pixel takes the commonest colour in its cell.
  const cells = [];
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const buckets = new Map();
      let opaque = 0;
      for (let dy = 0; dy < CELL; dy++) {
        for (let dx = 0; dx < CELL; dx++) {
          const i = ((y * CELL + dy) * SW + x * CELL + dx) * 4;
          if (data[i + 3] < 128) continue;
          opaque++;
          const key = ((data[i] >> 3) << 10) | ((data[i + 1] >> 3) << 5) | (data[i + 2] >> 3);
          const b = buckets.get(key) ?? [0, 0, 0, 0];
          b[0] += data[i]; b[1] += data[i + 1]; b[2] += data[i + 2]; b[3]++;
          buckets.set(key, b);
        }
      }
      if (opaque * 2 < CELL * CELL) { cells.push(null); continue; }
      // Bucket neighbours vote together, so a gradient doesn't split the vote.
      let best = null, bestScore = -1;
      for (const [key, b] of buckets) {
        let score = 0;
        const r = key >> 10, g = (key >> 5) & 31, bl = key & 31;
        for (const [k2, b2] of buckets) {
          if (Math.abs((k2 >> 10) - r) <= 1 && Math.abs(((k2 >> 5) & 31) - g) <= 1 && Math.abs((k2 & 31) - bl) <= 1) score += b2[3];
        }
        if (score > bestScore) { bestScore = score; best = b; }
      }
      cells.push([best[0] / best[3], best[1] / best[3], best[2] / best[3]].map(Math.round));
    }
  }
  const opaque = cells.filter(Boolean);
  const { centres, nearest } = quantize(opaque, Math.min(colours, MAX_COLOURS));
  const idx = new Uint8Array(W * H);
  cells.forEach((c, i) => { idx[i] = c ? nearest(c) + 1 : 0; });
  despeckle(idx);
  return compact({ idx, centres });
}

/** Lone pixels: a speck inside a flat area takes the area's colour; a speck in the air goes. */
function despeckle(idx) {
  const src = idx.slice();
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      if (!src[i]) continue;
      const n = [];
      if (x > 0) n.push(src[i - 1]);
      if (x < W - 1) n.push(src[i + 1]);
      if (y > 0) n.push(src[i - W]);
      if (y < H - 1) n.push(src[i + W]);
      if (n.every((v) => v === 0)) { idx[i] = 0; continue; }
      if (n.length === 4 && n.every((v) => v === n[0]) && n[0] !== src[i] && n[0] !== 0) idx[i] = n[0];
    }
  }
}

/** Drop unused palette entries and renumber. */
function compact({ idx, centres }) {
  const used = [...new Set(idx)].filter((v) => v).sort((a, b) => a - b);
  const map = new Map(used.map((v, i) => [v, i + 1]));
  return { idx: idx.map((v) => map.get(v) ?? 0), centres: used.map((v) => centres[v - 1]) };
}

/**
 * Hand art: must already be badge-ready. Returns { sprite } or { errors }.
 * Rules: exactly 16x24; every pixel fully clear or fully opaque; at most 15
 * colours. Colours are stored as RGB565, so near-identical shades may merge.
 */
export async function validateSprite(buf) {
  const { data, info } = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const errors = [];
  if (info.width !== W || info.height !== H) errors.push(`is ${info.width}x${info.height}, must be ${W}x${H}`);
  if (errors.length) return { errors };
  const colours = new Map();
  const idx = new Uint8Array(W * H);
  let partial = 0;
  for (let i = 0; i < W * H; i++) {
    const a = data[i * 4 + 3];
    if (a !== 0 && a !== 255) partial++;
    if (a < 128) continue;
    const key = rgb565(data[i * 4], data[i * 4 + 1], data[i * 4 + 2]);
    if (!colours.has(key)) colours.set(key, colours.size + 1);
    idx[i] = colours.get(key);
  }
  if (partial) errors.push(`${partial} semi-transparent pixel(s): alpha must be 0 or 255`);
  if (colours.size > MAX_COLOURS) errors.push(`${colours.size} colours, at most ${MAX_COLOURS}`);
  if (colours.size === 0) errors.push('is empty');
  if (errors.length) return { errors };
  const centres = [...colours.keys()].map((c) => [((c >> 11) & 31) << 3, ((c >> 5) & 63) << 2, (c & 31) << 3]);
  return { sprite: { idx, centres } };
}

/** Sprite → the badge's encoding: { pal, rle, tint }. */
export function encode({ idx, centres }) {
  const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let rle = '';
  for (let i = 0; i < idx.length;) {
    let n = 1;
    while (i + n < idx.length && idx[i + n] === idx[i] && n < 64) n++;
    rle += B64[n - 1] + idx[i].toString(16);
    i += n;
  }
  const pal = centres.map((c) => rgb565(...c).toString(16).padStart(4, '0')).join('');
  // The glint colour on the map: the sprite's average, lifted so it reads in the dark.
  let sum = [0, 0, 0], n = 0;
  for (const v of idx) if (v) { sum = sum.map((s, c) => s + centres[v - 1][c]); n++; }
  const avg = sum.map((v) => Math.min(255, Math.round((v / Math.max(1, n)) * 1.25 + 30)));
  return { pal, rle, tint: rgb565(...avg) };
}

/** Sprite → PNG (scale × nearest), for previews and starter files. */
export async function toPng({ idx, centres }, scale = 1) {
  const raw = Buffer.alloc(W * H * 4);
  idx.forEach((v, i) => {
    if (!v) return;
    const c = centres[v - 1];
    raw[i * 4] = c[0]; raw[i * 4 + 1] = c[1]; raw[i * 4 + 2] = c[2]; raw[i * 4 + 3] = 255;
  });
  return sharp(raw, { raw: { width: W, height: H, channels: 4 } })
    .resize(W * scale, H * scale, { kernel: 'nearest' }).png().toBuffer();
}
