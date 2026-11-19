#!/usr/bin/env node
// pnpm sync [--mosa ../mosa] [--api https://api.mosa.center] [--check]
//
// The one door between MOSA and the badge. Everything the badge knows about
// the museum is DERIVED here from MOSA's own sources, never hand-copied:
//
//   MOSA repo (local checkout, pinned by commit in mosa.lock.json)
//     apps/frontend/src/lib/rooms.generated.ts  the room table, exported from
//                                               MOSA-ROOMS.blend: claim volumes
//                                               become the badge floorplans,
//                                               portals become doors, vitrines/
//                                               boards/machines become landmarks
//     apps/frontend/public/rooms/<id>.programme.json
//                                               each room's goals: the badge
//                                               stamps the same ones (visit,
//                                               pop-all-balloons, discover-room)
//     apps/frontend/src/lib/linkPaths.ts        the /at/ link grammar. Every URL
//                                               the badge will ever print as a QR
//                                               is checked with MOSA's own parser
//   MOSA API (public, live)
//     GET /finds/catalog                        collections, pieces, tiers, where
//                                               each collection hunts
//     GET /links                                curated /at/<slug> links
//     GET /finds/media/<c>/<p>/cover            renders, shrunk to badge thumbnails
//
// Outputs (both committed):
//   src/data/mosa_data.lua   the generated Lua module the app requires
//   mosa.lock.json           what it was generated from: MOSA commit, API hashes,
//                            and the APPEND-ONLY piece/room index registry that
//                            keeps shift-report bitmasks stable across releases
//
// --check   regenerate in memory and exit 1 if the committed data is stale
//           (the scheduled CI drift check runs this).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import sharp from 'sharp';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};
const CHECK = args.includes('--check');
const MOSA = path.resolve(ROOT, opt('mosa', process.env.MOSA_REPO ?? '../mosa'));
const API = opt('api', process.env.MOSA_API ?? 'https://api.mosa.center').replace(/\/$/, '');
const SITE = opt('site', process.env.MOSA_SITE ?? 'https://mosa.center').replace(/\/$/, '');
const LOCK_PATH = path.join(ROOT, 'mosa.lock.json');
const DATA_PATH = path.join(ROOT, 'src', 'data', 'mosa_data.lua');
const THUMB_CACHE = path.join(ROOT, '.cache', 'thumbs');

/** Bump when the shape of mosa_data.lua changes; the app refuses a mismatch. */
export const DATA_SCHEMA = 1;

// Badge map tuning. A tile is drawn TILE_PX square on the 320x240 screen.
const MAX_TILES = 44;      // longest room axis, in tiles (before the corridor rule)
const MIN_SHORT_TILES = 8; // a room's short axis gets at least this many tiles…
const HARD_MAX_TILES = 100;// …unless that would make the long axis longer than this
const MIN_TILE_M = 1.5;    // never finer than this many metres per tile
const MAX_TILE_M = 8;
const THUMB_W = 16, THUMB_H = 24, THUMB_COLOURS = 15;

/** The badge font is 6x8 ASCII: fold accents and typographic quotes, drop the rest. */
const ascii = (s) => String(s ?? '')
  .normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
  .replace(/[\u2018\u2019\u02bc]/g, "'").replace(/[\u201c\u201d]/g, '"')
  .replace(/[\u2013\u2014]/g, '-').replace(/\u2026/g, '...').replace(/\u00b7/g, '-')
  .replace(/[^\x20-\x7e]/g, '').replace(/\s+/g, ' ').trim();
const log = (...a) => console.error('[sync]', ...a);
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);

// ── MOSA repo ────────────────────────────────────────────────────────────────

function mosaFile(rel) {
  const p = path.join(MOSA, rel);
  if (!fs.existsSync(p)) throw new Error(`MOSA checkout missing ${rel} (looked in ${MOSA}; pass --mosa <path>)`);
  return p;
}

function mosaCommit() {
  const git = (...a) => execFileSync('git', ['-C', MOSA, ...a], { encoding: 'utf8' }).trim();
  const commit = git('rev-parse', 'HEAD');
  const dirty = git('status', '--porcelain', '--', 'apps/frontend/src/lib/rooms.generated.ts', 'apps/frontend/src/lib/linkPaths.ts') !== '';
  let describe = '';
  try { describe = git('describe', '--tags', '--always'); } catch { describe = commit.slice(0, 7); }
  return { commit, describe, dirty };
}

