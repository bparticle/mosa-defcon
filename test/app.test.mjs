// Night Shift, played on the headless badge (the real Solana OS emulator from
// the vendored submodule) using the BUILT app in apps/mosa — the same bytes the
// App Store installs. Run `pnpm build` first (pnpm test does not rebuild).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { bootApp } from '../tools/preview.mjs';
import { decodeShift } from '../tools/lib/shift.mjs';
import { HeadlessBadge } from '../tools/lib/emulator.mjs';

const lock = JSON.parse(fs.readFileSync(new URL('../mosa.lock.json', import.meta.url), 'utf8'));
const state = (b) => String(b.lua('return mosa_debug.state()'));
const ROOMS = lock.registry.rooms;

test('boots to the title with no errors', async () => {
  const b = await bootApp();
  await b.frames(10);
  assert.deepEqual(b.errors, []);
  assert.match(state(b), /scene=title/);
  assert.ok(b.logs.some((l) => l.includes(`MOSA ${lock.mosa.commit.slice(0, 12)}`)), 'logs the MOSA commit it was built from');
});

test('opens on the splash, which skips on a button or hands over to the title by itself', async () => {
  const b = await bootApp({ splash: true });
  assert.match(state(b), /scene=splash/);
  await b.press('a');
  assert.match(state(b), /scene=title/);
  assert.match(state(b), /depth=1/, 'the skip press does not also choose a menu item');
  const c = await bootApp({ splash: true });
  await c.frames(120);
  assert.match(state(c), /scene=title/);
  assert.deepEqual([...b.errors, ...c.errors], []);
});

test('every room can be entered and drawn, within the heap budget', async () => {
  const b = await bootApp();
  await b.press('a'); await b.frames(4);
  for (const id of ROOMS) {
    b.lua(`mosa_debug.travel("${id}")`);
    await b.hold('down', 6); await b.hold('left', 6);
    assert.deepEqual(b.errors, [], `in ${id}`);
    assert.match(state(b), new RegExp(`room=${id}`));
  }
  await b.press('b'); await b.press('down'); await b.press('down'); await b.press('a'); // record screen
  await b.frames(3);
  const kb = Number(b.lua('collectgarbage() return collectgarbage("count")'));
  // The emulator's 64-bit Lua roughly doubles table cost vs the badge's 32-bit
  // build, so 640 KB here leaves real headroom under the badge's 1 MB cap.
  assert.ok(kb < 640, `heap ${kb.toFixed(0)} KB after visiting every room`);
  assert.deepEqual(b.errors, []);
});

test('a found bottle is kept across relaunches and shows up in the shift report', async () => {
  const b = await bootApp();
  await b.press('a'); await b.frames(3);
  const title = String(b.lua('return mosa_debug.to_bottle()'));
  await b.frames(3);
  assert.match(state(b), /scene=card .*found=1/);
  // Relaunch on a badge that kept its NVS.
  const kv = [...b.core.kv.entries];
  assert.ok(kv.length > 0, 'wrote to the key/value store');
  const again = await bootApp({ kv });
  assert.match(state(again), /found=1/, `kept ${title}`);
  // Decode the report the app would print, the way MOSA will.
  const shift = String(b.lua('return mosa_debug.report()'));
  const decoded = decodeShift(shift, lock.registry);
  assert.deepEqual(decoded.rooms, ['room0']);
  assert.equal(decoded.pieces.length, 1);
});

test('announces itself to other badges and hears waves', async () => {
  const b = await bootApp();
  await b.press('a'); await b.frames(100);
  assert.ok(b.espnowOut.some((m) => m.data.startsWith('MOSA1 P room0 ')), JSON.stringify(b.espnowOut.slice(0, 2)));
  b.espnowIn('aa:bb:cc:dd:ee:02', 'MOSA1 P room4 7');
  await b.frames(2);
  assert.equal(Number(b.lua('return mosa_debug.nearby()')), 1);
  b.espnowIn('aa:bb:cc:dd:ee:02', 'MOSA1 W Night_Owl');
  await b.frames(2);
  assert.deepEqual(b.errors, []);
});

test('a lone janitor never meets a mythical', async () => {
  const b = await bootApp();
  await b.press('a'); await b.frames(2);
  for (const id of ROOMS) b.lua(`mosa_debug.travel("${id}")`);
  await b.frames(1);
  assert.equal(String(b.lua('return mosa_debug.tiers()')).includes('mythical'), false);
});

test('ignores ESP-NOW traffic that is not Night Shift', async () => {
  const b = await bootApp();
  b.espnowIn('aa:bb:cc:dd:ee:03', 'hello from another app');
  b.espnowIn('aa:bb:cc:dd:ee:03', 'MOSA1 ');
  b.espnowIn('aa:bb:cc:dd:ee:03', 'MOSA1 Z ???');
  await b.frames(3);
  assert.deepEqual(b.errors, []);
});

test('the data module agrees with the lock file', async () => {
  const b = await new HeadlessBadge().boot();
  b.install('datat', {
    'data/mosa_data.lua': fs.readFileSync(new URL('../src/data/mosa_data.lua', import.meta.url)),
    'main.lua': `
      local D = require("data.mosa_data")
      local ids, problems = {}, {}
      for _, r in ipairs(D.rooms) do ids[r.id] = r end
      for _, r in ipairs(D.rooms) do
        for _, d in ipairs(r.doors) do
          if not ids[d.to] then problems[#problems + 1] = r.id .. " door to unknown " .. d.to end
        end
      end
      -- every room reachable from the start through doors
      local seen, queue = { [D.start] = true }, { D.start }
      while #queue > 0 do
        local r = ids[table.remove(queue)]
        for _, d in ipairs(r.doors) do if not seen[d.to] then seen[d.to] = true; queue[#queue + 1] = d.to end end
      end
      for id in pairs(ids) do if not seen[id] then problems[#problems + 1] = "unreachable " .. id end end
      for _, p in ipairs(D.pieces) do
        if p.url:sub(1, #D.site) ~= D.site then problems[#problems + 1] = "bad url " .. p.url end
        if not p.rle then problems[#problems + 1] = "no thumbnail " .. p.id end
      end
      badge.log("PROBLEMS " .. #problems .. " " .. table.concat(problems, "; "))
      badge.log("ROOMS " .. #D.rooms .. " PIECES " .. #D.pieces)`,
  });
  await b.launch('datat');
  await b.frames(1);
  const line = b.logs.find((l) => l.includes('PROBLEMS'));
  assert.match(line, /PROBLEMS 0 /, line);
  const counts = b.logs.find((l) => l.includes('ROOMS'));
  assert.match(counts, new RegExp(`ROOMS ${ROOMS.length} `));
});
