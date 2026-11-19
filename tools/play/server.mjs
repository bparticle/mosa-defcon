#!/usr/bin/env node
// pnpm play [--port 5317]
//
// Play the built app in a browser on the headless Solana OS (tools/lib/host.mjs),
// in real time in this Node process. The page shows the app area and the eight
// LEDs and sends buttons back.
//
//   arrows        d-pad          Z / Enter   SELECT     X / Esc   CANCEL
//   page buttons  a janitor nearby (mesh presence), a wave, relaunch
//
// apps/mosa/ is watched: run `pnpm build` in another terminal and the app
// relaunches with the new build. Its storage (your shift record) survives
// relaunches and is kept in .cache/play-storage.lua between sessions.
//
// The same server hands the built files to the REAL emulator, the firmware in
// WebAssembly on solana.com: GET /app/files.json lists them and /app/<path>
// serves each, with the CORS headers a page on another origin needs. See
// docs/BADGE.md, "On the real emulator".
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { SolanaOS, WIDTH, HEIGHT } from '../lib/host.mjs';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..', '..');
const APP = path.join(ROOT, 'apps', 'mosa');
const STORE_FILE = path.join(ROOT, '.cache', 'play-storage.lua');
const args = process.argv.slice(2);
const PORT = Number(args[args.indexOf('--port') + 1] || 0) || 5317;
const FRIEND = '7K2Q9M';

const clients = new Set();
const history = []; // recent log lines, replayed to a page that connects later
const send = (event, data) => {
  if (event === 'log') { history.push(data); if (history.length > 100) history.shift(); }
  for (const res of clients) res.write(`event: ${event}\ndata: ${data}\n\n`);
};

let badge, last = null, lastLeds = '', logCount = 0, errCount = 0, friend = false, friendT = 0;
const held = new Set();

function loadStore() {
  try { return fs.readFileSync(STORE_FILE, 'utf8'); } catch { return undefined; }
}
function saveStore() {
  if (!badge?.engine) return;
  fs.mkdirSync(path.dirname(STORE_FILE), { recursive: true });
  fs.writeFileSync(STORE_FILE, badge.storageDump());
}

async function start(storage = badge?.engine ? badge.storageDump() : loadStore()) {
  if (badge?.engine) badge.call('on_exit');
  badge = await new SolanaOS({ dir: APP, storage, seed: Date.now() >>> 0 }).launch();
  last = null; lastLeds = ''; logCount = 0; errCount = 0; held.clear();
  send('log', JSON.stringify(`-- launched ${new Date().toLocaleTimeString()}`));
}

/** The app area as RGB565, little-endian: what the page decodes. */
function frame565() {
  const rgba = badge.rgba();
  const out = Buffer.alloc(WIDTH * HEIGHT * 2);
  for (let i = 0; i < WIDTH * HEIGHT; i++) {
    const c = ((rgba[i * 4] >> 3) << 11) | ((rgba[i * 4 + 1] >> 2) << 5) | (rgba[i * 4 + 2] >> 3);
    out.writeUInt16LE(c, i * 2);
  }
  return out;
}

// Real time: each tick advances the clock by the wall-clock time elapsed (Solana OS ticks every 30 ms).
let then = performance.now(), busy = false;
setInterval(async () => {
  if (!badge || busy) return;
  busy = true;
  try {
    const now = performance.now();
    await badge.frames(1, Math.round(Math.min(100, now - then)));
    then = now;
    if (badge.exited) { send('log', JSON.stringify('-- the app closed (CANCEL on the title); relaunching')); await start(); }
    if (friend && now - friendT > 2000) { friendT = now; badge.meshIn(FRIEND, { p: 'room0', f: 3 }); }
    const fb = frame565();
    if (!last || !fb.equals(last)) { last = fb; send('frame', fb.toString('base64')); }
    const leds = JSON.stringify(badge.leds);
    if (leds !== lastLeds) { lastLeds = leds; send('leds', leds); }
    while (logCount < badge.logs.length) send('log', JSON.stringify(badge.logs[logCount++]));
    while (errCount < badge.errors.length) send('log', JSON.stringify(`ERROR ${badge.errors[errCount++]}`));
  } catch (e) {
    send('log', JSON.stringify(`ERROR ${e.message}`));
  } finally { busy = false; }
}, 30);
setInterval(saveStore, 5000);

