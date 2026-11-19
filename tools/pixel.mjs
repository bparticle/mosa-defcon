#!/usr/bin/env node
// pnpm pixel <command>
//
//   sheet                       docs/pixel-sheet.png: every bottle, cover beside
//                               its badge sprite (8x), marked HAND or AUTO
//   starter                     art/starter/<c>/<p>.png: the automatic sprite for
//                               every bottle with no hand art yet, at 1x and 8x —
//                               open the 1x in Aseprite and clean it up
//   import <image> <c>/<p> [--colours N]
//                               snap any image (a ChatGPT or PixelLab output, a
//                               scan, a drawing) to a badge sprite and save it as
//                               art/pixel/<c>/<p>.png, plus an 8x preview
//   check                       validate everything in art/pixel/
//
// Hand art in art/pixel/ must be exactly 16x24, alpha 0 or 255, at most 15
// colours. `pnpm sync` uses it instead of the pixelized cover and fails on a
// file that breaks the rules.
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
import { W, H, pixelize, validateSprite, toPng } from './lib/pixel.mjs';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const API = (process.env.MOSA_API ?? 'https://api.mosa.center').replace(/\/$/, '');
const PIXEL = path.join(ROOT, 'art', 'pixel');
const STARTER = path.join(ROOT, 'art', 'starter');
const CACHE = path.join(ROOT, '.cache', 'thumbs');
const [cmd, ...rest] = process.argv.slice(2);

function pieces() {
  const lock = JSON.parse(fs.readFileSync(path.join(ROOT, 'mosa.lock.json'), 'utf8'));
  return lock.registry.pieces.map((key) => { const [c, p] = key.split('/'); return { key, c, p }; });
}

async function cover(c, p) {
  fs.mkdirSync(CACHE, { recursive: true });
  const cached = fs.readdirSync(CACHE).find((f) => f.startsWith(`${c}--${p}--`));
  if (cached) return fs.readFileSync(path.join(CACHE, cached));
  const res = await fetch(`${API}/finds/media/${c}/${p}/cover`);
  if (!res.ok) throw new Error(`cover ${c}/${p}: HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(path.join(CACHE, `${c}--${p}--x.png`), buf);
  return buf;
}

const handPath = (c, p) => path.join(PIXEL, c, `${p}.png`);

async function spriteFor(c, p) {
  if (fs.existsSync(handPath(c, p))) {
    const { sprite, errors } = await validateSprite(fs.readFileSync(handPath(c, p)));
    if (errors) throw new Error(`art/pixel/${c}/${p}.png ${errors.join('; ')}`);
    return { sprite, hand: true };
  }
  return { sprite: await pixelize(await cover(c, p)), hand: false };
}

async function sheet() {
  const list = pieces();
  const S = 6, cw = W * S * 2 + 30, ch = H * S + 34, cols = 6;
  const rows = Math.ceil(list.length / cols);
  const layers = [];
  for (const [i, { c, p }] of list.entries()) {
    const x = (i % cols) * cw + 10, y = Math.floor(i / cols) * ch + 10;
    const { sprite, hand } = await spriteFor(c, p);
    const src = await sharp(await cover(c, p)).resize(W * S, H * S, { fit: 'contain', background: '#18181800' }).png().toBuffer();
    layers.push({ input: src, left: x, top: y });
    layers.push({ input: await toPng(sprite, S), left: x + W * S + 10, top: y });
    const label = `<svg width="${cw}" height="20"><text x="0" y="14" font-family="monospace" font-size="12" fill="${hand ? '#7ee8a8' : '#8a8680'}">${hand ? 'HAND' : 'AUTO'} ${p.slice(0, 22)}</text></svg>`;
    layers.push({ input: Buffer.from(label), left: x, top: y + H * S + 4 });
  }
  const out = path.join(ROOT, 'docs', 'pixel-sheet.png');
  await sharp({ create: { width: cols * cw + 10, height: rows * ch + 10, channels: 3, background: '#181818' } })
    .composite(layers).png().toFile(out);
  const hand = list.filter(({ c, p }) => fs.existsSync(handPath(c, p))).length;
  console.log(`[pixel] ${path.relative(ROOT, out)}: ${hand} of ${list.length} hand-made`);
}

async function starter() {
  let n = 0;
  for (const { c, p } of pieces()) {
    if (fs.existsSync(handPath(c, p))) continue;
    const { sprite } = await spriteFor(c, p);
    fs.mkdirSync(path.join(STARTER, c), { recursive: true });
    fs.writeFileSync(path.join(STARTER, c, `${p}.png`), await toPng(sprite, 1));
    fs.writeFileSync(path.join(STARTER, c, `${p}@8x.png`), await toPng(sprite, 8));
    n++;
  }
  console.log(`[pixel] ${n} starters in art/starter/ (1x to edit, @8x to look at). Finished art goes in art/pixel/<collection>/<piece>.png`);
}

async function importImage() {
  const [file, key] = rest.filter((a, i) => !a.startsWith('--') && rest[i - 1] !== '--colours');
  const ci = rest.indexOf('--colours');
  const colours = ci >= 0 ? Number(rest[ci + 1]) : 12;
  if (!file || !key || !key.includes('/')) throw new Error('usage: pnpm pixel import <image> <collection>/<piece> [--colours N]');
  if (!pieces().some((x) => x.key === key)) console.warn(`[pixel] warning: ${key} is not in the registry (yet)`);
  const [c, p] = key.split('/');
  const sprite = await pixelize(fs.readFileSync(file), { colours });
  fs.mkdirSync(path.join(PIXEL, c), { recursive: true });
  fs.writeFileSync(handPath(c, p), await toPng(sprite, 1));
  fs.mkdirSync(path.join(ROOT, '.cache', 'pixel'), { recursive: true });
  const preview = path.join(ROOT, '.cache', 'pixel', `${c}--${p}@8x.png`);
  fs.writeFileSync(preview, await toPng(sprite, 8));
  console.log(`[pixel] art/pixel/${c}/${p}.png (${sprite.centres.length} colours); preview ${path.relative(ROOT, preview)}`);
  console.log('[pixel] clean it up by hand if it needs it, then pnpm sync && pnpm build');
}

async function check() {
  let bad = 0, n = 0;
  if (!fs.existsSync(PIXEL)) { console.log('[pixel] no art/pixel/ yet'); return; }
  const known = new Set(pieces().map((x) => x.key));
  for (const c of fs.readdirSync(PIXEL)) {
    if (!fs.statSync(path.join(PIXEL, c)).isDirectory()) continue;
    for (const f of fs.readdirSync(path.join(PIXEL, c)).filter((x) => x.endsWith('.png'))) {
      n++;
      const key = `${c}/${f.slice(0, -4)}`;
      const { errors } = await validateSprite(fs.readFileSync(path.join(PIXEL, c, f)));
      if (errors) { bad++; console.log(`  FAIL ${key}: ${errors.join('; ')}`); }
      else if (!known.has(key)) console.log(`  ok, but ${key} is not a known piece (typo?)`);
    }
  }
  console.log(`[pixel] ${n - bad} of ${n} hand sprites valid`);
  if (bad) process.exit(1);
}

const commands = { sheet, starter, import: importImage, check };
if (!commands[cmd]) {
  console.log('usage: pnpm pixel sheet | starter | import <image> <collection>/<piece> | check');
  process.exit(cmd ? 1 : 0);
}
commands[cmd]().catch((e) => { console.error(e.message); process.exit(1); });
