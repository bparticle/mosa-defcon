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

// Past the holding cell (and any calling card) a cleared break-in plays, back to the walk.
async function toWalk(b) {
  for (let i = 0; i < 6 && !/scene=game/.test(state(b)); i++) { await b.press('b'); await b.frames(2); }
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
  assert.match(state(b), /scene=dawn/, 'clocking out ends the shift with its report');
  await b.frames(40); await b.press('b');
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
  // 140 KB canvas lives outside this count). 0.7.0 sat at 636 KB; the thieves'
  // kinds, the weather, calling cards and the vignettes added ~40 KB of code.
  assert.ok(kb < 704, `heap ${kb.toFixed(0)} KB after visiting every room`);
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
    // The empty frame shows what was taken; SELECT there opens nothing.
    assert.equal(b.lua('return mosa_debug.near("missing")'), true, `an empty frame in ${id}`);
    await b.frames(2); await b.press('a');
    assert.match(state(b), /scene=game/);
    assert.equal(b.lua('return mosa_debug.face_thief()'), true, `a thief in ${id}`);
    for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) { await b.frames(1); peak = Math.max(peak, b.lastInstructions()); }
    assert.match(state(b), new RegExp(`scene=artcard .*left=${2 - n} `), `caught in ${id}`);
    await b.press('a'); await b.frames(2); // see it in HD
    assert.match(b.qr()?.text ?? '', /^https:\/\//);
    await b.press('b'); await b.frames(2);
  }
  assert.match(state(b), /scene=holding/, 'a cleared break-in: the thieves go behind bars');
  await toWalk(b);
  assert.match(state(b), /scene=game/, 'a cleared wave keeps the night going');
  assert.match(String(b.lua('return mosa_debug.night()')), /recovered=3 lost=0 calm=\d+/, 'and the desk waits to radio the next');
  b.lua(`mosa_debug.clock(${30 * 60})`); await b.frames(4);
  assert.match(state(b), /scene=dawn/, 'the lights come up at dawn');
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
  // Only rooms walked before can be travelled to: first, one that hasn't been.
  await b.press('b'); await b.press('down'); await b.press('a'); await b.frames(4);
  assert.match(state(b), /scene=map/);
  await b.press('right'); await b.frames(2);
  await b.press('a'); await b.frames(4);
  assert.match(state(b), /scene=map/, 'an unwalked room is out of reach');
  await b.press('b'); await b.press('b'); // the map, then the clipboard
  b.lua('local R = require("record"); for _, r in ipairs(require("data.mosa_data").rooms) do R.state.rooms[r.idx] = true end');
  const before = Number(/min=(\d+)/.exec(String(b.lua('return mosa_debug.night()')))[1]);
  await b.press('b'); await b.press('down'); await b.press('a'); await b.frames(4);
  await b.press('right'); await b.frames(2);
  await b.press('a'); await b.frames(40);
  assert.match(state(b), /scene=game/);
  const there = /room=(\S+)/.exec(state(b))[1];
  assert.notEqual(there, here, 'arrived somewhere else');
  const after = Number(/min=(\d+)/.exec(String(b.lua('return mosa_debug.night()')))[1]);
  assert.ok(after - before >= 20, `the trip cost twenty minutes of the night (${before} to ${after})`);
  // A second shift goes straight to the footage: the cupboard is for the first night.
  await b.press('b'); for (let i = 0; i < 5; i++) await b.press('down');
  await b.press('a'); await b.frames(40); await b.press('b'); await b.frames(2);
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
  for (let i = 0; i < 4; i++) await b.press('down');
  await b.press('a'); await b.frames(2); // lanyard
  assert.equal(b.qr()?.text, HOME);
  await b.press('b');
  assert.equal(b.qr(), null, 'the code goes away with its screen');
  for (let i = 0; i < 4; i++) await b.press('up');
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
  // !LAMPs are a build switch (tools/bundle.mjs): the permission is asked for
  // exactly when build_info says the game awards them.
  const lampsOn = /lamps = true/.test(fs.readFileSync(new URL('../apps/mosa/build_info.lua', import.meta.url), 'utf8'));
  assert.deepEqual([...manifest.permissions].sort(), ['background', ...(lampsOn ? ['lamps'] : []), 'led', 'mesh']);
  const main = fs.statSync(new URL('../apps/mosa/main.lua', import.meta.url)).size;
  assert.ok(main <= 64 * 1024, `main.lua ${main} bytes`);
});

