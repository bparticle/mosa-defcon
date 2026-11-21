// Night Shift in a browser page: the headless Solana OS (tools/lib/host-core.mjs)
// drawing to a canvas, in real time. This is what M.O.S.A.'s arcade cabinet runs
// (the museum's Janitor Room): `pnpm build:web` bundles this file with wasmoon and
// the built app into dist/web/night-shift-<version>/, and the museum pins a copy.
//
// What it plays of Solana OS is what the tests play (host-core.mjs), plus:
//
//   - a 320x240 screen, as the badge's: a 22 px status strip over the app's 320x218
//   - real time: one tick every 30 ms while running, by the wall clock, never faster
//     than the page can keep up (a stalled page is not a fast-forward)
//   - storage in localStorage, as JSON (the badge's 16 KB, the same limit)
//   - `cabinet.open(url)`: the app's QR codes become a way there (main.lua, Code)
//   - CANCEL on the title, which leaves the app on a badge, starts it again: the
//     cabinet is never switched off by the game
//
// What it does not: no mesh (no janitors nearby), no !LAMPs, no background service.
// Night Shift runs without them, as it does on a badge whose owner has none.
import { SolanaOS, WIDTH as APP_W, HEIGHT as APP_H } from '../lib/host-core.mjs';

export const SCREEN_W = 320;
export const SCREEN_H = 240;
export const STATUS_H = SCREEN_H - APP_H;
export const KEYS = ['up', 'down', 'left', 'right', 'select', 'back'];

const TICK_MS = 30;
const SAVE_EVERY_MS = 5000;

function readStore(key) {
  try { return globalThis.localStorage?.getItem(key) ?? undefined; } catch { return undefined; }
}
function writeStore(key, value) {
  try { globalThis.localStorage?.setItem(key, value); } catch { /* the night still plays without storage */ }
}

/**
 * Start Night Shift on `canvas` (320x240; its 2D context is used).
 *
 * @param {{ canvas: HTMLCanvasElement | OffscreenCanvas, base?: string, app?: { version: string, files: Record<string,string> },
 *   storageKey?: string, onOpen?: (url: string) => void, onFrame?: () => void, onLeds?: (leds: number[][]) => void,
 *   onError?: (message: string) => void, seed?: number }} options
 *   base: where host.js, glue.wasm and app.json are served (default: next to this module).
 */
export async function createCabinet(options) {
  const base = options.base ?? new URL('./', import.meta.url).href;
  const app = options.app ?? await (await fetch(new URL('app.json', base))).json();
  const storageKey = options.storageKey ?? 'mosa-night-shift';
  const ctx = options.canvas.getContext('2d', { alpha: false });
  const image = ctx.createImageData(APP_W, APP_H);
  const files = app.files;

  let badge = null;
  let timer = null;
  let then = 0;
  let painted = -1;
  let savedJson = null;
  let lastSave = 0;
  let ledsKey = '';
  let errorsSeen = 0;
  let disposed = false;
  const held = new Set();

  async function launch() {
    badge = await new SolanaOS({
      read: (rel) => files[rel],
      storageJson: readStore(storageKey),
      seed: options.seed ?? (Date.now() >>> 0),
      wasmUrl: new URL('glue.wasm', base).href,
      cabinet: { open: (url) => options.onOpen?.(url) },
    }).launch();
    painted = -1; errorsSeen = 0; held.clear();
  }

  function save() {
    if (!badge?.engine) return;
    const json = badge.storageJson();
    if (json !== savedJson) { savedJson = json; writeStore(storageKey, json); }
  }

  function statusStrip() {
    // The badge's own strip: the app on the left, the time on the right. No colour.
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, SCREEN_W, STATUS_H);
    ctx.fillStyle = '#888';
    ctx.fillRect(0, STATUS_H - 1, SCREEN_W, 1);
    ctx.fillStyle = '#fff';
    ctx.font = '10px ui-monospace, Menlo, Consolas, monospace';
    // The canvas is the page's: whatever it last drew with, the strip sets its own alignment.
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText('NIGHT SHIFT', 6, STATUS_H / 2);
    const d = new Date();
    const clock = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    ctx.fillText(clock, SCREEN_W - 6 - ctx.measureText(clock).width, STATUS_H / 2);
  }
  let clockShown = '';

  function paint() {
    const minute = new Date().getMinutes();
    if (String(minute) !== clockShown) { clockShown = String(minute); statusStrip(); options.onFrame?.(); }
    if (badge.revision === painted) return;
    painted = badge.revision;
    image.data.set(badge.rgba());
    ctx.putImageData(image, 0, STATUS_H);
    options.onFrame?.();
  }

  let busy = false;
  async function tick() {
    if (!badge?.engine || disposed || busy) return;
    busy = true;
    try { await step(); } finally { busy = false; }
  }
  async function step() {
    const now = performance.now();
    await badge.frames(1, Math.max(1, Math.round(Math.min(100, now - then))));
    then = now;
    if (badge.exited) { save(); badge.close(); await launch(); }
    paint();
    const leds = JSON.stringify(badge.leds);
    if (leds !== ledsKey) { ledsKey = leds; options.onLeds?.(badge.leds); }
    while (errorsSeen < badge.errors.length) options.onError?.(badge.errors[errorsSeen++]);
    if (now - lastSave > SAVE_EVERY_MS) { lastSave = now; save(); }
  }

  await launch();
  statusStrip();
  paint();

  return {
    version: app.version,
    get running() { return timer !== null; },
    get leds() { return badge?.leds ?? []; },
    /** Ticks begin (the visitor is at the cabinet). */
    start() {
      if (timer !== null || disposed) return;
      then = performance.now();
      timer = setInterval(() => { tick().catch((e) => options.onError?.(String(e?.message ?? e))); }, TICK_MS);
    },
    /** Ticks stop; the night holds where it is. Storage is written. */
    stop() {
      if (timer !== null) { clearInterval(timer); timer = null; }
      for (const k of held) badge?.engine?.global.get('__keys_set')(k, false);
      held.clear();
      save();
    },
    /** A button: one of KEYS, down or up. A fresh press calls on_key, as Solana OS does. */
    press(key, down) {
      if (!badge?.engine || !KEYS.includes(key)) return;
      badge.engine.global.get('__keys_set')(key, down);
      if (down && !held.has(key)) {
        held.add(key);
        const handled = badge.call('on_key', key, 0);
        // CANCEL that the app leaves unhandled would close it on a badge: here it starts again.
        if (key === 'back' && handled !== true) badge.exited = true;
      } else if (!down) held.delete(key);
    },
    /** Let go of every button (the page lost focus, the visitor stepped away). */
    releaseAll() {
      for (const k of [...held]) this.press(k, false);
    },
    /** Storage, now (a page about to unload). */
    save,
    dispose() {
      this.stop();
      disposed = true;
      badge?.close();
      badge = null;
    },
  };
}