const KEYS = { up: 'up', down: 'down', left: 'left', right: 'right', a: 'select', b: 'back' };
const cors = {
  'access-control-allow-origin': '*',
  // Chrome asks before a public page reads from localhost (Private Network Access).
  'access-control-allow-private-network': 'true',
  'access-control-allow-methods': 'GET',
};
function appFiles() {
  return fs.readdirSync(APP, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.relative(APP, path.join(e.parentPath ?? e.path, e.name)).replace(/\\/g, '/'))
    .sort();
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'OPTIONS') { res.writeHead(204, { ...cors, 'access-control-allow-headers': '*' }); res.end(); return; }
  if (url.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(fs.readFileSync(new URL('index.html', import.meta.url)));
  } else if (url.pathname === '/app/files.json') {
    res.writeHead(200, { ...cors, 'content-type': 'application/json', 'cache-control': 'no-store' });
    res.end(JSON.stringify(appFiles()));
  } else if (url.pathname.startsWith('/app/')) {
    const rel = decodeURIComponent(url.pathname.slice(5));
    if (!appFiles().includes(rel)) { res.writeHead(404, cors); res.end(); return; }
    res.writeHead(200, { ...cors, 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
    res.end(fs.readFileSync(path.join(APP, rel)));
  } else if (url.pathname === '/events') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
    for (const line of history) res.write(`event: log\ndata: ${line}\n\n`);
    clients.add(res);
    last = null; lastLeds = ''; // send the current frame to the newcomer
    req.on('close', () => clients.delete(res));
  } else if (url.pathname === '/key' && req.method === 'POST') {
    const key = KEYS[url.searchParams.get('k')], down = url.searchParams.get('down') === '1';
    if (key && badge?.engine) {
      badge.engine.global.get('__keys_set')(key, down);
      if (down && !held.has(key)) {
        held.add(key);
        const handled = badge.call('on_key', key, false);
        if (key === 'back' && handled !== true) badge.exited = true; // Solana OS closes the app
      } else if (!down) held.delete(key);
    }
    res.end('ok');
  } else if (url.pathname === '/friend' && req.method === 'POST') {
    friend = url.searchParams.get('on') === '1'; friendT = 0;
    res.end('ok');
  } else if (url.pathname === '/wave' && req.method === 'POST') {
    badge.meshIn(FRIEND, { w: '@nightowl' });
    res.end('ok');
  } else if (url.pathname === '/relaunch' && req.method === 'POST') {
    saveStore(); await start(); res.end('ok');
  } else if (url.pathname === '/reset' && req.method === 'POST') {
    await start(''); saveStore(); res.end('ok');
  } else { res.writeHead(404); res.end(); }
});

// Relaunch on a new build (debounced: bundle.mjs writes several files).
let debounce;
fs.watch(APP, { recursive: true }, () => {
  clearTimeout(debounce);
  debounce = setTimeout(() => { saveStore(); start().catch((e) => send('log', JSON.stringify(`ERROR ${e.message}`))); }, 300);
});

process.on('SIGINT', () => { saveStore(); process.exit(0); });

await start();
server.listen(PORT, '127.0.0.1', () => {
  console.log(`[play] M.O.S.A. Night Shift on a headless Solana OS: http://localhost:${PORT}`);
  console.log('[play] arrows move, Z/Enter = SELECT, X/Esc = CANCEL. pnpm build to reload.');
  console.log(`[play] the real emulator can load this build from http://localhost:${PORT}/app/ (docs/BADGE.md)`);
});
