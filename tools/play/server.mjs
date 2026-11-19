#!/usr/bin/env node
// pnpm play [--port 5317]
//
// Play the built app in a browser, on the real Solana OS emulator: the same
// headless badge the tests use (BadgeCore from vendor/solana-badge), running
// in real time in this Node process. The page shows the framebuffer and LEDs
// and sends buttons back; there is nothing to bundle and no dependency to add.
//
//   arrows        d-pad          Z / Enter   SELECT (a)     X / Esc   CANCEL (b)
//   hold M        blow into the mics (pops balloons, when "blow to pop" is on)
//   page buttons  a janitor nearby (ESP-NOW presence), a wave, relaunch
//
// apps/mosa/ is watched: run `pnpm build` in another terminal and the badge
// relaunches with the new build. The key/value store (your shift record)
// survives relaunches and is kept in .cache/play-kv.json between sessions.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { HeadlessBadge } from '../lib/emulator.mjs';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..', '..');
const APP = path.join(ROOT, 'apps', 'mosa');
const KV_FILE = path.join(ROOT, '.cache', 'play-kv.json');
const args = process.argv.slice(2);
const PORT = Number(args[args.indexOf('--port') + 1] || 0) || 5317;
const FRIEND = 'b2:ad:9e:00:00:01';

const clients = new Set();
const history = []; // recent log lines, replayed to a page that connects later
const send = (event, data) => {
  if (event === 'log') { history.push(data); if (history.length > 100) history.shift(); }
  for (const res of clients) res.write(`event: ${event}\ndata: ${data}\n\n`);
};

let badge, last = null, lastLeds = '', logCount = 0, errCount = 0, friend = false, friendT = 0;

function loadKv() {
  try { return JSON.parse(fs.readFileSync(KV_FILE, 'utf8')); } catch { return []; }
}
function saveKv() {
  if (!badge) return;
  fs.mkdirSync(path.dirname(KV_FILE), { recursive: true });
  fs.writeFileSync(KV_FILE, JSON.stringify([...badge.core.kv.entries]));
}

async function start() {
  const kv = badge ? [...badge.core.kv.entries] : loadKv();
  badge = await new HeadlessBadge({ kv, randomSeed: Date.now() >>> 0 }).boot();
  badge.install('mosa', Object.fromEntries(fs.readdirSync(APP).map((f) => [f, fs.readFileSync(path.join(APP, f))])));
  await badge.launch('mosa');
  // The emulator's mics are silent; let the page blow into them.
  badge.lua('local level = badge.mic.level; play_blow = false; badge.mic.level = function() if play_blow then return 100, 100 end return level() end');
  last = null; lastLeds = ''; logCount = 0; errCount = 0;
  send('log', JSON.stringify(`-- launched ${new Date().toLocaleTimeString()}`));
}

// Real time: each tick advances the badge clock by the wall-clock time elapsed.
let then = performance.now(), busy = false;
setInterval(async () => {
  if (!badge || busy) return;
  busy = true;
  try {
    const now = performance.now();
    await badge.frames(1, Math.min(100, now - then));
    then = now;
    if (friend && now - friendT > 2000) { friendT = now; badge.espnowIn(FRIEND, 'MOSA1 P room0 3'); }
    const fb = Buffer.from(badge.core.fb.buf.buffer, badge.core.fb.buf.byteOffset, badge.core.fb.buf.byteLength);
    if (!last || !fb.equals(last)) { last = Buffer.from(fb); send('frame', fb.toString('base64')); }
    const leds = JSON.stringify(badge.leds?.leds ?? []);
    if (leds !== lastLeds) { lastLeds = leds; send('leds', leds); }
    while (logCount < badge.logs.length) send('log', JSON.stringify(badge.logs[logCount++]));
    while (errCount < badge.errors.length) send('log', JSON.stringify(`ERROR ${JSON.stringify(badge.errors[errCount++])}`));
  } catch (e) {
    send('log', JSON.stringify(`ERROR ${e.message}`));
  } finally { busy = false; }
}, 33);
setInterval(saveKv, 5000);

const KEYS = new Set(['up', 'down', 'left', 'right', 'a', 'b']);
const downAt = {};
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(fs.readFileSync(new URL('index.html', import.meta.url)));
  } else if (url.pathname === '/events') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
    for (const line of history) res.write(`event: log\ndata: ${line}\n\n`);
    clients.add(res);
    last = null; lastLeds = ''; // send the current frame to the newcomer
    req.on('close', () => clients.delete(res));
  } else if (url.pathname === '/key' && req.method === 'POST') {
    const key = url.searchParams.get('k'), down = url.searchParams.get('down') === '1';
    if (KEYS.has(key)) {
      // The badge debounces buttons (25 ms), so a tap shorter than a couple
      // of frames would never register: hold it at least 70 ms.
      const press = () => badge.core.handle({ type: 'button', key, down, atMs: badge.ms });
      if (down) { downAt[key] = performance.now(); press(); }
      else setTimeout(press, Math.max(0, 70 - (performance.now() - (downAt[key] ?? 0))));
    }
    res.end('ok');
  } else if (url.pathname === '/blow' && req.method === 'POST') {
    badge.lua(`play_blow = ${url.searchParams.get('on') === '1'}`);
    res.end('ok');
  } else if (url.pathname === '/friend' && req.method === 'POST') {
    friend = url.searchParams.get('on') === '1'; friendT = 0;
    res.end('ok');
  } else if (url.pathname === '/wave' && req.method === 'POST') {
    badge.espnowIn(FRIEND, 'MOSA1 W Night_Owl');
    res.end('ok');
  } else if (url.pathname === '/relaunch' && req.method === 'POST') {
    saveKv(); await start(); res.end('ok');
  } else if (url.pathname === '/reset' && req.method === 'POST') {
    badge.core.kv.entries.clear(); saveKv(); await start(); res.end('ok');
  } else { res.writeHead(404); res.end(); }
});

// Relaunch on a new build (debounced: bundle.mjs writes several files).
let debounce;
fs.watch(APP, () => {
  clearTimeout(debounce);
  debounce = setTimeout(() => { saveKv(); start().catch((e) => send('log', JSON.stringify(`ERROR ${e.message}`))); }, 300);
});

process.on('SIGINT', () => { saveKv(); process.exit(0); });

await start();
server.listen(PORT, '127.0.0.1', () => {
  console.log(`[play] M.O.S.A. Night Shift on the Solana OS emulator: http://localhost:${PORT}`);
  console.log('[play] arrows move, Z/Enter = SELECT, X/Esc = CANCEL, hold M to blow. pnpm build to reload.');
});
