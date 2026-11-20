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
export function clearBackground(data, w, h) {
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

// A cover is a 3D render with the bottle leaning in the frame, like the static
// posters. At 16x24 that lean turns every edge into a staircase and smears the
// label, so the sprite stands the bottle up first. Shapes with no clear long axis
// (a goblet, an hourglass, a face) and extreme leans are left as drawn.
const MAX_LEAN = 35;       // degrees: more than this is a pose, not a lean
const MIN_ELONGATION = 2;  // long-axis spread over short-axis spread (std dev ratio)

/**
 * The subject's long axis, from the opaque pixels' second moments:
 * { cx, cy, lean, elongation }. `lean` is in degrees from vertical, positive
 * when the bottle's top is to the left of its base (the way the covers lean).
 */
export function shapeAxis(data, w, h) {
  let n = 0, sx = 0, sy = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (data[(y * w + x) * 4 + 3] < 128) continue;
      n++; sx += x; sy += y;
    }
  }
  if (!n) return { cx: 0, cy: 0, lean: 0, elongation: 1 };
  const cx = sx / n, cy = sy / n;
  let mxx = 0, myy = 0, mxy = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (data[(y * w + x) * 4 + 3] < 128) continue;
      const dx = x - cx, dy = y - cy;
      mxx += dx * dx; myy += dy * dy; mxy += dx * dy;
    }
  }
  const half = (mxx + myy) / 2, spread = Math.hypot((mxx - myy) / 2, mxy);
  const elongation = Math.sqrt((half + spread) / Math.max(1e-9, half - spread));
  const phi = 0.5 * Math.atan2(2 * mxy, mxx - myy); // long axis, from the x axis (y points down)
  let lean = (Math.PI / 2 - phi) * (180 / Math.PI);  // from vertical
  lean = ((lean + 90) % 180 + 180) % 180 - 90;       // fold to (-90, 90]
  return { cx, cy, lean, elongation };
}

/** Rotate the subject upright about its centroid (nearest neighbour: the cells are 8 px, no need to smooth). */
function standUp(data, w, h, { cx, cy, lean }) {
  const t = (lean * Math.PI) / 180, c = Math.cos(t), s = Math.sin(t);
  const D = Math.ceil(Math.hypot(w, h));
  const out = Buffer.alloc(D * D * 4);
  // Keep the cover's own backdrop colour under the clear pixels, so trim() sees what it always saw.
  for (let i = 0; i < D * D; i++) { out[i * 4] = data[0]; out[i * 4 + 1] = data[1]; out[i * 4 + 2] = data[2]; }
  for (let oy = 0; oy < D; oy++) {
    for (let ox = 0; ox < D; ox++) {
      const u = ox - D / 2, v = oy - D / 2;
      const x = Math.round(cx + c * u + s * v), y = Math.round(cy - s * u + c * v);
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      const i = (y * w + x) * 4;
      if (data[i + 3] < 128) continue;
      data.copy(out, (oy * D + ox) * 4, i, i + 4);
    }
  }
  return { data: out, info: { width: D, height: D, channels: 4 } };
}

/** Any image → { idx: Uint8Array(W*H) with 0 = clear, centres: [[r,g,b]...] }. */
export async function pixelize(buf, { colours = 7, upright = true } = {}) {
  let big = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  clearBackground(big.data, big.info.width, big.info.height);
  if (upright) {
    const axis = shapeAxis(big.data, big.info.width, big.info.height);
    if (axis.elongation >= MIN_ELONGATION && Math.abs(axis.lean) >= 1 && Math.abs(axis.lean) <= MAX_LEAN) {
      big = standUp(big.data, big.info.width, big.info.height, axis);
    }
  }
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

// A hung work is a picture, not an object: no background to clear and nothing
// to stand upright. It keeps its own shape inside an ART x ART box, so a square
// Sirial is 24x24 and a portrait Community Gallery work is ~17x24.
export const ART = 24;

/** The work's size in sprite pixels: the longer side ART, the other by aspect. */
export function artSize(aspect) {
  const a = Number.isFinite(aspect) && aspect > 0 ? aspect : 1;
  return a >= 1
    ? { w: ART, h: Math.max(8, Math.round(ART / a)) }
    : { w: Math.max(8, Math.round(ART * a)), h: ART };
}

// Averaging a painting down to 24 px gives a blurry thumbnail: every cell is a
// mix of its colours, and 15 shades of mud. The badge wants pixel art, like the
// bottles: a handful of flat colours from the work itself, and every pixel one
// of them. So the palette is picked from the full-size image, each cell takes
// the colour it holds most of (a vote, never an average), rarer colours vote a
// little louder so eyes and outlines survive, and lone pixels are cleaned up.
// Ink drawings (most Sirials) get their dark lines thickened first, or the
// vote would hand every cell to the paper.
const ART_CELL = 8;          // source pixels per sprite pixel
const ART_COLOURS = 7;       // like the bottles
const INK_COLOURS = 4;       // black, paper and a grey or two
const INK_SATURATION = 0.12; // mean saturation below this: an ink drawing
const MERGE = 40;            // palette colours closer than this (RGB distance) are one

/** Mean saturation (HSV) of an RGB buffer, 0..1. */
function saturation(data) {
  let sum = 0;
  const n = data.length / 3;
  for (let i = 0; i < data.length; i += 3) {
    const mx = Math.max(data[i], data[i + 1], data[i + 2]), mn = Math.min(data[i], data[i + 1], data[i + 2]);
    sum += mx ? (mx - mn) / mx : 0;
  }
  return sum / n;
}

/** Thicken dark lines: each pixel takes its darkest neighbour within r. */
function thickenInk(src, w, h, r) {
  const out = Buffer.from(src);
  const lum = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) lum[i] = src[i * 3] * 0.3 + src[i * 3 + 1] * 0.59 + src[i * 3 + 2] * 0.11;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let bi = y * w + x;
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          const xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          if (lum[yy * w + xx] < lum[bi]) bi = yy * w + xx;
        }
      }
      src.copy(out, (y * w + x) * 3, bi * 3, bi * 3 + 3);
    }
  }
  return out;
}