// ── geometry → floorplans ────────────────────────────────────────────────────

/** Axis-aligned footprint (x,z) of a box with a Y rotation. */
function footprint(center, half, rotationY = 0) {
  const c = Math.abs(Math.cos(rotationY)), s = Math.abs(Math.sin(rotationY));
  const hx = c * half[0] + s * half[2];
  const hz = s * half[0] + c * half[2];
  return { x0: center[0] - hx, x1: center[0] + hx, z0: center[2] - hz, z1: center[2] + hz };
}

function roomPlan(room, allPortals) {
  const boxes = room.claims.map((c) => footprint(c.center, c.half, c.rotationY));
  const minX = Math.min(...boxes.map((b) => b.x0)), maxX = Math.max(...boxes.map((b) => b.x1));
  const minZ = Math.min(...boxes.map((b) => b.z0)), maxZ = Math.max(...boxes.map((b) => b.z1));
  const longest = Math.max(maxX - minX, maxZ - minZ);
  const shortest = Math.min(maxX - minX, maxZ - minZ);
  const half = (v) => Math.ceil(v * 2) / 2;
  let m = Math.min(MAX_TILE_M, Math.max(MIN_TILE_M, half(longest / MAX_TILES)));
  // Long halls (Floor 1 is 312 m by 28 m) scroll rather than shrink to a slit.
  m = Math.max(MIN_TILE_M, half(longest / HARD_MAX_TILES), Math.min(m, half(shortest / MIN_SHORT_TILES)));
  // One tile of wall all round.
  const ox = minX - m, oz = minZ - m;
  const w = Math.ceil((maxX - minX) / m) + 2, h = Math.ceil((maxZ - minZ) / m) + 2;
  const tx = (x) => Math.floor((x - ox) / m), tz = (z) => Math.floor((z - oz) / m);

  const rects = boxes.map((b) => {
    const x0 = tx(b.x0 + 1e-6), z0 = tz(b.z0 + 1e-6);
    const x1 = Math.max(x0, tx(b.x1 - 1e-6)), z1 = Math.max(z0, tz(b.z1 - 1e-6));
    return [x0, z0, x1 - x0 + 1, z1 - z0 + 1];
  });
  const floor = new Set();
  for (const [x, y, rw, rh] of rects) for (let j = y; j < y + rh; j++) for (let i = x; i < x + rw; i++) floor.add(`${i},${j}`);

  const nearestFloor = (x, z, avoid = new Set()) => {
    const fx = (x - ox) / m - 0.5, fz = (z - oz) / m - 0.5;
    let best = null, bestD = Infinity;
    for (const key of floor) {
      if (avoid.has(key)) continue;
      const [i, j] = key.split(',').map(Number);
      const d = (i - fx) ** 2 + (j - fz) ** 2;
      if (d < bestD) { bestD = d; best = [i, j]; }
    }
    return best;
  };

  const doors = [];
  for (const p of allPortals) {
    if (!p.rooms.includes(room.id)) continue;
    const to = p.rooms[0] === room.id ? p.rooms[1] : p.rooms[0];
    const [i, j] = nearestFloor(p.center[0], p.center[2]);
    doors.push({ to, x: i, y: j, key: p.key });
  }
  for (const wp of room.warps ?? []) {
    const [i, j] = nearestFloor(wp.center[0], wp.center[2]);
    doors.push({ to: wp.toRoom, x: i, y: j, key: `warp:${room.id}:${wp.name}`, warp: true });
  }

  // Landmarks: the museum's furniture, each one a thing the badge can describe.
  const occupied = new Set(doors.map((d) => `${d.x},${d.y}`));
  const marks = [];
  const place = (kind, name, center, half, rotationY) => {
    const fp = half ? footprint(center, half, rotationY) : { x0: center[0], x1: center[0], z0: center[2], z1: center[2] };
    const at = nearestFloor((fp.x0 + fp.x1) / 2, (fp.z0 + fp.z1) / 2, occupied);
    if (!at) return;
    const mw = Math.max(1, Math.min(4, Math.round((fp.x1 - fp.x0) / m)));
    const mh = Math.max(1, Math.min(4, Math.round((fp.z1 - fp.z0) / m)));
    let [x, y] = at;
    // Keep the mark inside the floor; shrink rather than block a corridor.
    const cells = [];
    for (let j = 0; j < mh; j++) for (let i = 0; i < mw; i++) {
      const k = `${x + i},${y + j}`;
      if (floor.has(k) && !occupied.has(k)) cells.push(k);
    }
    const fits = cells.length === mw * mh;
    const [cw, ch] = fits ? [mw, mh] : [1, 1];
    for (let j = 0; j < ch; j++) for (let i = 0; i < cw; i++) occupied.add(`${x + i},${y + j}`);
    marks.push({ kind, name, x, y, w: cw, h: ch });
  };
  for (const v of room.vitrines) place('vitrine', v.name, v.center, v.half, v.rotationY);
  for (const f of room.flapboards) place('flapboard', f.name, f.center, f.half, f.rotationY);
  for (const p of room.postcardwalls) place('postcards', p.name, p.center, p.half, p.rotationY);
  for (const d of room.dispensers) place('tickets', d.id, d.center, null, 0);
  for (const v of room.vendors) place('vending', v.id, v.center, null, 0);
  for (const e of room.entrances) place('entrance', e.slug, e.center, null, 0);

  return { m, ox, oz, w, h, rects, doors, marks, floorTiles: floor.size };
}

