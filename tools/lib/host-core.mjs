// A headless Solana OS for tests, screenshots, `pnpm play` and the arcade cabinet.
//
// Night Shift runs on the Solana Breakpoint 2026 badge (ESP32-C5, Solana OS,
// vendor/solana-os). Its real emulator is the firmware compiled to WebAssembly
// and runs only in a browser page (solana.com/breakpoint/badge/emulator), so
// this file plays Solana OS's side of the Lua API (vendor/solana-os/docs/
// LUA_API.md) in Node, with wasmoon: the parts Night Shift uses, held to the
// same rules:
//
//   - the sandbox: no io, os, debug, package, load; collectgarbage("count") only
//   - 200 000 VM instructions per callback, coroutines included ("Script took
//     too long"), and canvas pixels charged at 1 instruction per 16
//   - integer arguments where Solana OS checks for them (a float coordinate is
//     an error there, not a rounding)
//   - 128 UI objects, one QR code, QR text <= 256 bytes and size 25..218
//   - storage values JSON-encodable, 16 KB; mesh messages <= 200 bytes as
//     JSON, 4 a second
//
// What it is not: the badge's Lua is 5.5 with 32-bit integers and floats,
// wasmoon is 5.4 with 64-bit ones (see docs/ARCHITECTURE.md, "32-bit Lua"),
// and the QR code is drawn as a placeholder (the tests read its text). The
// last word is the real emulator: docs/BADGE.md says how to run the build there.
//
// This is the host's core: it needs no Node module (no fs, path or pngjs), so the
// same file runs the app in Node (host.mjs: tests, preview, `pnpm play`) and in a
// browser page (tools/web/host-browser.mjs: the museum's arcade cabinet). The
// caller hands it the app's files as a `read(rel)` function and, in a browser,
// where wasmoon's glue.wasm is served.
import { LuaFactory } from 'wasmoon';

export const WIDTH = 320;
export const HEIGHT = 218;

const factories = new Map();
function factoryFor(wasmUrl) {
  const key = wasmUrl ?? '';
  if (!factories.has(key)) factories.set(key, new LuaFactory(wasmUrl));
  return factories.get(key);
}

// Solana OS's theme colours (dark theme), for the few names the host accepts.
const THEME = { bg: 0x000000, text: 0xffffff, dim: 0x888888, panel: 0x1a1a1a, border: 0x333333, green: 0x14f195, purple: 0x9945ff };