// ── the night ──────────────────────────────────────────────────────────────
const nightOf = (b) => String(b.lua('return mosa_debug.night()'));
const minOf = (b) => Number(/min=(\d+)/.exec(nightOf(b))[1]);

test('the night runs on a clock that the clipboard stops, and dawn ends it', async () => {
  const b = await bootApp();
  await clockIn(b);
  const m0 = minOf(b);
  assert.equal(m0, 23 * 60 + 41, 'the shift starts at 23:41');
  await b.frames(120);
  const m1 = minOf(b);
  assert.ok(m1 > m0, `the clock runs while you walk (${m0} to ${m1})`);
  await b.press('b'); await b.frames(120);
  assert.equal(minOf(b), m1, 'and stops while the clipboard is up');
  await b.press('b');
  b.lua(`mosa_debug.clock(${30 * 60})`); await b.frames(3);
  assert.match(state(b), /scene=dawn/);
  assert.match(nightOf(b), /lost=3/, 'the thieves still inside leave with the light');
  assert.equal(b.lua('return service.running()'), true, 'after a dawn the desk offers its evening call');
  assert.deepEqual(b.errors, []);
});

test('clearing a break-in brings the next one, sized by the desk', async () => {
  const b = await bootApp();
  await clockIn(b);
  for (const id of String(b.lua('return mosa_debug.heist()')).split(',')) {
    b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
    b.lua('mosa_debug.face_thief()');
    for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
    await b.press('b'); await b.frames(2);
  }
  await toWalk(b);
  const calm = Number(/calm=(\d+)/.exec(nightOf(b))[1]);
  b.lua(`mosa_debug.clock(${calm + 1})`); await b.frames(3);
  assert.match(nightOf(b) + ' ' + state(b), /wave=2/, 'the desk radios a second wave');
  const left = Number(/left=(\d+)/.exec(state(b))[1]);
  assert.ok(left >= 1 && left <= 3, `with one to three thieves (${left})`);
  const next = String(b.lua('return mosa_debug.heist()')).split(',').slice(3);
  b.lua(`mosa_debug.travel("${next[0]}")`); await b.frames(2);
  assert.equal(b.lua('return mosa_debug.face_thief()'), true, 'and its thief is in the room the desk named');
  for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
  assert.match(state(b), /scene=artcard/);
  assert.deepEqual(b.errors, []);
});

// Clear tonight's first break-in, thief by thief, and come back to the walk.
async function clearFirstWave(b) {
  for (const id of String(b.lua('return mosa_debug.heist()')).split(',')) {
    b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
    b.lua('mosa_debug.face_thief()');
    for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
    await b.press('b'); await b.frames(2);
  }
}

test('a cleared break-in leaves a calling card; waiting in its room catches the next thief in the act', async () => {
  const b = await bootApp();
  await clockIn(b);
  await clearFirstWave(b);
  assert.match(state(b), /scene=holding/);
  for (let i = 0; i < 200 && !/scene=callingcard/.test(state(b)); i++) await b.frames(1);
  assert.match(state(b), /scene=callingcard/, 'one of them flicks a card at the camera');
  const [body, room] = String(b.lua('return mosa_debug.card()')).split(' / ');
  assert.ok(ROOMS.includes(room), `the card names a real room (${room})`);
  assert.match(body, /one door from|starts with|works? hangs?/, `with a clue to find it by: ${body}`);
  await toWalk(b);
  // The clipboard keeps the card.
  await b.press('b'); await b.frames(2);
  await b.press('down'); await b.press('a'); await b.frames(2);
  assert.match(state(b), /scene=callingcard/);
  await toWalk(b);
  // Be there when they come.
  b.lua(`mosa_debug.travel("${room}")`); await b.frames(2);
  const calm = Number(/calm=(\d+)/.exec(nightOf(b))[1]);
  b.lua(`mosa_debug.clock(${calm + 1})`); await b.frames(3);
  assert.match(state(b), /scene=intheact/, 'caught in the act');
  assert.match(nightOf(b), /prevented=1/);
  assert.ok(!String(b.lua('return mosa_debug.heist()')).split(',').slice(3).includes(room), 'nothing was taken from that room');
  for (let i = 0; i < 200 && !/scene=(game|holding)/.test(state(b)); i++) await b.frames(1);
  await toWalk(b);
  assert.match(state(b), /scene=game/);
  assert.deepEqual(b.errors, []);
});