// ── thumbnails ───────────────────────────────────────────────────────────────

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const rgb565 = (r, g, b) => ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);

function quantize(pixels, k) {
  // pixels: [[r,g,b], ...] opaque only. Tiny k-means seeded by frequency.
  const freq = new Map();
  for (const p of pixels) {
    const key = ((p[0] >> 4) << 8) | ((p[1] >> 4) << 4) | (p[2] >> 4);
    freq.set(key, (freq.get(key) ?? 0) + 1);
  }
  let centres = [...freq.entries()].sort((a, b) => b[1] - a[1]).slice(0, k)
    .map(([key]) => [((key >> 8) & 15) * 17, ((key >> 4) & 15) * 17, (key & 15) * 17]);
  const nearest = (p) => {
    let bi = 0, bd = Infinity;
    centres.forEach((c, i) => {
      const d = (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2;
      if (d < bd) { bd = d; bi = i; }
    });
    return bi;
  };
  for (let iter = 0; iter < 10; iter++) {
    const acc = centres.map(() => [0, 0, 0, 0]);
    for (const p of pixels) { const a = acc[nearest(p)]; a[0] += p[0]; a[1] += p[1]; a[2] += p[2]; a[3]++; }
    centres = centres.map((c, i) => (acc[i][3] ? acc[i].slice(0, 3).map((v) => Math.round(v / acc[i][3])) : c));
  }
  return { centres, nearest };
}

async function thumbnail(collection, piece, etag) {
  fs.mkdirSync(THUMB_CACHE, { recursive: true });
  const cacheFile = path.join(THUMB_CACHE, `${collection}--${piece}--${etag || 'x'}.png`);
  let buf;
  if (fs.existsSync(cacheFile)) buf = fs.readFileSync(cacheFile);
  else {
    const res = await fetch(`${API}/finds/media/${collection}/${piece}/cover`);
    if (!res.ok) throw new Error(`cover ${collection}/${piece}: HTTP ${res.status}`);
    buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(cacheFile, buf);
  }
  const { data } = await sharp(buf)
    .ensureAlpha()
    .trim({ threshold: 1 })
    .resize(THUMB_W, THUMB_H, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 }, kernel: 'lanczos3' })
    .raw()
    .toBuffer({ resolveWithObject: true });
  const opaque = [];
  for (let i = 0; i < THUMB_W * THUMB_H; i++) if (data[i * 4 + 3] >= 110) opaque.push([data[i * 4], data[i * 4 + 1], data[i * 4 + 2]]);
  const { centres, nearest } = quantize(opaque, THUMB_COLOURS);
  // Run-length pairs: <count-1 in base64 alphabet><palette index in hex, 0 = clear>,
  // scanning row by row. The badge draws each run as one rect, with no decode cache.
  const idx = [];
  let sum = [0, 0, 0];
  for (let i = 0; i < THUMB_W * THUMB_H; i++) {
    if (data[i * 4 + 3] < 110) { idx.push(0); continue; }
    const p = [data[i * 4], data[i * 4 + 1], data[i * 4 + 2]];
    idx.push(nearest(p) + 1);
    sum = sum.map((v, c) => v + p[c]);
  }
  let rle = '';
  for (let i = 0; i < idx.length;) {
    let n = 1;
    while (i + n < idx.length && idx[i + n] === idx[i] && n < 64) n++;
    rle += B64[n - 1] + idx[i].toString(16);
    i += n;
  }
  const pal = centres.map((c) => rgb565(...c).toString(16).padStart(4, '0')).join('');
  const n = Math.max(1, opaque.length);
  // The glint colour on the map: the piece's average, lifted so it reads in the dark.
  const avg = sum.map((v) => Math.min(255, Math.round((v / n) * 1.25 + 30)));
  return { pal, rle, tint: rgb565(...avg) };
}

