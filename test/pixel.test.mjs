// The sprite pipeline (tools/lib/pixel.mjs): bottles stand upright on the badge.
// The cover renders lean in the frame like the static posters; at 16x24 that lean
// is a staircase, so pixelize() stands a bottle up before it snaps to the grid.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { W, H, pixelize, shapeAxis } from '../tools/lib/pixel.mjs';

const PAPER = '#e8e6e0';

/** A flat bottle-ish silhouette on the cover's paper backdrop, leaning by `deg`. */
async function cover(shape, deg) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">
    <rect width="512" height="512" fill="${PAPER}"/>
    <g transform="rotate(${deg} 256 256)" fill="#1d5a2a">${shape}</g></svg>`;
  return sharp(Buffer.from(svg)).png().toBuffer();
}
const BOTTLE = '<rect x="226" y="40" width="60" height="150"/><rect x="196" y="170" width="120" height="300" rx="14"/>';
const BLOB = '<ellipse cx="256" cy="256" rx="170" ry="200"/>';

/** Lean (degrees from vertical) and elongation of a sprite's silhouette. */
function lean({ idx }) {
  const rgba = Buffer.alloc(W * H * 4);
  idx.forEach((v, i) => { if (v) rgba[i * 4 + 3] = 255; });
  return shapeAxis(rgba, W, H);
}

test('a leaning bottle is stood upright, in either direction', async () => {
  for (const deg of [-9, -5, 5, 9]) {
    const png = await cover(BOTTLE, deg);
    const flat = lean(await pixelize(png, { upright: false }));
    const up = lean(await pixelize(png));
    assert.ok(Math.abs(flat.lean) > 3, `${deg}°: the untouched sprite leans ${flat.lean.toFixed(1)}° (the test needs a lean to fix)`);
    assert.ok(Math.abs(up.lean) < 1.5, `${deg}°: the sprite still leans ${up.lean.toFixed(1)}°`);
  }
});

test('a shape with no long axis is left as drawn', async () => {
  const png = await cover(BLOB, 20);
  const a = await pixelize(png, { upright: false });
  const b = await pixelize(png);
  assert.deepEqual([...b.idx], [...a.idx]);
});

test('an upright bottle is left as drawn', async () => {
  const png = await cover(BOTTLE, 0);
  const a = await pixelize(png, { upright: false });
  const b = await pixelize(png);
  assert.deepEqual([...b.idx], [...a.idx]);
});