/** A pixel with no same-coloured 4-neighbour takes the colour most of them share. */
function cleanOrphans(idx, w, h) {
  const src = idx.slice();
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x, n = [];
      if (x > 0) n.push(src[i - 1]);
      if (x < w - 1) n.push(src[i + 1]);
      if (y > 0) n.push(src[i - w]);
      if (y < h - 1) n.push(src[i + w]);
      if (n.includes(src[i])) continue;
      const count = new Map();
      for (const v of n) count.set(v, (count.get(v) ?? 0) + 1);
      const [best, k] = [...count].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0];
      if (k >= 2) idx[i] = best;
    }
  }
}

/** A painting → { idx, centres, w, h, ink }: a pixel-art miniature in a few flat colours. */
export async function pixelizeArt(buf, { aspect } = {}) {
  const meta = await sharp(buf).metadata();
  const { w, h } = artSize(aspect ?? (meta.width && meta.height ? meta.width / meta.height : 1));
  const BW = w * ART_CELL, BH = h * ART_CELL;
  const base = sharp(buf).flatten({ background: '#000000' }).removeAlpha()
    .resize(BW, BH, { fit: 'cover', kernel: 'lanczos3' }).normalise();
  const ink = saturation(await base.clone().raw().toBuffer()) < INK_SATURATION;
  // A median takes the grain and the finest hatching out before the vote.
  let data = await base.modulate({ saturation: 1.3 }).median(3).raw().toBuffer();
  if (ink) data = thickenInk(data, BW, BH, 1);

  const pixels = [];
  for (let i = 0; i < BW * BH; i += 3) pixels.push([data[i * 3], data[i * 3 + 1], data[i * 3 + 2]]);
  let { centres } = quantize(pixels, ink ? INK_COLOURS : ART_COLOURS);
  centres = centres.filter((c, i) => !centres.slice(0, i).some((o) => dist(o, c) < MERGE * MERGE));
  const nearest = (p) => {
    let bi = 0, bd = Infinity;
    centres.forEach((c, i) => { const d = dist(p, c); if (d < bd) { bd = d; bi = i; } });
    return bi;
  };
  const q = new Uint8Array(BW * BH), freq = new Array(centres.length).fill(0);
  for (let i = 0; i < BW * BH; i++) { q[i] = nearest([data[i * 3], data[i * 3 + 1], data[i * 3 + 2]]); freq[q[i]]++; }
  // The vote: a colour's share of the cell, louder the rarer it is overall.
  const loud = freq.map((f) => (BW * BH / Math.max(1, f)) ** (ink ? 0.25 : 0.5));
  // Palette index 0 is "clear"; a picture has none, so every pixel is 1..n.
  const idx = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const votes = new Array(centres.length).fill(0);
      for (let dy = 0; dy < ART_CELL; dy++) {
        for (let dx = 0; dx < ART_CELL; dx++) votes[q[(y * ART_CELL + dy) * BW + x * ART_CELL + dx]]++;
      }
      let bi = 0, bs = -1;
      votes.forEach((v, i) => { if (v * loud[i] > bs) { bs = v * loud[i]; bi = i; } });
      idx[y * w + x] = bi + 1;
    }
  }
  cleanOrphans(idx, w, h);
  if (ink) cleanOrphans(idx, w, h);
  return { ...compact({ idx, centres }), w, h, ink };
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
export async function toPng({ idx, centres, w: SW = W, h: SH = H }, scale = 1) {
  const [W, H] = [SW, SH];
  const raw = Buffer.alloc(W * H * 4);
  idx.forEach((v, i) => {
    if (!v) return;
    const c = centres[v - 1];
    raw[i * 4] = c[0]; raw[i * 4 + 1] = c[1]; raw[i * 4 + 2] = c[2]; raw[i * 4 + 3] = 255;
  });
  return sharp(raw, { raw: { width: W, height: H, channels: 4 } })
    .resize(W * scale, H * scale, { kernel: 'nearest' }).png().toBuffer();
}
