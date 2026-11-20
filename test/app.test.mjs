// Night Shift, played on the headless Solana OS (tools/lib/host.mjs) using the
// BUILT app in apps/mosa: the same files the App Store compiles and installs.
// Run `pnpm build` first (pnpm test does not rebuild).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { bootApp } from '../tools/preview.mjs';
import { decodeShift } from '../tools/lib/shift.mjs';
import { SolanaOS } from '../tools/lib/host.mjs';

const lock = JSON.parse(fs.readFileSync(new URL('../mosa.lock.json', import.meta.url), 'utf8'));
const data = fs.readFileSync(new URL('../src/data/mosa_data.lua', import.meta.url), 'utf8');
const HOME = data.match(/home="([^"]+)"/)[1];
const START = data.match(/start="([^"]+)"/)[1];
const state = (b) => String(b.lua('return mosa_debug.state()'));
const ROOMS = lock.registry.rooms;
const BUDGET = 200000;

// CLOCK IN, past the intro (a first shift only) and tonight's footage, into the first room.
async function clockIn(b) {
  await b.press('a'); await b.frames(2); // CLOCK IN
  if (/scene=intro/.test(state(b))) { await b.press('a'); await b.frames(2); } // skip the cupboard
  assert.match(state(b), /scene=briefing/);
  await b.press('a'); await b.frames(2); // fast-forward the tape to tonight's list
  assert.match(state(b), /scene=briefing/);
  await b.press('a'); await b.frames(10); // start the shift
  assert.match(state(b), /scene=game/);
}

/** The doors of a room in the data module, as room ids. */
function doorsOf(id) {
  const at = data.indexOf(`id="${id}"`);
  const block = data.slice(at, data.indexOf('marks=', at));
  return [...block.matchAll(/to="(room\d+)"/g)].map((m) => m[1]);
}

test('boots to the title with no errors, inside the instruction budget', async () => {
  const b = await bootApp();
  await b.frames(10);
  assert.deepEqual(b.errors, []);
  assert.match(state(b), /scene=title/);
  assert.ok(b.logs.some((l) => l.includes(`MOSA ${lock.mosa.commit.slice(0, 12)}`)), 'prints the MOSA commit it was built from');
  assert.ok(b.lastInstructions() < BUDGET / 4, `title tick ${b.lastInstructions()} instructions`);
});

test('opens on the splash, which skips on a button or hands over to the title by itself', async () => {
  const b = await bootApp({ splash: true });
  assert.match(state(b), /scene=splash/);
  await b.press('a');
  assert.match(state(b), /scene=title/);
  assert.match(state(b), /depth=1/, 'the skip press does not also choose a menu item');
  const c = await bootApp({ splash: true });
  await c.frames(130);
  assert.match(state(c), /scene=title/);
  assert.deepEqual([...b.errors, ...c.errors], []);
});

test('the shift starts in a cupboard, with a flashlight and a curator\'s note', async () => {
  const b = await bootApp();
  await b.press('a'); await b.frames(2);
  assert.match(state(b), /scene=intro/);
  await b.frames(220); // the whole intro plays out by itself
  assert.match(state(b), /scene=briefing/);
  // The footage plays out: a thief lifts a work and runs, then tonight's list.
  let peak = 0;
  for (let i = 0; i < 180; i++) { await b.frames(1); peak = Math.max(peak, b.lastInstructions()); }
  assert.ok(peak < BUDGET / 2, `briefing peak tick ${peak}`);
  assert.match(state(b), /scene=briefing/, 'the briefing waits for the janitor');
  await b.press('b');
  assert.match(state(b), /scene=title/, 'CANCEL on the note goes back to the front door');
  assert.deepEqual(b.errors, []);
});

test('CANCEL on the title leaves the app; anywhere else it steps back', async () => {
  const b = await bootApp();
  await clockIn(b);
  assert.equal(await b.press('b'), true, 'CANCEL in the museum is handled (opens the clipboard)');
  assert.match(state(b), /scene=pause/);
  await b.press('b'); await b.press('b'); // back to work, then the clipboard again
  await b.press('up'); await b.press('a'); // CLOCK OUT is the last item
  assert.match(state(b), /scene=title/);
  assert.notEqual(await b.press('b'), true, 'CANCEL on the title returns false: Solana OS closes the app');
});

