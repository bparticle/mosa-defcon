#!/usr/bin/env node
// pnpm preview [outDir]
//
// Plays the built app (apps/mosa/) on the headless Solana OS (tools/lib/host.mjs)
// and saves a screenshot of every screen to docs/screens/. Re-run after a change
// to see it without hardware. QR codes show as placeholders here; the real ones
// are drawn by Solana OS (see docs/BADGE.md for running the build on the real
// emulator).
import fs from 'node:fs';
import path from 'node:path';
import { SolanaOS } from './lib/host.mjs';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');

/** Launch the built app; past the splash unless `splash` is set. */
export async function bootApp(options = {}) {
  const badge = await new SolanaOS({ dir: path.join(ROOT, 'apps', 'mosa'), ...options }).launch();
  await badge.frames(3);
  // The splash skips on any button; most callers want the title.
  if (!options.splash) { await badge.press('a'); await badge.frames(2); }
  return badge;
}

const state = (b) => String(b.lua('return mosa_debug.state()'));

async function main() {
  const OUT = path.resolve(process.argv[2] ?? path.join(ROOT, 'docs', 'screens'));
  fs.mkdirSync(OUT, { recursive: true });
  const s = await bootApp({ splash: true });
  await s.frames(30); s.screenshot(path.join(OUT, '00-splash-pour.png'), 2);
  await s.frames(60); s.screenshot(path.join(OUT, '00-splash.png'), 2);
  const b = await bootApp();
  const shots = [];
  const shot = async (name) => {
    if (b.errors.length) throw new Error(`app error before ${name}: ${JSON.stringify(b.errors)}`);
    b.screenshot(path.join(OUT, `${name}.png`), 2);
    shots.push(`${name}  (${state(b)})`);
  };

  await b.frames(20);
  await shot('01-title');

  // The intro: the janitor's cupboard, then the flashlight clicks on.
  await b.press('a'); await b.frames(48);
  await shot('02-intro-cupboard');
  await b.frames(90);
  await shot('03-intro-flashlight');
  await b.press('a'); await b.frames(70);
  await shot('04-the-footage');
  await b.press('a'); await b.frames(2);
  await shot('04-briefing');
  await b.press('a'); await b.frames(10);
  await b.hold('up', 14); await b.hold('left', 6); await b.frames(2);
  await shot('05-lobby-walk');

  // A work on its wall, up close, and the way to the real one.
  b.lua('mosa_debug.travel("room1")'); await b.frames(70);
  b.lua('mosa_debug.near("art")'); b.lua('local gm = mosa_debug.game(); gm.py = gm.py + 1; gm.fy = -1; gm.fx = 0'); await b.frames(3);
  await shot('06-art-on-the-wall');
  b.lua('mosa_debug.near("art")'); await b.frames(2);
  await b.press('a'); await b.frames(2);
  await shot('07-art-card');
  await b.press('a'); await b.frames(2);
  await shot('08-see-it-in-hd');
  await b.press('b');

  // Tonight's first thief: the empty frame, the thief in the light, the work recovered.
  const heist = String(b.lua('return mosa_debug.heist()')).split(',');
  b.lua(`mosa_debug.travel("${heist[0]}")`); await b.frames(70);
  if (b.lua('return mosa_debug.near("missing")') === true) {
    await b.frames(2);
    await shot('09-empty-frame');
  }
  b.lua('mosa_debug.face_thief()'); await b.frames(8);
  await shot('10-thief-in-the-light');
  for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
  await shot('11-recovered');
  await b.press('b');

  b.lua('mosa_debug.to_bottle()'); await b.frames(4);
  await shot('12-bottle-card');
  await b.press('b');

  b.lua('mosa_debug.travel("room4")'); await b.frames(70); await b.hold('right', 16);
  await shot('13-community-gallery');

  await b.press('b');
  await shot('14-clipboard');
  await b.press('down'); await b.press('a'); await b.frames(2);
  await b.press('right'); await b.frames(2);
  await shot('15-museum-map');
  await b.press('left'); await b.frames(2);
  await b.press('b');
  await b.press('down'); await b.press('a'); await b.frames(10);
  await shot('16-the-art');
  await b.press('b');
  await b.press('down'); await b.press('a'); await b.frames(10);
  await shot('17-bottles');
  for (let i = 0; i < 4; i++) await b.press('down');
  await b.press('a'); await b.frames(4);
  await shot('18-shift-report-qr');
  await b.press('b'); await b.press('b'); await b.press('b');

  // The rest of tonight's thieves, and the lights come up.
  for (const id of heist.slice(1)) {
    b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
    b.lua('mosa_debug.face_thief()');
    for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
    await b.press('b'); await b.frames(2);
  }
  await b.frames(10);
  await shot('19-all-clear');
  await b.frames(100);

  b.meshIn('7K2Q9M', { w: '@pixeljanitor' }); await b.frames(3);
  await shot('20-wave-received');
  await b.frames(100);

  // The calm ends: the desk radios the next wave.
  b.lua('local n = mosa_debug.game().night; mosa_debug.clock(n.calm + 1)'); await b.frames(4);
  await shot('23-break-in');
  await b.frames(120);

  // Travel: SELECT on a walked room on the map, and the light closes in.
  b.lua('local R = require("record"); for i = 1, 64 do R.state.rooms[i] = true end');
  await b.press('b'); await b.press('down'); await b.press('a'); await b.frames(2);
  await b.press('right'); await b.press('a');
  await shot('22-teleport');
  await b.frames(60);

  // Dawn: the lights come up on the night.
  b.lua('mosa_debug.clock(1800)'); await b.frames(110);
  await shot('24-dawn');
  await b.press('b'); await b.frames(4);

  const t = await bootApp();
  for (let i = 0; i < 4; i++) await t.press('down');
  await t.press('a'); await t.frames(12);
  t.screenshot(path.join(OUT, '21-lanyard.png'), 2);
  await t.press('b'); await t.frames(4);
  for (let i = 0; i < 3; i++) await t.press('up');
  await t.press('a'); await t.frames(4);
  t.screenshot(path.join(OUT, '25-how-to-play.png'), 2);
  await t.press('right'); await t.frames(2);
  t.screenshot(path.join(OUT, '26-how-to-play-light.png'), 2);
  if (t.errors.length) throw new Error(JSON.stringify(t.errors));


  console.log(shots.join('\n'));
  if (b.errors.length) throw new Error(JSON.stringify(b.errors));
}

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('tools/preview.mjs')) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
