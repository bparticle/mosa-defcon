#!/usr/bin/env node
// pnpm preview [outDir]
//
// Plays the built app (apps/mosa/) on the headless badge — the real Solana OS
// emulator from the vendored submodule — and saves a screenshot of every
// screen to docs/screens/. Re-run after a change to see it without hardware.
import fs from 'node:fs';
import path from 'node:path';
import { HeadlessBadge } from './lib/emulator.mjs';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const OUT = path.resolve(process.argv[2] ?? path.join(ROOT, 'docs', 'screens'));
fs.mkdirSync(OUT, { recursive: true });

export async function bootApp(options = {}) {
  const badge = await new HeadlessBadge(options).boot();
  const dir = path.join(ROOT, 'apps', 'mosa');
  badge.install('mosa', Object.fromEntries(fs.readdirSync(dir).map((f) => [f, fs.readFileSync(path.join(dir, f))])));
  await badge.launch('mosa');
  await badge.frames(3);
  return badge;
}

const state = (b) => String(b.lua('return mosa_debug.state()'));

async function main() {
  const b = await bootApp();
  const shots = [];
  const shot = async (name) => {
    if (b.errors.length) throw new Error(`app error before ${name}: ${JSON.stringify(b.errors)}`);
    b.screenshot(path.join(OUT, `${name}.png`), 2);
    shots.push(`${name}  (${state(b)})`);
  };

  await b.frames(20);
  await shot('01-title');

  await b.press('down'); await b.press('a'); await b.frames(12);
  await shot('02-lanyard');
  await b.press('b');

  await b.press('up'); await b.press('a'); await b.frames(10);
  await shot('03-lobby-arrival');
  await b.hold('up', 25); await b.hold('left', 12); await b.frames(4);
  await shot('04-lobby-walk');

  b.lua('mosa_debug.near("balloon")'); await b.frames(2);
  await shot('05-balloon-in-reach');
  await b.press('a', { after: 6 });
  await shot('06-balloon-pop');

  b.lua('mosa_debug.to_bottle()'); await b.frames(4);
  await shot('07-found-card');
  await b.press('a'); await b.frames(12);
  await shot('08-museum-link-qr');
  await b.press('b');

  b.lua('mosa_debug.travel("room1")'); await b.frames(6);
  await shot('09-floor1-corridor');
  b.lua('mosa_debug.travel("room4")'); await b.frames(3); await b.hold('right', 20);
  await shot('10-community-gallery');
  if (String(b.lua('return mosa_debug.near("mark")')) === 'true') {
    await b.frames(2);
    await b.press('a');
    await shot('11-plaque');
    await b.press('b');
  }

  await b.press('b');
  await shot('12-pause');
  await b.press('down'); await b.press('a');
  await shot('13-visitor-map');
  await b.press('b');
  await b.press('down'); await b.press('a');
  await shot('14-shift-record');
  for (let i = 0; i < 4; i++) await b.press('down');
  await b.press('a'); await b.frames(12);
  await shot('15-shift-report-qr');

  await b.press('b'); await b.press('b'); await b.press('b');
  b.espnowIn('aa:bb:cc:dd:ee:01', 'MOSA1 W Pixel_Janitor'); await b.frames(3);
  await shot('16-wave-received');

  console.log(shots.join('\n'));
  if (b.errors.length) throw new Error(JSON.stringify(b.errors));
}

if (import.meta.url === `file:///${process.argv[1].replace(/\\/g, '/')}` || process.argv[1].endsWith('preview.mjs')) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