test('SELECT and CANCEL act on a fresh press (repeat 0) and ignore held repeats', async () => {
  const b = await bootApp();
  await clockIn(b);
  assert.equal(b.call('on_key', 'back', 1), true, 'a held CANCEL repeat is swallowed');
  assert.match(state(b), /scene=game/);
  b.call('on_key', 'back', 0); await b.frames(2);
  assert.match(state(b), /scene=pause/, 'repeat 0 is a fresh press');
});

test('every room can be entered, walked and drawn, within the budgets', async () => {
  const b = await bootApp();
  await clockIn(b);
  let peak = 0;
  for (const id of ROOMS) {
    while (/scene=(card|artcard)/.test(state(b))) await b.press('b'); // a bottle walked into, a thief caught
    // Walk in the way a visitor does: the room is laid out across ticks.
    b.lua(`mosa_debug.game():travel("${id}", nil)`);
    for (let i = 0; i < 30 && !state(b).includes(`room=${id} `); i++) {
      await b.frames(1);
      peak = Math.max(peak, b.lastInstructions());
    }
    assert.match(state(b), new RegExp(`room=${id} `), `${id} laid out within 30 ticks`);
    for (const dir of ['up', 'right', 'down', 'left']) {
      await b.hold(dir, 6);
      peak = Math.max(peak, b.lastInstructions());
    }
    assert.deepEqual(b.errors, [], `in ${id}`);
    b.lua(`mosa_debug.travel("${id}")`); // back in the room, past any card a bottle opened
  }
  // Solana OS stops a callback past 200 000 instructions; keep a wide margin.
  assert.ok(peak < BUDGET / 2, `peak tick ${peak} instructions`);
  while (/scene=(card|artcard)/.test(state(b))) await b.press('b');
  await b.press('b'); await b.press('down'); await b.press('down'); await b.press('a'); // the art
  await b.frames(10);
  assert.match(state(b), /scene=art/);
  const kb = Number(b.lua('return __gc()'));
  // The badge gives an app 6 MB; Night Shift keeps to well under 1 MB (64-bit
  // Lua here roughly doubles table cost vs the badge's 32-bit build, and the
  // 140 KB canvas lives outside this count).
  assert.ok(kb < 640, `heap ${kb.toFixed(0)} KB after visiting every room`);
  assert.deepEqual(b.errors, []);
});

test('tonight there are thieves, the first of them one door from the start', async () => {
  const b = await bootApp();
  await clockIn(b);
  const heist = String(b.lua('return mosa_debug.heist()')).split(',');
  assert.equal(heist.length, 3);
  assert.equal(new Set(heist).size, 3, 'three different rooms');
  assert.ok(doorsOf(START).includes(heist[0]), `${heist[0]} is one door from ${START}`);
});

test('a thief held in the beam drops the work, and catching them all clears the night', async () => {
  const b = await bootApp();
  await clockIn(b);
  const heist = String(b.lua('return mosa_debug.heist()')).split(',');
  let peak = 0;
  for (const [n, id] of heist.entries()) {
    b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
    // The empty frame tells you what was taken.
    assert.equal(b.lua('return mosa_debug.near("missing")'), true, `an empty frame in ${id}`);
    await b.frames(2); await b.press('a');
    assert.match(state(b), /scene=plaque/);
    await b.press('b');
    assert.equal(b.lua('return mosa_debug.face_thief()'), true, `a thief in ${id}`);
    for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) { await b.frames(1); peak = Math.max(peak, b.lastInstructions()); }
    assert.match(state(b), new RegExp(`scene=artcard .*left=${2 - n} `), `caught in ${id}`);
    await b.press('a'); await b.frames(2); // see it in HD
    assert.match(b.qr()?.text ?? '', /^https:\/\//);
    await b.press('b'); await b.frames(2);
  }
  assert.match(state(b), /scene=finale/, 'the lights come up');
  await b.frames(100);
  await b.press('a'); await b.frames(2);
  assert.ok(b.qr()?.text.startsWith(`${HOME}?shift=`), 'the night ends one scan from the museum');
  assert.ok(peak < BUDGET / 2, `peak tick ${peak}`);
  assert.deepEqual(b.errors, []);
});

