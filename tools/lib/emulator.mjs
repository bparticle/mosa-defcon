// A headless Solana badge for tests and screenshots.
//
// This is NOT a mock. It drives `BadgeCore` from the vendored Solana OS repo
// (vendor/solana-badge, a git submodule pinned to one commit): the same Lua
// 5.4 runtime (wasmoon), the same badge.* SDK shim and the same sandbox limits
// the official virtual badge at solanadefcon.com/badge runs. When the badge
// team changes the SDK, bump the submodule and the tests tell us what broke.
//
// Caveat carried over from upstream: wasmoon is a 64-bit Lua, while the real
// badge is built with LUA_32BITS (int32 integers, single-precision floats).
// The Lua sources avoid anything that would behave differently (see
// docs/ARCHITECTURE.md, "32-bit Lua").
//
// Run with `node --import ./tools/lib/register.mjs` so the vendored TypeScript
// can resolve its npm dependencies from this repo.
import fs from 'node:fs';
import { PNG } from 'pngjs';

const WORKER = new URL('../../vendor/solana-badge/app/src/lib/emulator/worker/', import.meta.url);
const { BadgeCore } = await import(new URL('worker.ts', WORKER).href);
const { installApp } = await import(new URL('appstore.ts', WORKER).href);

export const WIDTH = 320;
export const HEIGHT = 240;

export class HeadlessBadge {
  /** @param {{ kv?: [string,string][], http?: Function, randomSeed?: number }} [options] */
  constructor(options = {}) {
    this.ms = 0;
    this.logs = [];
    this.errors = [];
    this.leds = null;
    this.espnowOut = [];
    let seed = options.randomSeed ?? 1;
    const clock = {
      now: () => this.ms,
      epochSeconds: () => 1_790_000_000 + Math.floor(this.ms / 1000),
      sleep: (d) => { this.ms += d; },
    };
    this.core = new BadgeCore({
      clock,
      kv: options.kv,
      http: options.http,
      // Deterministic "TRNG" so screenshots are reproducible.
      randomBytes: (n) => {
        const out = new Uint8Array(n);
        for (let i = 0; i < n; i++) { seed = (seed * 1103515245 + 12345) >>> 0; out[i] = seed >>> 24; }
        return out;
      },
      emit: (m) => {
        if (m.type === 'log') this.logs.push(`[${m.tag}] ${m.text}`);
        else if (m.type === 'app-error') this.errors.push(m.error);
        else if (m.type === 'led-state') this.leds = m.state;
        else if (m.type === 'espnow-out') this.espnowOut.push({ mac: m.mac, data: Buffer.from(m.data).toString('latin1') });
      },
    });
  }

  async boot() { await this.core.boot(); return this; }

  /** Install an app directory: `{ 'main.lua': '...', 'app.ini': '...' }`. */
  install(id, files) {
    const list = Object.entries(files).map(([path, body]) => ({
      path, bytes: typeof body === 'string' ? new TextEncoder().encode(body) : body,
    }));
    const result = installApp(this.core.vfs, id, list);
    if (!result.ok) throw new Error(result.error);
  }

  async launch(id) {
    const ok = await this.core.runtime.launch(id);
    if (!ok) throw new Error(`launch failed: ${JSON.stringify(this.core.runtime.lastError())}`);
    return this;
  }

  running() { return this.core.runtime.running(); }
  lastError() { return this.core.runtime.lastError(); }

  /** Advance `count` frames of `stepMs` each. */
  async frames(count, stepMs = 33) {
    for (let i = 0; i < count; i++) {
      this.ms += stepMs;
      await this.core.tick();
    }
    return this;
  }

  /** Press and release a button ("up".."b"), letting frames run in between. */
  async press(key, { holdFrames = 2, after = 4 } = {}) {
    this.core.handle({ type: 'button', key, down: true, atMs: this.ms });
    await this.frames(holdFrames);
    this.core.handle({ type: 'button', key, down: false, atMs: this.ms });
    await this.frames(after);
    return this;
  }

  async hold(key, frames) {
    this.core.handle({ type: 'button', key, down: true, atMs: this.ms });
    await this.frames(frames);
    this.core.handle({ type: 'button', key, down: false, atMs: this.ms });
    await this.frames(1);
    return this;
  }

  espnowIn(mac, text, rssi = -50) {
    this.core.handle({ type: 'espnow-in', mac, data: new TextEncoder().encode(text), rssi });
  }

  /** Run Lua in the app's state (tests only). Returns the stringified result. */
  lua(code) {
    return this.core.runtime.engine.doStringSync(code);
  }

  pixel(x, y) { return this.core.fb.buf[y * WIDTH + x]; }

  /** RGBA bytes of the framebuffer (RGB565 expanded). */
  rgba() {
    const out = new Uint8Array(WIDTH * HEIGHT * 4);
    const buf = this.core.fb.buf;
    for (let i = 0; i < buf.length; i++) {
      const c = buf[i];
      const r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31;
      out[i * 4] = (r << 3) | (r >> 2);
      out[i * 4 + 1] = (g << 2) | (g >> 4);
      out[i * 4 + 2] = (b << 3) | (b >> 2);
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  /** Write the screen as a PNG, scaled up by an integer factor. */
  screenshot(path, scale = 2) {
    const src = this.rgba();
    const png = new PNG({ width: WIDTH * scale, height: HEIGHT * scale });
    for (let y = 0; y < HEIGHT * scale; y++) {
      for (let x = 0; x < WIDTH * scale; x++) {
        const s = ((y / scale | 0) * WIDTH + (x / scale | 0)) * 4;
        const d = (y * WIDTH * scale + x) * 4;
        png.data[d] = src[s]; png.data[d + 1] = src[s + 1]; png.data[d + 2] = src[s + 2]; png.data[d + 3] = 255;
      }
    }
    fs.writeFileSync(path, PNG.sync.write(png));
  }

  kvDump() { return Object.fromEntries(this.core.kv.entries?.() ?? []); }
}