// ── Lua emitter ──────────────────────────────────────────────────────────────

function lua(value, indent = '') {
  if (value === null || value === undefined) return 'nil';
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('non-finite number');
    return Number.isInteger(value) ? String(value) : String(Math.round(value * 1000) / 1000);
  }
  if (typeof value === 'boolean') return String(value);
  if (typeof value === 'string') return JSON.stringify(value).replace(/\\u([0-9a-f]{4})/gi, (_, h) => {
    // Lua 5.4 understands \u{XXXX}
    return `\\u{${h}}`;
  });
  if (Array.isArray(value)) {
    if (value.every((v) => typeof v !== 'object' || v === null)) return `{${value.map((v) => lua(v)).join(',')}}`;
    const inner = indent + '  ';
    return `{\n${value.map((v) => inner + lua(v, inner)).join(',\n')}\n${indent}}`;
  }
  const inner = indent + '  ';
  const entries = Object.entries(value).filter(([, v]) => v !== undefined);
  const key = (k) => (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `[${JSON.stringify(k)}]`);
  const leaf = (v) => v === null || typeof v !== 'object' || (Array.isArray(v) && v.every((x) => x === null || typeof x !== 'object'));
  if (entries.every(([, v]) => leaf(v)) && entries.reduce((n, [, v]) => n + (typeof v === 'string' ? v.length : 4), 0) < 160) {
    return `{${entries.map(([k, v]) => `${key(k)}=${lua(v)}`).join(',')}}`;
  }
  return `{\n${entries.map(([k, v]) => `${inner}${key(k)}=${lua(v, inner)}`).join(',\n')}\n${indent}}`;
}

// ── main ─────────────────────────────────────────────────────────────────────

async function getJson(p) {
  const res = await fetch(`${API}${p}`);
  if (!res.ok) throw new Error(`GET ${p}: HTTP ${res.status}`);
  return res.json();
}