test('the kinds of thief: a statue poses in a steady light, a swindler drops a dummy', async () => {
  const b = await bootApp();
  await clockIn(b);
  const id = String(b.lua('return mosa_debug.heist()')).split(',')[0];
  b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
  assert.equal(b.lua('return mosa_debug.face_thief("statue")'), true);
  await b.frames(80);
  assert.match(state(b), /scene=game/, 'a statue held in a steady beam just poses');
  // Look away, then back: only a fresh look counts.
  for (let i = 0; i < 12 && !/scene=artcard/.test(state(b)); i++) {
    b.lua('local gm = mosa_debug.game(); gm.fx, gm.fy = -gm.fx, -gm.fy'); await b.frames(3);
    b.lua('local gm = mosa_debug.game(); gm.fx, gm.fy = -gm.fx, -gm.fy');
    for (let j = 0; j < 12 && !/scene=artcard/.test(state(b)); j++) await b.frames(1);
  }
  for (let i = 0; i < 40 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
  assert.match(state(b), /scene=artcard/, 'caught by looking again and again');
  await b.press('b'); await b.frames(2);

  const id2 = String(b.lua('return mosa_debug.heist()')).split(',')[1];
  b.lua(`mosa_debug.travel("${id2}")`); await b.frames(2);
  assert.equal(b.lua('return mosa_debug.face_thief("swindler")'), true);
  for (let i = 0; i < 60 && !b.lua('return mosa_debug.game().room.dummy ~= nil'); i++) await b.frames(1);
  assert.equal(b.lua('return mosa_debug.game().room.dummy ~= nil'), true, 'the first time, a dummy');
  assert.match(state(b), /scene=game/, 'and they still have the work');

  // A dodger weaves out of the beam, in a storm: lightning shows them for a blink.
  const id3 = String(b.lua('return mosa_debug.heist()')).split(',')[2];
  b.lua(`mosa_debug.travel("${id3}")`); await b.frames(2);
  b.lua('local gm = mosa_debug.game(); gm.weather = require("caper").NIGHTS[2]; gm.storm = 0.05');
  assert.equal(b.lua('return mosa_debug.face_thief("dodger")'), true);
  b.lua('mosa_debug.game().room.thief.stay = nil');
  let bolt = false;
  for (let i = 0; i < 30; i++) { await b.frames(1); bolt = bolt || b.lua('return require("world").bolt') === true; }
  assert.ok(bolt, 'the lightning struck');
  assert.deepEqual(b.errors, []);
});

test('nights count by the day: a streak grows, and lapses when a day is missed', async () => {
  const b = await bootApp();
  const run = (lua) => b.lua(`local R = require("record"); ${lua}`);
  assert.equal(run('return R.clock_in(20000)'), true, 'the first shift of a day starts a night');
  assert.equal(run('return R.clock_in(20000)'), false, 'a second shift that day does not');
  run('R.clock_in(20001); R.clock_in(20002)');
  assert.equal(run('return R.streak_now(20002)'), 3);
  assert.equal(run('return R.streak_now(20004)'), 0, 'a missed day ends the streak');
  run('R.clock_in(20005)');
  assert.equal(run('return R.state.streak .. "," .. R.state.best_streak .. "," .. R.state.nights'), '1,3,4');
});

test('a build without !LAMPs never asks for an award', async () => {
  const b = await bootApp();
  b.lua('require("build_info").lamps = false');
  await clockIn(b);
  const id = String(b.lua('return mosa_debug.heist()')).split(',')[0];
  b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
  b.lua('mosa_debug.face_thief()');
  for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
  assert.equal(String(b.lua('return __lamps_log()')), '', 'no award was asked for');
  await b.press('b'); await b.frames(3);
  assert.match(nightOf(b), /lamps=0/);
  assert.deepEqual(b.errors, []);
});

// The switch on (tools/bundle.mjs LAMPS = true), whatever this build ships with.
test('recovered works earn !LAMPs; an owner without X is told how', async () => {
  const b = await bootApp();
  b.lua('require("build_info").lamps = true');
  await clockIn(b);
  const id = String(b.lua('return mosa_debug.heist()')).split(',')[0];
  b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
  b.lua('mosa_debug.face_thief()');
  for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
  assert.match(String(b.lua('return __lamps_log()')), /^3 Recovered /);
  await b.press('b'); await b.frames(3);
  assert.match(nightOf(b), /lamps=3/, 'the award comes back and is counted for the report');

  const c = await bootApp();
  c.lua('require("build_info").lamps = true; __lamps_mode = "needsX"');
  await clockIn(c);
  const id2 = String(c.lua('return mosa_debug.heist()')).split(',')[0];
  c.lua(`mosa_debug.travel("${id2}")`); await c.frames(2);
  c.lua('mosa_debug.face_thief()');
  for (let i = 0; i < 100 && !/scene=artcard/.test(state(c)); i++) await c.frames(1);
  await c.press('b'); await c.frames(3);
  assert.match(nightOf(c), /lamps=0/);
  assert.deepEqual([...b.errors, ...c.errors], []);
});

// The arcade cabinet's host passes lamps: false (tools/web/host-browser.mjs): the badge's
// allowance is the badge's, so a cabinet never awards !LAMPs, even in a build that has them.
test('a host without !LAMPs (the arcade cabinet) never asks for an award', async () => {
  const b = await bootApp({ cabinet: { open: () => {} }, lamps: false });
  b.lua('require("build_info").lamps = true');
  assert.equal(b.lua('return lamps'), null, 'no lamps global');
  await clockIn(b);
  const id = String(b.lua('return mosa_debug.heist()')).split(',')[0];
  b.lua(`mosa_debug.travel("${id}")`); await b.frames(2);
  b.lua('mosa_debug.face_thief()');
  for (let i = 0; i < 100 && !/scene=artcard/.test(state(b)); i++) await b.frames(1);
  assert.match(state(b), /scene=artcard/);
  assert.equal(String(b.lua('return __lamps_log()')), '', 'no award was asked for');
  await b.press('b'); await b.frames(3);
  assert.match(nightOf(b), /lamps=0/);
  assert.deepEqual(b.errors, []);
});

// What How to play draws on its last page, caught as the desk's paragraph and tracked label
// are drawn: the page that tells how to earn !LAMPs, where the host has them.
async function lastHowToPage(b) {
  await b.frames(80);
  await b.press('down'); await b.press('a'); await b.frames(2);
  assert.match(state(b), /scene=howto/);
  b.lua('texts = {}; local kit = require("kit"); local para, tracked = kit.paragraph, kit.tracked;'
    + ' kit.paragraph = function(s, ...) texts[#texts + 1] = tostring(s); return para(s, ...) end;'
    + ' kit.tracked = function(s, ...) texts[#texts + 1] = tostring(s); return tracked(s, ...) end');
  for (let i = 0; i < 4; i++) { await b.press('right'); await b.frames(1); }
  b.lua('texts = {}');
  await b.press('right'); await b.frames(2); // the sixth and last page
  return String(b.lua('return table.concat(texts, " | ")'));
}

// The other half of the cabinet's fix: the build has !LAMPs in both runs, so the host decides
// whether How to play mentions them. The badge says how to earn them; the cabinet says nothing.
test('how to play mentions !LAMPs only on a host that has them', async () => {
  const badge = await bootApp();
  badge.lua('require("build_info").lamps = true');
  const on = await lastHowToPage(badge);
  assert.match(on, /EVERY NIGHT/, 'the last page is the one drawn');
  assert.match(on, /!LAMPS/, 'its picture is labelled !LAMPS');
  assert.match(on, /earn !LAMPs/, 'and its text says how to earn them');

  const cabinet = await bootApp({ cabinet: { open: () => {} }, lamps: false });
  cabinet.lua('require("build_info").lamps = true');
  const off = await lastHowToPage(cabinet);
  assert.match(off, /EVERY NIGHT/, 'the last page is the one drawn');
  assert.match(off, /EVERY BOTTLE/, 'its picture is labelled for the bottles instead');
  assert.doesNotMatch(off, /lamps/i, 'and nothing on it mentions !LAMPs');
  assert.deepEqual([...badge.errors, ...cabinet.errors], []);
});

test('how to play turns its pages', async () => {
  const b = await bootApp();
  await b.frames(80);
  await b.press('down'); await b.press('a'); await b.frames(2);
  assert.match(state(b), /scene=howto/);
  for (let i = 0; i < 6; i++) { await b.press('right'); await b.frames(1); }
  await b.press('b');
  assert.match(state(b), /scene=title/);
  assert.deepEqual(b.errors, []);
});

test('the desk calls once in the evening, and not on a night already worked', async () => {
  const b = await bootApp();
  // The service runs in a state of its own on the badge; here, in place of the app.
  b.lua('notices = {}; service.notify = function(t) notices[#notices + 1] = t; return true end; service.status = function() end; require("service")');
  const calls = () => Number(b.lua('return #notices'));
  const tick = () => b.call('on_tick', 300000);
  tick();
  assert.equal(calls(), 0, 'not in the afternoon');
  b.lua('__time_shift(4 * 3600)'); tick();
  assert.equal(calls(), 1, 'at six in the evening it calls');
  tick();
  assert.equal(calls(), 1, 'once a day');
  b.lua('__time_shift(86400)');
  b.lua('local d = storage.get("desk"); d.worked = sys.time() // 86400; storage.set("desk", d)');
  tick();
  assert.equal(calls(), 1, 'not when tonight is already worked');
  b.lua('__time_shift(86400)'); tick();
  assert.equal(calls(), 2, 'and again the next evening');
  assert.deepEqual(b.errors, []);
});

test('in the arcade cabinet a work is walked to, not scanned: cabinet.open, and no QR', async () => {
  const opened = [];
  const b = await bootApp({ cabinet: { open: (url) => opened.push(url) } });
  for (let i = 0; i < 4; i++) await b.press('down');
  await b.press('a'); await b.frames(2); // lanyard: an attract screen, no code to scan
  assert.equal(b.qr(), null);
  assert.ok(b.lastInstructions() < BUDGET);
  await b.press('b');
  for (let i = 0; i < 4; i++) await b.press('up');
  await clockIn(b);
  const room = ROOMS.find((id) => {
    const at = data.indexOf(`id="${id}"`);
    return /art=\{\s*\{w=/.test(data.slice(at, data.indexOf('goals=', at)));
  });
  b.lua(`mosa_debug.travel("${room}")`); await b.frames(2);
  assert.equal(b.lua('return mosa_debug.near("art")'), true);
  await b.frames(2);
  await b.press('a'); await b.frames(2); // the work up close
  assert.match(state(b), /scene=artcard/);
  await b.press('a'); await b.frames(2); // SEE IT IN HD
  assert.match(state(b), /scene=code/);
  assert.equal(b.qr(), null, 'the cabinet draws no QR code');
  await b.press('a'); await b.frames(1);
  await new Promise((r) => setTimeout(r, 0)); // the visit begins after the callback returns
  assert.equal(opened.length, 1);
  assert.match(opened[0], /^https:\/\/[^/]+\/at\/work\/[a-z0-9-]+$/);
  assert.doesNotMatch(state(b), /scene=code/, 'and the card steps back for when the visitor returns');
  assert.deepEqual(b.errors, []);
});

test('the browser host core runs the app from a files map, its storage as JSON', async () => {
  const { SolanaOS: CoreOS } = await import('../tools/lib/host-core.mjs');
  const dir = new URL('../apps/mosa/', import.meta.url);
  const files = {};
  for (const rel of fs.readdirSync(dir, { recursive: true })) {
    const file = new URL(String(rel).split(String.fromCharCode(92)).join('/'), dir);
    if (fs.statSync(file).isFile()) files[String(rel).split(String.fromCharCode(92)).join('/')] = fs.readFileSync(file, 'utf8');
  }
  const b = await new CoreOS({ read: (rel) => files[rel], storageJson: '{"desk":{"worked":3}}' }).launch();
  await b.frames(3);
  assert.deepEqual(b.errors, []);
  assert.deepEqual(JSON.parse(b.storageJson()).desk, { worked: 3 });
  const junk = await new CoreOS({ read: (rel) => files[rel], storageJson: 'os.exit()' }).launch();
  assert.deepEqual(junk.errors, [], 'damaged storage is an empty record');
  b.close(); junk.close();
});