const PRELUDE = `
local host_debug, host_load, host_cg, host_tointeger = debug, load, collectgarbage, math.tointeger
local BUDGET = 200000
local used = 0
-- Every 1000 instructions, like lua_host.c's step_hook; __px() is what the
-- canvas has charged for pixels since the callback began.
local function hook() used = used + 1000; if used + __px() > BUDGET then error("Script took too long", 2) end end
local function charge(n) used = used + n; if used + __px() > BUDGET then error("Script took too long", 3) end end
local function int(v, what)
  local i = host_tointeger(v)
  if i == nil then error((what or "argument") .. ": number has no integer representation", 3) end
  return i
end
local function colour(c)
  if type(c) == "number" then return int(c, "colour") end
  local v = __theme(tostring(c))
  if v < 0 then error("unknown colour " .. tostring(c), 3) end
  return v
end

-- Hooks are per thread in Lua: a coroutine resumed inside a callback gets the
-- same meter, or its work would go uncounted (the badge counts it).
local metering = false
local co_resume = coroutine.resume
coroutine.resume = function(co, ...)
  if metering then host_debug.sethook(co, hook, "", 1000) end
  return co_resume(co, ...)
end

-- Calls into the app, metered like Solana OS meters them.
function __call(fn, ...)
  if type(fn) == "string" then fn = _G[fn] end
  if type(fn) ~= "function" then return nil end
  used = 0
  __px_reset()
  metering = true
  host_debug.sethook(hook, "", 1000)
  local ok, res = pcall(fn, ...)
  host_debug.sethook()
  metering = false
  if not ok then __error(tostring(res)); return nil end
  return res
end
function __used() return used + __px() end
function __heap() return host_cg("count") end
function __gc() host_cg() return host_cg("count") end

-- ui: a canvas, the QR code, and plain rects/labels kept as objects.
ui = { W = ${WIDTH}, H = ${HEIGHT} }
local Obj = {}
Obj.__index = Obj
function Obj:pos(x, y) __obj_pos(self.id, int(x), int(y)) end
function Obj:show(b) __obj_show(self.id, b ~= false) end
function Obj:remove() __obj_remove(self.id) end
-- The drawing methods are host (JS) functions, as they are C functions on the
-- badge, so calling one costs the app the same few instructions.
local Canvas = setmetatable({}, { __index = Obj })
Canvas.__index = Canvas
Canvas.rect = __cv_rect
Canvas.pixel = __cv_pixel
Canvas.line = __cv_line
Canvas.clear = __cv_clear
function Canvas:get(x, y) local v = __cv_get(self.id, int(x), int(y)); if v < 0 then return nil end return v end
function ui.canvas(x, y, w, h, opts)
  opts = opts or {}
  local id = __obj_new("canvas", int(x), int(y), int(w), int(h), int(opts.scale or 1), "")
  local c = setmetatable({ id = id }, Canvas)
  if opts.color then c:clear(opts.color) end
  return c
end
local Qr = setmetatable({}, { __index = Obj })
Qr.__index = Qr
function Qr:text(s) __qr_text(self.id, tostring(s)) end
function ui.qr(x, y, size, text)
  size = int(size, "size")
  if size < 25 or size > 218 then error("ui.qr: size must be 25..218", 2) end
  if #tostring(text) > 256 then error("ui.qr: text over 256 bytes", 2) end
  return setmetatable({ id = __obj_new("qr", int(x), int(y), size, size, 1, tostring(text)) }, Qr)
end
function ui.rect(x, y, w, h, opts)
  return setmetatable({ id = __obj_new("rect", int(x), int(y), int(w), int(h), 1, "") }, Obj)
end
function ui.label(x, y, text, opts)
  return setmetatable({ id = __obj_new("label", int(x), int(y), 0, 0, 1, tostring(text)) }, Obj)
end
function ui.bg(c) end
function ui.clear() __obj_clear() end
function ui.toast(s) __log("toast: " .. tostring(s)) end

led = { count = 8 }
function led.set(i, r, g, b)
  i = int(i, "i")
  if i < 1 or i > 8 then error("led.set: index 1..8", 2) end
  __led(i, int(r) & 255, int(g) & 255, int(b) & 255)
end
function led.hex(i, c) c = int(c); led.set(i, (c >> 16) & 255, (c >> 8) & 255, c & 255) end
function led.fill(r, g, b) for i = 1, 8 do led.set(i, r, g, b) end end
function led.off() for i = 1, 8 do led.set(i, 0, 0, 0) end end

-- json.encode, as storage and the mesh see a value.
local function encode(v, depth)
  depth = depth or 0
  if depth > 16 then error("too deep", 0) end
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("not a JSON number", 0) end
    return math.type(v) == "integer" and string.format("%d", v) or string.format("%.14g", v)
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\\\]', function(ch) return string.format("\\\\u%04x", ch:byte()) end) .. '"'
  elseif t == "table" then
    if next(v) == nil then return "[]" end
    if #v > 0 then
      local out = {}
      for i = 1, #v do out[i] = encode(v[i], depth + 1) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
      if type(k) ~= "string" then error("table keys must be strings", 0) end
      keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = {}
    for i, k in ipairs(keys) do out[i] = encode(k) .. ":" .. encode(v[k], depth + 1) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  error("can't encode a " .. t, 0)
end
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
json = { encode = function(v) local ok, s = pcall(encode, v) if ok then return s end return nil, s end }

storage = {}
local store, store_bytes = {}, {}
function storage.get(k) return copy(store[tostring(k)]) end
function storage.set(k, v)
  k = tostring(k)
  local s = encode(v)
  local total = #s
  for key, n in pairs(store_bytes) do if key ~= k then total = total + n end end
  if total > 16 * 1024 then error("storage: over 16 KB", 2) end
  store[k], store_bytes[k] = copy(v), #s
end
function storage.remove(k) store[tostring(k)], store_bytes[tostring(k)] = nil, nil end
-- Kept between launches as a Lua constructor (what storage holds is plain data).
local function literal(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for i, k in ipairs(keys) do out[i] = "[" .. literal(k) .. "]=" .. literal(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
function __storage_dump() return literal(store) end
function __storage_json() return encode(store) end
function __storage_load(src) store = host_load("return " .. src)() or {}; for k, v in pairs(store) do store_bytes[k] = #encode(v) end end

local held = {}
function __keys_set(k, down) held[k] = down or nil end
sys = {}
function sys.millis() return __millis() end
-- The server clock; tests move it a day at a time with __time_shift.
local time_offset = 0
function __time_shift(s) time_offset = time_offset + s end
function sys.time() return 1790000000 + time_offset + __millis() // 1000 end
function sys.battery() return nil end
function sys.keys() local out = {} for k in pairs(held) do out[k] = true end return out end
function sys.memory() return { used = math.floor(host_cg("count") * 1024), max = 6 * 1024 * 1024 } end
function sys.exit() __exit() end

badge = {}
function badge.id() return "MOSA01" end
function badge.owner() return nil end
function badge.online() return false end

local timers, next_timer = {}, 0
timer = {}
local function add_timer(ms, fn, every)
  ms = int(ms)
  if ms < 20 then ms = 20 end
  local n = 0 for _ in pairs(timers) do n = n + 1 end
  if n >= 8 then error("timer: 8 at a time", 3) end
  next_timer = next_timer + 1
  timers[next_timer] = { at = __millis() + ms, every = every and ms or nil, fn = fn }
  return next_timer
end
function timer.after(ms, fn) return add_timer(ms, fn, false) end
function timer.every(ms, fn) return add_timer(ms, fn, true) end
function timer.cancel(id) timers[id] = nil end
function __timers()
  local now = __millis()
  for id, t in pairs(timers) do
    if now >= t.at then
      if t.every then t.at = now + t.every else timers[id] = nil end
      __call(t.fn)
    end
  end
end

-- !LAMPs (permission lamps): awards answer on the next timer pass, as the
-- server's do. __lamps_mode "needsX" plays an owner who hasn't linked X.
lamps = {}
local lamp_log = {}
__lamps_mode = "earn"
function lamps.award(amount, reason, cb)
  if type(amount) ~= "number" or type(reason) ~= "string" then error("lamps.award(amount, reason, cb)", 2) end
  lamp_log[#lamp_log + 1] = amount .. " " .. reason
  timer.after(20, function()
    if __lamps_mode == "needsX" then cb(true, { awarded = 0, balance = 0, needsX = true })
    else cb(true, { awarded = amount, balance = 100 + amount }) end
  end)
end
function __lamps_log() return table.concat(lamp_log, string.char(10)) end

-- The app's side of a background service (permission background).
service = {}
local svc_on = false
function service.start(cb) svc_on = true; if cb then cb(true) end end
function service.stop() svc_on = false end
function service.running() return svc_on end

local sent = {}
mesh = {}
function mesh.nearby() return {} end
function mesh.send(to, msg)
  if type(to) ~= "string" or (to ~= "*" and #to ~= 6) then error('bad argument #1 to send (a badge id or "*")', 2) end
  if type(msg) ~= "table" then error("bad argument #2 to send (table expected)", 2) end
  local now = __millis()
  local recent = 0
  for i = #sent, 1, -1 do if now - sent[i] < 1000 then recent = recent + 1 else table.remove(sent, i) end end
  if recent >= 4 then return nil, "too fast: 4 messages per second" end
  local ok, s = pcall(encode, msg)
  if not ok then return nil, s end
  if #s > 200 then return nil, "message over 200 bytes" end
  sent[#sent + 1] = now
  __mesh_out(to, s)
  return true
end

-- require: the app's own modules, loaded once.
local loaded = {}
function require(name)
  if loaded[name] ~= nil then return loaded[name] end
  local file = name:gsub("%.", "/") .. ".lua"
  local src = __read(file)
  if src == nil then error("module '" .. name .. "' not found", 2) end
  local chunk, err = host_load(src, "@" .. file, "t")
  if not chunk then error(err, 2) end
  local v = chunk(name)
  if v == nil then v = true end
  loaded[name] = v
  return v
end
function __run_main(src)
  local chunk, err = host_load(src, "@main.lua", "t")
  if not chunk then __error(err) return end
  __call(chunk)
end

-- The sandbox Solana OS gives an app.
io, os, debug, package, load, loadfile, dofile, warn = nil, nil, nil, nil, nil, nil, nil, nil
string.dump = nil
collectgarbage = function(what)
  if what ~= "count" then error("collectgarbage: only \\"count\\" is available", 2) end
  return host_cg("count")
end
`;