test('a work on its wall opens up close, joins the record, and links to the real one', async () => {
  const b = await bootApp();
  await clockIn(b);
  const room = ROOMS.find((id) => {
    const at = data.indexOf(`id="${id}"`);
    return /art=\{\s*\{w=/.test(data.slice(at, data.indexOf('goals=', at)));
  });
  b.lua(`mosa_debug.travel("${room}")`); await b.frames(2);
  assert.equal(b.lua('return mosa_debug.near("art")'), true);
  await b.frames(2);
  await b.press('a'); await b.frames(2);
  assert.match(state(b), /scene=artcard .*seen=1 /);
  await b.press('a'); await b.frames(2);
  const link = b.qr();
  assert.ok(link && /^https:\/\//.test(link.text) && link.text.length <= 256, JSON.stringify(link));
  const again = await bootApp({ storage: b.storageDump() });
  assert.match(state(again), /seen=1 /, 'kept across relaunches');
  assert.deepEqual(b.errors, []);
});

test('a thief who reaches a door gets away into the next room, and the hunt moves', async () => {
  const b = await bootApp();
  await clockIn(b);
  const heist = String(b.lua('return mosa_debug.heist()')).split(',');
  b.lua(`mosa_debug.travel("${heist[0]}")`); await b.frames(2);
  // Stand the thief beside a door into a room with no thief, the janitor close behind them.
  const to = b.lua(`
    local gm = mosa_debug.game()
    local th = gm.room.thief
    for _, d in ipairs(gm.room.data.doors) do
      if gm:open_to(d.to) then
        for _, o in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
          local x, y = d.x + 0.5 + o[1], d.y + 0.5 + o[2]
          if gm.room:walkable(x, y) and gm.room:walkable(x + o[1] * 2, y + o[2] * 2) then
            th.x, th.y = x, y
            gm.px, gm.py = x + o[1] * 2, y + o[2] * 2
            gm.fx, gm.fy = o[1], o[2] -- facing away: heard, not seen
            return d.to
          end
        end
      end
    end`);
  assert.ok(to, 'a door to run for');
  for (let i = 0; i < 60 && String(b.lua('return mosa_debug.heist()')).split(',')[0] === heist[0]; i++) await b.frames(1);
  assert.equal(String(b.lua('return mosa_debug.heist()')).split(',')[0], to, 'the hunt moved next door');
  b.lua(`mosa_debug.travel("${to}")`); await b.frames(2);
  assert.equal(b.lua('return mosa_debug.face_thief()'), true, 'the thief is in there');
  for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
  assert.match(state(b), /scene=artcard/, 'and can still be caught');
  assert.deepEqual(b.errors, []);
});

test('the map travels: SELECT on another room teleports there', async () => {
  const b = await bootApp();
  await clockIn(b);
  const here = /room=(\S+)/.exec(state(b))[1];
  await b.press('b'); await b.press('down'); await b.press('a'); await b.frames(4);
  assert.match(state(b), /scene=map/);
  await b.press('right'); await b.frames(2);
  await b.press('a'); await b.frames(40);
  assert.match(state(b), /scene=game/);
  const there = /room=(\S+)/.exec(state(b))[1];
  assert.notEqual(there, here, 'arrived somewhere else');
  // A second shift goes straight to the footage: the cupboard is for the first night.
  await b.press('b'); for (let i = 0; i < 5; i++) await b.press('down');
  await b.press('a'); await b.frames(2);
  assert.match(state(b), /scene=title/);
  await b.press('a'); await b.frames(2);
  assert.match(state(b), /scene=briefing/);
  assert.deepEqual(b.errors, []);
});

test('the museum map opens from the clipboard', async () => {
  const b = await bootApp();
  await clockIn(b);
  await b.press('b'); await b.press('down'); await b.press('a'); await b.frames(20);
  assert.match(state(b), /scene=map/);
  for (let i = 0; i < 14; i++) await b.press('right');
  assert.deepEqual(b.errors, []);
});

test('a found bottle is kept across relaunches and shows up in the shift report', async () => {
  const b = await bootApp();
  await clockIn(b);
  const title = String(b.lua('return mosa_debug.to_bottle()'));
  await b.frames(3);
  assert.match(state(b), /scene=card .*found=1/);
  // Relaunch on a badge that kept the app's storage.
  const saved = b.storageDump();
  assert.match(saved, /"found"/, 'wrote the record to storage');
  const again = await bootApp({ storage: saved });
  assert.match(state(again), /found=1/, `kept ${title}`);
  // Decode the report the app would show, the way MOSA does.
  const shift = String(b.lua('return mosa_debug.report()'));
  const decoded = decodeShift(shift, lock.registry);
  assert.deepEqual(decoded.rooms, [START]);
  assert.equal(decoded.pieces.length, 1);
});

test('the museum link and the shift report are QR codes Solana OS draws', async () => {
  const b = await bootApp();
  for (let i = 0; i < 3; i++) await b.press('down');
  await b.press('a'); await b.frames(2); // lanyard
  assert.equal(b.qr()?.text, HOME);
  await b.press('b');
  assert.equal(b.qr(), null, 'the code goes away with its screen');
  for (let i = 0; i < 3; i++) await b.press('up');
  await clockIn(b);
  b.lua('mosa_debug.to_bottle()'); await b.frames(3);
  await b.press('a'); await b.frames(2); // the card's museum link
  const link = b.qr();
  assert.ok(link && link.text.startsWith('https://'), JSON.stringify(link));
  assert.ok(link.size >= 25 && link.size <= 218 && link.text.length <= 256);
  await b.press('b');
  await b.press('b'); for (let i = 0; i < 3; i++) await b.press('down');
  await b.press('a'); await b.frames(10); // bottles
  assert.match(state(b), /scene=bottles/);
  for (let i = 0; i < 4; i++) await b.press('down');
  await b.press('a'); await b.frames(2);
  const report = b.qr();
  assert.ok(report && report.text.startsWith(`${HOME}?shift=`), JSON.stringify(report));
  const decoded = decodeShift(report.text.split('?shift=')[1], lock.registry);
  assert.equal(decoded.pieces.length, 1);
  assert.deepEqual(b.errors, []);
});

test('announces itself to other badges over the mesh and hears waves', async () => {
  const b = await bootApp();
  await clockIn(b); await b.frames(90);
  const presence = b.meshOut.filter((m) => m.to === '*' && m.msg.p === START);
  assert.ok(presence.length > 0, JSON.stringify(b.meshOut.slice(0, 2)));
  assert.ok(presence.length <= 4, 'a presence every couple of seconds, well under the mesh rate');
  b.meshIn('7K2Q9M', { p: 'room4', f: 7 });
  await b.frames(2);
  assert.equal(Number(b.lua('return mosa_debug.nearby()')), 1);
  b.meshIn('7K2Q9M', { w: '@nightowl' });
  await b.frames(2);
  assert.deepEqual(b.errors, []);
  // Waving back, from the clipboard.
  await b.press('b'); for (let i = 0; i < 4; i++) await b.press('down');
  await b.press('a');
  assert.ok(b.meshOut.some((m) => m.msg.w), 'sent a wave');
});

test('a lone janitor never meets a mythical', async () => {
  const b = await bootApp();
  await clockIn(b);
  for (const id of ROOMS) b.lua(`mosa_debug.travel("${id}")`);
  await b.frames(1);
  assert.equal(String(b.lua('return mosa_debug.tiers()')).includes('mythical'), false);
});

test('ignores mesh messages that are not Night Shift presence or waves', async () => {
  const b = await bootApp();
  b.meshIn('7K2Q9M', { hello: 'another app' });
  b.meshIn('7K2Q9M', { p: 42 });
  b.meshIn('7K2Q9M', { w: { nested: true } });
  b.lua('on_mesh(nil, nil)');
  await b.frames(3);
  assert.equal(Number(b.lua('return mosa_debug.nearby()')), 0);
  assert.deepEqual(b.errors, []);
});

test('the data module agrees with the lock file', async () => {
  const b = await new SolanaOS({
    files: {
      'data/mosa_data.lua': data,
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
          if #p.url > 256 then problems[#problems + 1] = "url too long for a QR code " .. p.url end
          if not p.rle then problems[#problems + 1] = "no thumbnail " .. p.id end
        end
        local works = {}
        for _, w in ipairs(D.works) do
          works[w.idx] = w
          if not w.url:match("^https://") or #w.url > 256 then problems[#problems + 1] = "bad work url " .. w.url end
          if not w.rle or w.sw > 24 or w.sh > 24 then problems[#problems + 1] = "bad miniature " .. w.title end
          if not ids[w.room] then problems[#problems + 1] = "work in unknown room " .. w.room end
        end
        for _, r in ipairs(D.rooms) do
          if r.balloons then problems[#problems + 1] = r.id .. " still has balloons" end
          for _, a in ipairs(r.art) do
            if not works[a.w] then problems[#problems + 1] = r.id .. " hangs unknown work " .. a.w end
            if a.x < 0 or a.y < 0 or a.x >= r.w or a.y >= r.h then problems[#problems + 1] = r.id .. " work off the plan" end
          end
          if #r.plan == 0 then problems[#problems + 1] = r.id .. " not on the map" end
        end
        print("PROBLEMS " .. #problems .. " " .. table.concat(problems, "; "))
        print("ROOMS " .. #D.rooms .. " PIECES " .. #D.pieces .. " WORKS " .. #D.works)`,
    },
  }).launch();
  assert.deepEqual(b.errors, []);
  const line = b.logs.find((l) => l.includes('PROBLEMS'));
  assert.match(line, /PROBLEMS 0 /, line);
  const counts = b.logs.find((l) => l.includes('ROOMS'));
  assert.match(counts, new RegExp(`ROOMS ${ROOMS.length} `));
  assert.match(counts, new RegExp(`WORKS ${lock.registry.works.length}$`), 'every registered work is on the badge');
});

// The badge runs Lua 5.5, where a for loop's variables are read-only; the host
// here is Lua 5.4 and would not notice. A line-based check, enough for src/.
test('no for loop assigns to its own loop variable (Lua 5.5)', () => {
  const dir = new URL('../src/', import.meta.url);
  const problems = [];
  for (const f of fs.readdirSync(dir, { recursive: true }).filter((f) => String(f).endsWith('.lua'))) {
    const lines = fs.readFileSync(new URL(String(f).replace(/\\/g, '/'), dir), 'utf8').split('\n');
    lines.forEach((line, i) => {
      const m = line.match(/^(\s*)(?:.*[\s;])?for\s+([\w\s,]+?)\s*(?:=|\bin\b)/);
      if (!m) return;
      const vars = m[2].split(',').map((v) => v.trim());
      const indent = m[1].length;
      for (let j = i + 1; j < lines.length; j++) {
        const l = lines[j];
        if (/^\s*end\b/.test(l) && l.match(/^\s*/)[0].length <= indent) break;
        for (const v of vars) {
          const assign = new RegExp(`(^|[;\\s])${v}\\s*(,[\\w\\s,]*)?=(?!=)`);
          const declares = new RegExp(`(local|for)\\s+[\\w\\s,]*\\b${v}\\b`);
          if (assign.test(l) && !declares.test(l)) problems.push(`src/${f}:${j + 1} assigns to loop variable ${v}`);
        }
      }
    });
  }
  assert.deepEqual(problems, []);
});

test('the build is a package Solana OS accepts', () => {
  const manifest = JSON.parse(fs.readFileSync(new URL('../apps/mosa/app.json', import.meta.url), 'utf8'));
  assert.match(manifest.id, /^[a-z0-9-]{3,24}$/);
  assert.ok(manifest.name.length <= 20);
  assert.deepEqual([...manifest.permissions].sort(), ['led', 'mesh']);
  const main = fs.statSync(new URL('../apps/mosa/main.lua', import.meta.url)).size;
  assert.ok(main <= 64 * 1024, `main.lua ${main} bytes`);
});