async function main() {
  const lock = fs.existsSync(LOCK_PATH) ? JSON.parse(fs.readFileSync(LOCK_PATH, 'utf8')) : {};
  const registry = { rooms: [...(lock.registry?.rooms ?? [])], pieces: [...(lock.registry?.pieces ?? [])] };

  const source = mosaCommit();
  if (source.dirty) log('warning: MOSA checkout has uncommitted changes to the synced files');
  const roomsTs = mosaFile('apps/frontend/src/lib/rooms.generated.ts');
  const linksTs = mosaFile('apps/frontend/src/lib/linkPaths.ts');
  const { GENERATED_ROOMS } = await import(pathToFileURL(roomsTs).href);
  const { parseLinkPath, findLinkPath } = await import(pathToFileURL(linksTs).href);

  /** Every URL the badge prints goes through MOSA's own link parser. */
  const linkUrl = (p) => {
    if (!parseLinkPath(p)) throw new Error(`MOSA's link grammar rejects ${p}`);
    return `${SITE}${p}`;
  };

  const [catalog, links] = await Promise.all([getJson('/finds/catalog'), getJson('/links')]);

  // Portals are listed by both rooms (sometimes by only one); dedupe by pair+place.
  const portals = new Map();
  for (const r of GENERATED_ROOMS) for (const p of r.portals) {
    const key = `${[...p.rooms].sort().join('|')}@${p.center.map((n) => n.toFixed(1)).join(',')}`;
    if (!portals.has(key)) portals.set(key, { ...p, key });
  }
  const allPortals = [...portals.values()];

  const roomIds = new Set(GENERATED_ROOMS.map((r) => r.id));
  const startRoom = GENERATED_ROOMS.find((r) => r.start)?.id ?? GENERATED_ROOMS[0].id;
  for (const r of GENERATED_ROOMS) if (!registry.rooms.includes(r.id)) registry.rooms.push(r.id);

  // A curated link per room, when MOSA has one (e.g. /at/bp26 → room12).
  const roomLinks = {};
  for (const l of links.links ?? []) {
    if (l.enabled && l.kind === 'room' && !roomLinks[l.ref] && !l.opensAt) roomLinks[l.ref] = linkUrl(`/at/${l.slug}`);
  }

  // Where finds hunt and lie wild, per room — straight from the catalogue.
  const huntByRoom = {};
  for (const c of catalog.collections) {
    for (const [room, n] of Object.entries({ ...(c.hunt?.rooms ?? {}) })) huntByRoom[room] = (huntByRoom[room] ?? 0) + n;
    for (const [room, n] of Object.entries(c.wild ?? {})) huntByRoom[room] = (huntByRoom[room] ?? 0) + n;
  }

  // Room programmes (MOSA's quests). The badge can award the goal types it can
  // observe; any other type is reported and skipped, never approximated.
  const BADGE_GOALS = new Set(['visit', 'pop-all-balloons', 'discover-room']);
  const programme = (id) => {
    const file = path.join(MOSA, 'apps/frontend/public/rooms', `${id}.programme.json`);
    if (!fs.existsSync(file)) return [];
    const goals = JSON.parse(fs.readFileSync(file, 'utf8')).goals ?? [];
    for (const g of goals) if (!BADGE_GOALS.has(g.type)) log(`${id}: goal type '${g.type}' (${g.id}) has no badge equivalent yet; skipped`);
    return goals.filter((g) => BADGE_GOALS.has(g.type)).map((g) => ({
      id: g.id, type: g.type, name: ascii(g.name), text: ascii(g.description), room: g.room,
    }));
  };

  // A partner entrance in the room can be scanned straight to its own /at/ link.
  const entranceLinks = {};
  for (const l of links.links ?? []) {
    if (l.enabled && l.kind === 'entrance' && !l.opensAt) entranceLinks[l.ref] = { url: linkUrl(`/at/${l.slug}`), label: ascii(l.label || l.hostName || l.slug) };
  }

  const rooms = GENERATED_ROOMS.map((r) => {
    const plan = roomPlan(r, allPortals);
    for (const mk of plan.marks) if (mk.kind === 'entrance' && entranceLinks[mk.name]) Object.assign(mk, entranceLinks[mk.name]);
    const area = plan.floorTiles;
    return {
      id: r.id,
      idx: registry.rooms.indexOf(r.id),
      name: ascii(r.name),
      m: plan.m,
      w: plan.w,
      h: plan.h,
      rects: plan.rects,
      doors: plan.doors.filter((d) => roomIds.has(d.to)).map((d) => ({ to: d.to, x: d.x, y: d.y, warp: d.warp || undefined })),
      marks: plan.marks,
      // Night-shift litter: the catalogue's own hunt/wild counts, so the busiest
      // rooms in the museum are the messiest on the badge. Scaled for a smaller map.
      bottles: Math.max(1, Math.min(8, Math.round((huntByRoom[r.id] ?? 0) * 0.6) || (area > 60 ? 1 : 0))),
      balloons: Math.max(1, Math.min(10, Math.round(area / 45))),
      link: roomLinks[r.id],
      goals: programme(r.id),
    };
  });
  // Fixed rooms order: the registry's (stable) order.
  rooms.sort((a, b) => a.idx - b.idx);

  // Pieces: every catalogue variation, with a thumbnail and its canonical link.
  const pieces = [];
  for (const c of catalog.collections) {
    for (const p of c.pieces) {
      const key = `${c.slug}/${p.id}`;
      if (!registry.pieces.includes(key)) registry.pieces.push(key);
      const etag = /[?&]v=([0-9a-f]+)/.exec(p.cover ?? '')?.[1] ?? '';
      let thumb = null;
      try { thumb = await thumbnail(c.slug, p.id, etag); } catch (e) { log(`thumbnail skipped for ${key}: ${e.message}`); }
      pieces.push({
        idx: registry.pieces.indexOf(key),
        c: c.slug,
        id: p.id,
        title: ascii(p.title),
        artist: ascii(p.traits?.Artist ?? p.artist ?? ''),
        tier: p.tier,
        url: linkUrl(findLinkPath(c.slug, p.id)),
        tint: thumb?.tint ?? 0xffff,
        pal: thumb?.pal,
        rle: thumb?.rle,
      });
    }
  }
  pieces.sort((a, b) => a.idx - b.idx);

  const collections = catalog.collections.map((c) => ({
    slug: c.slug,
    name: ascii(c.name),
    blurb: ascii(c.description),
    weights: c.rarityWeights ?? {},
    presence: c.hunt?.presence ?? {},
  }));

  const roomsHash = sha(JSON.stringify([GENERATED_ROOMS.map((r) => [r.id, r.name, r.claims, r.portals, r.warps]), rooms.map((r) => r.goals)]));
  const catalogHash = sha(JSON.stringify(catalog.collections.map((c) => [c.slug, c.rarityWeights, c.hunt, c.wild, c.pieces.map((p) => [p.id, p.title, p.tier, p.cover])])));
  const linksHash = sha(JSON.stringify(links.links ?? []));
  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));

  const data = {
    schema: DATA_SCHEMA,
    source: { mosa: source.commit.slice(0, 12), rooms: roomsHash, catalog: catalogHash },
    site: SITE,
    home: linkUrl('/at/defcon'),
    start: startRoom,
    thumb: { w: THUMB_W, h: THUMB_H },
    rooms,
    collections,
    pieces,
  };
  const header = [
    '-- GENERATED by tools/sync-mosa.mjs from the MOSA repo and api.mosa.center. Do not edit.',
    `-- MOSA ${source.describe}${source.dirty ? ' (dirty)' : ''} · rooms ${roomsHash} · catalog ${catalogHash} · schema ${DATA_SCHEMA}`,
    '',
  ].join('\n');
  const text = `${header}return ${lua(data)}\n`;

  const nextLock = {
    $comment: 'Written by `pnpm sync`. The registry is append-only: never reorder or delete an entry (shift-report bitmasks index into it).',
    schema: DATA_SCHEMA,
    generator: `mosa-badge@${pkg.version}`,
    mosa: { repo: 'bparticle/mosa', commit: source.commit, describe: source.describe, dirty: source.dirty },
    api: { url: API, catalog: catalogHash, links: linksHash },
    rooms: roomsHash,
    data: sha(text),
    registry,
  };

  if (CHECK) {
    const current = fs.existsSync(DATA_PATH) ? fs.readFileSync(DATA_PATH, 'utf8') : '';
    if (sha(current) !== nextLock.data) {
      log('STALE: src/data/mosa_data.lua differs from what MOSA would generate now.');
      log(`  rooms ${lock.rooms} → ${roomsHash}, catalog ${lock.api?.catalog} → ${catalogHash}`);
      process.exit(1);
    }
    log('up to date with MOSA', source.describe);
    return;
  }

  fs.mkdirSync(path.dirname(DATA_PATH), { recursive: true });
  fs.writeFileSync(DATA_PATH, text);
  fs.writeFileSync(LOCK_PATH, JSON.stringify(nextLock, null, 2) + '\n');
  log(`wrote ${path.relative(ROOT, DATA_PATH)} (${(text.length / 1024).toFixed(1)} KB): ${rooms.length} rooms, ${pieces.length} pieces, MOSA ${source.describe}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