// The arcade cabinet's one capability (not Solana OS): a host that can take the
// visitor to a link instead of showing its QR code defines `cabinet.open(url)`.
// The app checks for it (main.lua, the Code scene): on a badge it is nil.
const CABINET = `
cabinet = {}
function cabinet.open(url)
  if type(url) ~= "string" or #url > 256 then error("cabinet.open(url)", 2) end
  __cabinet_open(url)
end
`;

export class SolanaOS {
  /**
   * @param {{ read: (rel: string) => string | undefined, storage?: string, storageJson?: string, seed?: number,
   *   wasmUrl?: string, cabinet?: { open: (url: string) => void } }} options
   *   read: the app's files by relative path (main.lua, world.lua, data/mosa_data.lua…);
   *   storage: a previous run's storageDump(), or storageJson: its storageJson(); wasmUrl: where glue.wasm is served (a browser);
   *   cabinet: the arcade cabinet's capability, `cabinet.open(url)` in the app.
   */
  constructor(options = {}) {
    this.options = options;
    this.ms = 0;
    this.logs = [];
    this.errors = [];
    this.leds = Array.from({ length: 8 }, () => [0, 0, 0]);
    this.meshOut = [];
    this.objects = new Map();
    this.order = [];
    this.nextId = 1;
    this.exited = false;
    /** Grows whenever what is on screen may have changed (a browser host repaints only then). */
    this.revision = 0;
  }

  /** Load the app and run main.lua's top level, as Solana OS does at launch. */
  async launch() {
    const read = this.options.read;
    if (typeof read !== 'function') throw new Error('SolanaOS: options.read(rel) is required');
    this.engine = await factoryFor(this.options.wasmUrl).createEngine({ injectObjects: false, enableProxy: false });
    const g = this.engine.global;
    const self = this;
    let seed = this.options.seed ?? 1;
    g.set('__theme', (name) => (name in THEME ? THEME[name] : -1));
    g.set('__error', (e) => { self.errors.push(e); });
    g.set('__log', (s) => { self.logs.push(s); });
    g.set('__millis', () => self.ms);
    g.set('__exit', () => { self.exited = true; });
    g.set('__read', (rel) => read(rel) ?? null);
    g.set('__led', (i, r, gg, b) => { self.leds[i - 1] = [r, gg, b]; });
    g.set('__mesh_out', (to, s) => { self.meshOut.push({ to, msg: JSON.parse(s) }); });
    g.set('__obj_new', (kind, x, y, w, h, scale, text) => self.newObject(kind, x, y, w, h, scale, text));
    g.set('__obj_pos', (id, x, y) => { const o = self.objects.get(id); if (o) { o.x = x; o.y = y; self.revision++; } });
    g.set('__obj_show', (id, b) => { const o = self.objects.get(id); if (o) { o.visible = b; self.revision++; } });
    g.set('__obj_remove', (id) => { self.objects.delete(id); self.order = self.order.filter((i) => i !== id); self.revision++; });
    g.set('__obj_clear', () => { self.objects.clear(); self.order = []; self.revision++; });
    g.set('__qr_text', (id, s) => { const o = self.objects.get(id); if (o) o.text = s; });
    // canvas methods, called as c:rect(...): `cv` is the canvas table. Arguments
    // are checked like lua_img.c checks them (luaL_checkinteger, a colour).
    this.px = 0;
    const int = (v, what) => {
      if (typeof v !== 'number' || !Number.isInteger(v)) throw new Error(`bad argument (${what}): number has no integer representation`);
      return v;
    };
    const colour = (c) => {
      if (c === null || c === undefined || c === false) return -1;
      if (typeof c === 'number') return to565(int(c, 'colour'));
      if (c in THEME) return to565(THEME[c]);
      throw new Error(`unknown colour ${c}`);
    };
    g.set('__px', () => Math.floor(self.px));
    g.set('__px_reset', () => { self.px = 0; });
    g.set('__cv_rect', (cv, x, y, w, h, c) => self.canvasRect(cv.id, int(x, 'x'), int(y, 'y'), int(w, 'w'), int(h, 'h'), colour(c)));
    g.set('__cv_pixel', (cv, x, y, c) => self.canvasRect(cv.id, int(x, 'x'), int(y, 'y'), 1, 1, colour(c)));
    g.set('__cv_line', (cv, x1, y1, x2, y2, c) => self.canvasLine(cv.id, int(x1, 'x1'), int(y1, 'y1'), int(x2, 'x2'), int(y2, 'y2'), colour(c)));
    g.set('__cv_clear', (cv, c) => { const o = self.objects.get(cv.id); if (o) { self.revision++; self.px += o.w * o.h / 16; o.px.fill(colour(c)); } });
    g.set('__cv_get', (id, x, y) => { const o = self.objects.get(id); return o && x >= 0 && y >= 0 && x < o.w && y < o.h ? o.px[y * o.w + x] : -1; });
    this.engine.doStringSync(PRELUDE);
    if (this.options.cabinet) {
      const open = this.options.cabinet.open;
      // Never re-enter the page from inside a Lua callback: the visit begins after it returns.
      g.set('__cabinet_open', (url) => { queueMicrotask(() => open(String(url))); });
      this.engine.doStringSync(CABINET);
    }
    // print goes to the serial console, tagged with the app id.
    g.set('print', (...a) => { self.logs.push(a.map(String).join('\t')); });
    // math.random is seeded per launch on the badge; here per seed, for reproducible runs.
    this.engine.doStringSync(`math.randomseed(${seed})`);
    if (this.options.storage) this.engine.global.get('__storage_load')(this.options.storage);
    else if (this.options.storageJson) this.engine.global.get('__storage_load')(storageFromJson(this.options.storageJson));
    const main = read('main.lua');
    if (main === undefined) throw new Error('no main.lua');
    this.engine.global.get('__run_main')(main);
    return this;
  }

  newObject(kind, x, y, w, h, scale, text) {
    if (this.objects.size >= 128) throw new Error(`ui.${kind}: 128 objects at a time`);
    if (kind === 'qr' && [...this.objects.values()].some((o) => o.kind === 'qr')) throw new Error('ui.qr: one QR code at a time');
    const id = this.nextId++;
    const o = { id, kind, x, y, w, h, scale, text, visible: true };
    if (kind === 'canvas') o.px = new Int32Array(w * h).fill(-1);
    this.objects.set(id, o);
    this.order.push(id);
    this.revision++;
    return id;
  }

  canvasRect(id, x, y, w, h, c) {
    const o = this.objects.get(id);
    if (!o || w <= 0 || h <= 0) return;
    this.revision++;
    const x0 = Math.max(0, x), x1 = Math.min(o.w, x + w), y0 = Math.max(0, y), y1 = Math.min(o.h, y + h);
    if (x0 >= x1 || y0 >= y1) return;
    this.px += (x1 - x0) * (y1 - y0) / 16; // 1 instruction per 16 pixels, as on the badge
    for (let yy = y0; yy < y1; yy++) o.px.fill(c, yy * o.w + x0, yy * o.w + x1);
  }

  canvasLine(id, x1, y1, x2, y2, c) {
    const dx = Math.abs(x2 - x1), dy = -Math.abs(y2 - y1);
    const sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.canvasRect(id, x1, y1, 1, 1, c);
      if (x1 === x2 && y1 === y2) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x1 += sx; }
      if (e2 <= dx) { err += dx; y1 += sy; }
    }
  }

  call(name, ...args) { return this.engine.global.get('__call')(name, ...args); }

  /** Advance `count` ticks of `ms` each (Solana OS ticks every 30 ms). */
  async frames(count, ms = 30) {
    for (let i = 0; i < count && !this.exited; i++) {
      this.ms += ms;
      this.engine.global.get('__timers')();
      this.call('on_tick', ms);
    }
    return this;
  }

  /** Press and release a button: "up".."right", "select"/"a", "back"/"b". Returns on_key's answer. */
  async press(key, { after = 3 } = {}) {
    const k = KEYS[key] ?? key;
    this.engine.global.get('__keys_set')(k, true);
    const handled = this.call('on_key', k, 0); // the firmware passes repeat as an int: 0 is a fresh press
    await this.frames(1);
    this.engine.global.get('__keys_set')(k, false);
    await this.frames(after);
    return handled;
  }

  /** Hold a button for `count` ticks (sys.keys sees it; on_key gets the press). */
  async hold(key, count) {
    const k = KEYS[key] ?? key;
    this.engine.global.get('__keys_set')(k, true);
    this.call('on_key', k, 0); // the firmware passes repeat as an int: 0 is a fresh press
    await this.frames(count);
    this.engine.global.get('__keys_set')(k, false);
    await this.frames(1);
    return this;
  }

  /** A message from the same app on another badge: on_mesh(from, msg). */
  meshIn(from, msg) {
    this.engine.doStringSync(`__call("on_mesh", ${JSON.stringify(from)}, ${luaLiteral(msg)})`);
  }

  /** Run Lua in the app's state (tests only). Returns the result. */
  lua(code) { return this.engine.doStringSync(code); }

  /** Instructions the last callback used. */
  lastInstructions() { return this.engine.global.get('__used')(); }

  storageDump() { return this.engine.global.get('__storage_dump')(); }

  /** The app's storage as JSON (what a browser keeps in localStorage). */
  storageJson() { return this.engine.global.get('__storage_json')(); }

  /** Shut the Lua state down (a page leaving the cabinet). */
  close() {
    if (!this.engine) return;
    this.engine.global.close();
    this.engine = null;
    this.exited = true;
  }

  /** The QR code on screen now, if any: { text, x, y, size }. */
  qr() {
    const o = [...this.objects.values()].find((v) => v.kind === 'qr' && v.visible);
    return o ? { text: o.text, x: o.x, y: o.y, size: o.w } : null;
  }

  /** RGBA of the app area: the canvases and the QR placeholder, in the order made. */
  rgba() {
    const out = new Uint8Array(WIDTH * HEIGHT * 4);
    for (let i = 0; i < WIDTH * HEIGHT; i++) out[i * 4 + 3] = 255;
    const put = (x, y, rgb) => {
      if (x < 0 || y < 0 || x >= WIDTH || y >= HEIGHT) return;
      const d = (y * WIDTH + x) * 4;
      out[d] = rgb >> 16 & 255; out[d + 1] = rgb >> 8 & 255; out[d + 2] = rgb & 255;
    };
    for (const id of this.order) {
      const o = this.objects.get(id);
      if (!o || !o.visible) continue;
      if (o.kind === 'canvas') {
        for (let y = 0; y < o.h * o.scale; y++) {
          for (let x = 0; x < o.w * o.scale; x++) {
            const c = o.px[((y / o.scale) | 0) * o.w + ((x / o.scale) | 0)];
            if (c >= 0) put(o.x + x, o.y + y, from565(c));
          }
        }
      } else if (o.kind === 'qr') {
        // Not a real code: a white square, a dark frame and a hash of the text.
        let h = 2166136261;
        for (const ch of o.text) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
        const m = Math.max(2, Math.floor(o.w / 33));
        for (let y = 0; y < o.w; y++) {
          for (let x = 0; x < o.w; x++) {
            const cx = Math.floor((x - m * 2) / m), cy = Math.floor((y - m * 2) / m);
            const inside = cx >= 0 && cy >= 0 && cx < 29 && cy < 29;
            const finder = inside && ((cx < 7 && cy < 7) || (cx > 21 && cy < 7) || (cx < 7 && cy > 21));
            let dark = false;
            if (finder) { const fx = cx > 21 ? cx - 22 : cx, fy = cy > 21 ? cy - 22 : cy; dark = fx === 0 || fy === 0 || fx === 6 || fy === 6 || (fx > 1 && fx < 5 && fy > 1 && fy < 5); }
            else if (inside) { h = Math.imul(h ^ (cx * 31 + cy), 2654435761) >>> 0; dark = (h & 1) === 1; }
            put(o.x + x, o.y + y, dark ? 0 : 0xffffff);
          }
        }
      }
    }
    return out;
  }

}

export const KEYS = { a: 'select', b: 'back' };

export function to565(c) { return ((c >> 19 & 31) << 11) | ((c >> 10 & 63) << 5) | (c >> 3 & 31); }
export function from565(c) {
  const r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31;
  return (((r << 3) | (r >> 2)) << 16) | (((g << 2) | (g >> 4)) << 8) | ((b << 3) | (b >> 2));
}

/** Storage kept as JSON → the Lua constructor __storage_load reads. Anything that is not a
 *  JSON object (a damaged or foreign value) is an empty record, never code. */
export function storageFromJson(text) {
  try {
    const v = JSON.parse(text);
    return v && typeof v === 'object' && !Array.isArray(v) ? luaLiteral(v) : '{}';
  } catch { return '{}'; }
}

/** A JS value as a Lua table constructor (plain data only). */
export function luaLiteral(v) {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) return `{${v.map(luaLiteral).join(',')}}`;
  return `{${Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}]=${luaLiteral(x)}`).join(',')}}`;
}
