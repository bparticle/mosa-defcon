-- M.O.S.A. Night Shift: walk the museum after hours, find the bottles, scan into the HD museum.
--
-- Entry point. Scenes are small tables (enter / update / draw / button) on a
-- stack; overlays draw the scene beneath them first. All museum content comes
-- from data/mosa_data.lua, generated from MOSA by `pnpm sync`.
local g = badge.gfx
local input = badge.input
local led = badge.led

local util = require("util")
local qr = require("qr")
local ui = require("ui")
local world = require("world")
local record = require("record")
local net = require("net")
local DATA = require("data.mosa_data")
local ok_build, BUILD = pcall(require, "build_info")
if not ok_build then BUILD = { version = "dev", built = "", repo = "" } end
-- In the bundled script every module sits in package.preload; once required,
-- drop the loader so its (large, for the data) function can be collected.
for name in pairs(package.preload) do package.preload[name] = nil end

local DATA_SCHEMA = 1

-- ── shared state ─────────────────────────────────────────────────────────────

local t = 0
local idle = 0
local stack = {}
local toast = nil
local rng
local rooms_by_id, piece_count = {}, 0
local pulse = nil -- { r, g, b, until }

for _, r in ipairs(DATA.rooms) do rooms_by_id[r.id] = r end
for _, p in ipairs(DATA.pieces) do piece_count = math.max(piece_count, p.idx + 1) end
local collections = {}
for _, c in ipairs(DATA.collections) do collections[c.slug] = c end

-- The framebuffer persists between frames, so a `static` scene (a card, a
-- list, a QR code) is painted once and then left alone until something
-- changes: no CPU spent, and the badge lasts longer on a lanyard.
local dirty = true
local function invalidate() dirty = true end

local function top() return stack[#stack] end
local function push(s) stack[#stack + 1] = s; dirty = true; if s.enter then s:enter() end end
local function pop()
  local s = table.remove(stack)
  dirty = true
  if s and s.leave then s:leave() end
  if top() and top().resume then top():resume() end
end

local function say(text, sub, seconds)
  toast = { text = text, sub = sub, til = t + (seconds or 2.6) }
  dirty = true
end

local function rgb(c)
  local r, gg, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
  return (r << 3) | (r >> 2), (gg << 2) | (gg >> 4), (b << 3) | (b >> 2)
end

local function flash(c, seconds)
  local r, gg, b = rgb(c)
  pulse = { r, gg, b, t + (seconds or 0.5) }
end

-- QR codes are developed a mask at a time across frames, then kept.
local codes, developing = {}, {}
local function code_for(url)
  -- A handful of codes is plenty; each is a few KB of heap.
  local n = 0
  for _ in pairs(codes) do n = n + 1 end
  if n > 6 and not codes[url] then codes = {} end
  if codes[url] then return codes[url] end
  developing[url] = developing[url] or qr.encoder(url)
  local done = developing[url]()
  if done then codes[url] = done; developing[url] = nil end
  return done
end

local function report_url()
  return DATA.home .. "?shift=" .. record.report_code(piece_count)
end

local function short_url(url)
  return (url:gsub("^https?://", ""))
end

-- ── what litters a room ──────────────────────────────────────────────────────

-- Weighted by MOSA's own rarity weights, nudged toward what this badge has
-- not found yet. A mythical never shows up for a janitor working alone: it can
-- only surface when another badge running Night Shift is in radio range.
local function stocker(mythical_ok)
  local used = {}
  local mythical_placed = false
  return function()
    if mythical_ok and not mythical_placed and rng:float() < 0.3 then
      for _, p in ipairs(DATA.pieces) do
        if p.tier == "mythical" and not used[p.idx] then
          mythical_placed = true
          used[p.idx] = true
          return p
        end
      end
    end
    local options = {}
    for _, p in ipairs(DATA.pieces) do
      local c = collections[p.c]
      local w = (c and c.weights[p.tier]) or 0
      if p.tier == "mythical" then w = 0 end
      if not used[p.idx] and w > 0 then
        if not record.state.found[p.idx] then w = w * 3 end
        options[#options + 1] = { weight = w, piece = p }
      end
    end
    local pick = rng:weighted(options)
    if pick then used[pick.piece.idx] = true; return pick.piece end
    return nil
  end
end

-- ── scenes ───────────────────────────────────────────────────────────────────

local Splash, Title, Lanyard, Game, Pause, Card, Plaque, Code, Record, Map, About

-- A menu helper: items = { { label, fn }, ... }. Numbered like a catalogue;
-- the selected line is an inverted block of paper.
local function menu(items, x, y, sel, step, w)
  step, w = step or 18, w or 180
  for i, item in ipairs(items) do
    local label = type(item[1]) == "function" and item[1]() or item[1]
    local yy = y + (i - 1) * step
    local on = i == sel
    if on then g.fill_rect(x, yy - 3, w, 14, ui.PAPER) end
    g.text(string.format("%02d", i), x + 4, yy, on and ui.MUTED or ui.DIM)
    ui.tracked(label, x + 24, yy, on and ui.PAPER_INK or ui.MUTED, 1, 2)
  end
end

local function menu_button(self, key)
  if key == "up" then self.sel = (self.sel - 2) % #self.items + 1
  elseif key == "down" then self.sel = self.sel % #self.items + 1
  elseif key == "a" then self.items[self.sel][2]() end
end

-- Splash: the museum is poured, then cast in block letters. Any button skips.
Splash = { name = "splash", t = 0 }
local LOGO = "M.O.S.A."
function Splash:update(dt)
  local before = self.t
  self.t = self.t + dt
  -- Each letter lands with a thud of light.
  local n0, n1 = math.floor((before - 0.55) / 0.11), math.floor((self.t - 0.55) / 0.11)
  if n1 > n0 and n1 >= 0 and n1 < #LOGO and LOGO:sub(n1 + 1, n1 + 1) ~= "." then flash(ui.INK, 0.12) end
  if self.t > 3.6 then self:button() end
end
function Splash:draw()
  local T = self.t
  g.clear(ui.BG)
  local pour = math.min(1, T / 0.5)
  ui.concrete(0, 0, ui.W, math.floor(ui.H * (1 - (1 - pour) ^ 3)))
  local k = 7
  local w = ui.block_width(LOGO, k)
  local x = (ui.W - w) // 2
  local n = math.max(0, math.min(#LOGO, math.floor((T - 0.55) / 0.11) + 1))
  if n > 0 then ui.block(LOGO:sub(1, n), x, 70, k, ui.INK, ui.SHADOW) end
  if T > 1.45 then
    g.fill_rect(x, 134, math.floor(w * math.min(1, (T - 1.45) / 0.3)), 3, ui.INK)
  end
  if T > 1.8 then
    ui.tracked(("MUSEUM OF SIRIUS ART"):sub(1, math.floor((T - 1.8) * 40)), x, 50, ui.MUTED, 1, 4)
  end
  if T > 2.3 then
    local lw = ui.tracked_width("NIGHT SHIFT", 2, 4)
    g.fill_rect(x, 146, lw + 16, 24, ui.PAPER)
    ui.tracked("NIGHT SHIFT", x + 8, 150, ui.PAPER_INK, 2, 4)
    -- The museum's crosshair, the one thing on screen in colour.
    local cx, cy = x + w - 9, 158
    g.fill_rect(cx - 8, cy, 6, 1, ui.ACCENT); g.fill_rect(cx + 3, cy, 6, 1, ui.ACCENT)
    g.fill_rect(cx, cy - 8, 1, 6, ui.ACCENT); g.fill_rect(cx, cy + 3, 1, 6, ui.ACCENT)
  end
  if T > 2.7 then
    g.text(ui.no(1), x, 214, ui.MUTED)
    g.text_right("v" .. BUILD.version, x + w, 214, ui.DIM)
  end
end
function Splash:button()
  if top() == self then pop(); push(Title) end
end

-- Title: the museum's front door, and an advert when nobody is touching it.
Title = { sel = 1, art = 1, art_t = 0, name = "title" }
function Title:enter()
  self.items = {
    { "CLOCK IN", function() push(Game.new()) end },
    { "LANYARD", function() push(Lanyard) end },
    { "SHIFT RECORD", function() push(Record.new()) end },
    { "ABOUT", function() push(About) end },
  }
  pcall(badge.mic.enable, false)
end
function Title:resume() self:enter() end
function Title:update(dt)
  self.art_t = self.art_t + dt
  if self.art_t > 3 then self.art_t = 0; self.art = self.art % #DATA.pieces + 1 end
  if idle > 30 then push(Lanyard) end
end
function Title:draw()
  g.clear(ui.BG)
  ui.concrete(0, 0, ui.W, 92)
  g.fill_rect(0, 92, ui.W, 2, ui.INK)
  ui.tracked("MUSEUM OF SIRIUS ART", 16, 10, ui.MUTED, 1, 2)
  ui.block(LOGO, 16, 26, 4, ui.INK, ui.SHADOW)
  local lw = ui.tracked_width("NIGHT SHIFT", 1, 3)
  g.fill_rect(16, 64, lw + 12, 14, ui.PAPER)
  ui.tracked("NIGHT SHIFT", 22, 67, ui.PAPER_INK, 1, 3)
  menu(self.items, 16, 112, self.sel, 20, 184)
  -- The art panel, cantilevered over the band: a different bottle every few seconds.
  local p = DATA.pieces[self.art]
  ui.slab(212, 14, 94, 174)
  g.fill_rect(218, 20, 82, 108, g.color(24, 24, 24))
  ui.thumb(p, 227, 26, 4)
  g.text(ui.no(p.idx + 1), 218, 134, ui.PAPER_INK)
  g.fill_rect(218, 144, 82, 1, ui.PAPER_INK)
  g.text(ui.fit(p.title, 84), 218, 150, ui.PAPER_INK)
  g.text(ui.fit(p.artist, 84), 218, 162, ui.MUTED)
  ui.tracked(ui.TIER[p.tier] or "", 218, 175, ui.MUTED, 1, 1)
  g.fill_rect(0, 208, ui.W, 1, ui.DIM)
  g.text("v" .. BUILD.version, 16, 220, ui.DIM)
  local near = net.nearby()
  local found = record.found_count()
  if near > 0 then g.text_right(near .. " JANITOR" .. (near > 1 and "S" or "") .. " NEARBY", 306, 220, ui.ACCENT)
  elseif found > 0 then g.text_right(found .. " / " .. #DATA.pieces .. " IN YOUR RECORD", 306, 220, ui.MUTED) end
end
Title.button = menu_button

-- Lanyard: wear the badge and it hands the museum to whoever reads it.
Lanyard = { art = 1, art_t = 0, name = "lanyard", static = true }
function Lanyard:update(dt)
  self.art_t = self.art_t + dt
  if self.art_t > 4 then self.art_t = 0; self.art = self.art % #DATA.pieces + 1; invalidate() end
end
function Lanyard:draw()
  g.clear(ui.PAPER)
  local code = code_for(DATA.home)
  if code then
    ui.qr(code, 14, 28, ui.qr_scale(code, 186))
  else
    ui.tracked("DEVELOPING", 40, 110, ui.MUTED, 1, 2)
    invalidate()
  end
  local x = 206
  ui.block("MOSA", x, 26, 3, ui.PAPER_INK)
  g.fill_rect(x, 54, 100, 13, ui.PAPER_INK)
  ui.tracked("SCAN TO ENTER", x + 3, 57, ui.PAPER, 1, 1)
  g.text("The Museum of", x, 74, ui.MUTED)
  g.text("Sirius Art", x, 84, ui.MUTED)
  local p = DATA.pieces[self.art]
  g.fill_rect(x, 98, 100, 92, g.color(24, 24, 24))
  ui.thumb(p, x + 26, 104, 3)
  g.text(ui.fit(p.title, 100), x, 196, ui.PAPER_INK)
  g.text(ui.fit(p.artist, 100), x, 206, ui.MUTED)
  ui.tracked(short_url(DATA.site):upper(), 14, 222, ui.PAPER_INK, 1, 2)
end
function Lanyard:button() pop() end

-- The QR view: a link into the museum, full screen, dark on light.
Code = { name = "code", static = true }
Code.__index = Code
function Code.new(url, heading, title, body)
  return setmetatable({ url = url, heading = heading, title = title, body = body }, Code)
end
function Code:draw()
  g.clear(ui.PAPER)
  local code = code_for(self.url)
  if code then
    ui.qr(code, 8, 8, ui.qr_scale(code, 200))
  else
    ui.tracked("DEVELOPING", 46, 104, ui.MUTED, 1, 2)
    invalidate()
  end
  local x, w = 216, 98
  local y = 14
  for _, l in ipairs(ui.wrap(self.heading, w, 1)) do g.text(l, x, y, ui.PAPER_INK); y = y + 10 end
  g.fill_rect(x, y, w, 2, ui.PAPER_INK)
  y = y + 8
  for i, l in ipairs(ui.wrap(self.title or "", w, 1)) do
    if i <= 4 then g.text(l, x, y, ui.PAPER_INK); y = y + 10 end
  end
  y = y + 4
  ui.paragraph(self.body or "", x, y, w, ui.MUTED, 1, 10)
  local spaced = short_url(self.url):gsub("/", "/ "):gsub("%?", " ?")
  local lines = ui.wrap(spaced, w, 1)
  local yy = 214 - #lines * 10
  for _, l in ipairs(lines) do g.text((l:gsub("/ ", "/")), x, yy, ui.PAPER_INK); yy = yy + 10 end
  g.text("BACK", x + ui.key("b", x, 228, true) + 5, 228, ui.MUTED)
end
function Code:button(key) if key == "b" or key == "a" then pop() end end

-- The janitor's walk.
Game = { name = "game" }
Game.__index = Game
function Game.new()
  return setmetatable({ built = {}, fx = 0, fy = -1, armed = false, blow = 0, cool = 0 }, Game)
end

function Game:enter()
  record.clock_in()
  if record.state.mic then pcall(badge.mic.enable, true) end
  self:travel(DATA.start, nil)
end
function Game:resume()
  if record.state.mic then pcall(badge.mic.enable, true) else pcall(badge.mic.enable, false) end
end
function Game:leave()
  pcall(badge.mic.enable, false)
  record.flush()
end

function Game:stamp(room_id, goal)
  if record.stamp(room_id, goal.id) then
    say("STAMPED  " .. goal.name:upper(), goal.text, 3.2)
    flash(ui.ACCENT, 0.8)
  end
end

--- Start walking through a door. The room is laid out over the next few
--- frames (see world.lua); until then the screen holds a threshold.
function Game:travel(to, from)
  local data = rooms_by_id[to]
  if not data then return end
  if self.room then self.room:suspend() end
  self.room = nil
  self.loading = coroutine.create(function()
    local room = self.built[to]
    if not room then
      room = world.build(data, rng, stocker(net.nearby() > 0), coroutine.yield)
      self.built[to] = room
    else
      room:resume(coroutine.yield)
    end
    self.px, self.py = room:arrival(from)
    return room
  end)
  self.arriving = data
  self.armed = false
end

--- Advance a pending room load by one slice; true once the room is ready.
function Game:step_loading()
  if not self.loading then return true end
  local ok, room = coroutine.resume(self.loading)
  if not ok then error(room) end
  if coroutine.status(self.loading) ~= "dead" then return false end
  self.loading = nil
  self.room = room
  self:arrive(self.arriving)
  return true
end

function Game:arrive(data)
  self.banner = t + 2.8
  record.visit(data)
  for _, goal in ipairs(data.goals or {}) do
    if goal.type == "visit" then self:stamp(data.id, goal) end
  end
  -- "Discover" goals belong to the room that hides the other one.
  for _, other in ipairs(DATA.rooms) do
    for _, goal in ipairs(other.goals or {}) do
      if goal.type == "discover-room" and goal.room == data.id then self:stamp(other.id, goal) end
    end
  end
end

function Game:nearest_balloon(radius)
  local best, bd = nil, radius * radius
  for _, b in ipairs(self.room.balloons) do
    if not b.popped then
      local dx, dy = b.x - self.px, b.y - self.py
      local d = dx * dx + dy * dy
      if d < bd then best, bd = b, d end
    end
  end
  return best
end

function Game:popped()
  record.pop()
  flash(g.color(255, 255, 255), 0.15)
  if self.room:balloons_left() == 0 then
    for _, goal in ipairs(self.room.data.goals or {}) do
      if goal.type == "pop-all-balloons" then self:stamp(self.room.data.id, goal) end
    end
  end
end

function Game:update(dt)
  if not self:step_loading() then return end
  local room = self.room
  room:update(dt)
  local mx, my = 0, 0
  if input.down("left") then mx = mx - 1 end
  if input.down("right") then mx = mx + 1 end
  if input.down("up") then my = my - 1 end
  if input.down("down") then my = my + 1 end
  if mx ~= 0 or my ~= 0 then
    local len = math.sqrt(mx * mx + my * my)
    self.fx, self.fy = mx / len, my / len
    local step = 4.5 * dt
    local r = 0.3
    local nx = self.px + self.fx * step
    if room:walkable(nx - r, self.py - r) and room:walkable(nx + r, self.py - r)
      and room:walkable(nx - r, self.py + r) and room:walkable(nx + r, self.py + r) then self.px = nx end
    local ny = self.py + self.fy * step
    if room:walkable(self.px - r, ny - r) and room:walkable(self.px + r, ny - r)
      and room:walkable(self.px - r, ny + r) and room:walkable(self.px + r, ny + r) then self.py = ny end
  end

  -- Doors: step on one to go through; you must step off before it works again.
  local door = room:door_under(self.px, self.py)
  if not door then self.armed = true
  elseif self.armed then
    self:travel(door.to, room.data.id)
    return
  end

  -- Bottles are picked up by walking into them.
  for _, b in ipairs(room.bottles) do
    if not b.taken and not b.dropped then
      local dx, dy = b.x - self.px, b.y - self.py
      if dx * dx + dy * dy < 0.36 then
        b.taken = true
        local new = record.find(b.piece)
        flash(b.piece.tint, (b.piece.tier == "legendary" or b.piece.tier == "mythical") and 1.4 or 0.6)
        push(Card.new(b.piece, new))
        return
      end
    end
  end

  -- Blow into the badge's microphones to pop the balloons in front of you.
  self.cool = math.max(0, self.cool - dt)
  if record.state.mic then
    local ok, l, r = pcall(badge.mic.level)
    local level = ok and math.max(l or 0, r or 0) or 0
    if level > 70 then self.blow = self.blow + dt else self.blow = 0 end
    if self.blow > 0.2 and self.cool == 0 then
      self.cool = 1
      local any = false
      for _, b in ipairs(room.balloons) do
        if not b.popped then
          local dx, dy = b.x - self.px, b.y - self.py
          if dx * dx + dy * dy < 12 then room:pop(b, rng, stocker(false)); any = true end
        end
      end
      if any then say("WHOOSH", nil, 1.2); self:popped() end
    end
  end

  net.update(room.data.id, record.found_count())
end

function Game:draw()
  local room = self.room
  g.clear(ui.BG)
  if not room then
    -- The threshold: a doorway of light while the next room is laid out.
    g.fill_rect(150, 90, 20, 54, ui.CONC)
    g.fill_rect(156, 96, 8, 48, ui.DIM)
    if self.arriving then ui.tracked_center(self.arriving.name:upper(), 160, 156, ui.MUTED, 1, 3) end
    return
  end
  room:draw(self.px, self.py, self.fx, self.fy, t)
  if self.banner and t < self.banner then
    ui.tracked(room.data.name:upper(), 10, 10, ui.INK, 1, 3)
  end
  if top() ~= self then return end
  local hint
  if self:nearest_balloon(1.5) then hint = { "a", "pop" }
  elseif room:mark_near(self.px, self.py) then hint = { "a", "read" } end
  if hint then ui.hints(hint, 226)
  else
    local d = room:nearest_door(self.px, self.py, 2.6)
    if d and rooms_by_id[d.to] then
      g.text_center("> " .. rooms_by_id[d.to].name:upper(), 160, 226, ui.MUTED)
    end
  end
end

function Game:button(key)
  if not self.room then return end
  if key == "b" then push(Pause.new(self))
  elseif key == "a" then
    local b = self:nearest_balloon(1.5)
    if b then
      self.room:pop(b, rng, stocker(false))
      self:popped()
      return
    end
    local m = self.room:mark_near(self.px, self.py)
    if m then push(Plaque.new(m, self.room.data)) end
  end
end

-- A find: the label card, paper and ink with square corners.
Card = { name = "card" }
Card.__index = Card
Card.under = true
Card.static = true
function Card.new(piece, new) return setmetatable({ piece = piece, new = new }, Card) end
function Card:draw()
  local p = self.piece
  ui.slab(18, 18, 284, 198)
  g.fill_rect(18, 18, 284, 14, ui.PAPER_INK)
  ui.tracked(ui.TIER[p.tier] or "", 26, 21, ui.PAPER, 1, 2)
  g.text_right(ui.no(p.idx + 1), 294, 21, ui.PAPER)
  g.fill_rect(30, 42, 66, 96, g.color(24, 24, 24))
  ui.thumb(p, 39, 54, 3)
  local x, w = 108, 184
  local y = 44
  local size = (#p.title * 12 <= w) and 2 or 1
  for i, l in ipairs(ui.wrap(p.title, w, size)) do
    if i <= 3 then g.text(l, x, y, ui.PAPER_INK, size); y = y + 9 * size + 2 end
  end
  y = y + 4
  g.text(ui.fit("by " .. p.artist, w), x, y, ui.PAPER_INK)
  local c = collections[p.c]
  if c then g.text(ui.fit(c.name, w), x, y + 12, ui.MUTED) end
  -- A new find gets a stamp; the rest a plain line.
  local label = self.new and "NEW TO YOUR RECORD" or "ALREADY IN YOUR RECORD"
  if self.new then
    local lw = ui.tracked_width(label, 1, 1)
    g.rect(x, 116, lw + 10, 16, ui.PAPER_INK); g.rect(x + 1, 117, lw + 8, 14, ui.PAPER_INK)
    ui.tracked(label, x + 5, 120, ui.PAPER_INK, 1, 1)
  else
    ui.tracked(label, x, 120, ui.MUTED, 1, 1)
  end
  ui.paragraph("It stands somewhere in the museum, in full resolution. Find it there to collect it on Solana.", 30, 148, 260, ui.MUTED, 1, 11)
  ui.hints({ "a", "museum link", "b", "back to work" }, 198, ui.MUTED, true)
end
function Card:button(key)
  if key == "a" then
    pop()
    push(Code.new(self.piece.url, "FIND IT IN THE MUSEUM", self.piece.title, "by " .. self.piece.artist))
  elseif key == "b" then pop() end
end

-- A plaque for the museum's furniture.
local PLAQUES = {
  vitrine = { "SPECIMEN CASE", "One of every bottle there is to find, under glass. The rarest stand as plaster casts of their own shape until someone finds one." },
  flapboard = { "DEPARTURES BOARD", "Every collectible is a departure. Editions tick down; the last one reads DEPARTED." },
  postcards = { "POSTCARD WALL", "Every souvenir print made in the museum hangs here, and visitors heart the ones they like." },
  tickets = { "TICKET MACHINE", "Admission is printed here. A ticket opens rooms a walk-in cannot." },
  vending = { "VENDING MACHINE", "Key a lane, pay, pull the flap. It sells the room's fizzy bottle." },
  entrance = { "PARTNER ENTRANCE", "A door into MOSA kept by one of its partners." },
}
Plaque = { name = "plaque" }
Plaque.__index = Plaque
Plaque.under = true
Plaque.static = true
function Plaque.new(mark, room) return setmetatable({ mark = mark, room = room }, Plaque) end
function Plaque:url() return self.mark.url or self.room.link or DATA.home end
function Plaque:draw()
  local info = PLAQUES[self.mark.kind] or { self.mark.kind:upper(), "" }
  ui.slab(40, 50, 240, 138)
  g.fill_rect(40, 50, 240, 14, ui.PAPER_INK)
  ui.tracked(info[1], 48, 53, ui.PAPER, 1, 2)
  g.text(ui.fit(self.mark.label or self.room.name, 212), 54, 74, ui.MUTED)
  ui.paragraph(info[2], 54, 92, 214, ui.PAPER_INK, 1, 11)
  ui.hints({ "a", "museum link", "b", "back" }, 170, ui.MUTED, true)
end
function Plaque:button(key)
  if key == "a" then
    local info = PLAQUES[self.mark.kind] or { self.mark.kind:upper() }
    pop()
    push(Code.new(self:url(), "IN THE MUSEUM", info[1], self.room.name))
  elseif key == "b" then pop() end
end

-- Pause: the janitor's clipboard.
Pause = { name = "pause" }
Pause.__index = Pause
Pause.under = true
Pause.static = true
function Pause.new(game)
  local s = setmetatable({ game = game, sel = 1 }, Pause)
  s.items = {
    { "BACK TO WORK", function() pop() end },
    { "VISITOR MAP", function() push(Map.new()) end },
    { "SHIFT RECORD", function() push(Record.new()) end },
    { function() return "BLOW TO POP: " .. (record.state.mic and "ON" or "OFF") end,
      function() record.set_mic(not record.state.mic) end },
    { "WAVE", function()
        if net.nearby() == 0 then say("NOBODY IN RANGE", "No other janitor is on shift nearby.")
        elseif net.wave(badge.device_name) then say("YOU WAVED", "Every janitor in range saw it.") end
      end },
    { "CLOCK OUT", function() pop(); pop() end },
  }
  return s
end
function Pause:draw()
  g.fill_rect(28, 24, 272, 200, ui.SHADOW)
  ui.concrete(24, 20, 272, 200)
  g.fill_rect(24, 20, 272, 16, ui.PAPER)
  ui.tracked("ON SHIFT", 32, 24, ui.PAPER_INK, 1, 3)
  g.text(ui.fit(self.game.room.data.name, 240, 2), 36, 46, ui.INK, 2)
  local found = record.found_count()
  g.text(found .. " of " .. #DATA.pieces .. " bottles in your record", 36, 70, ui.MUTED)
  local left = self.game.room:balloons_left()
  g.text(left == 0 and "No balloons left in this room" or (left .. " balloon" .. (left > 1 and "s" or "") .. " left in this room"), 36, 82, ui.MUTED)
  local near = net.nearby()
  g.text(near == 0 and "No other janitors in range" or (near .. " other janitor" .. (near > 1 and "s" or "") .. " on shift nearby"),
    36, 94, near > 0 and ui.ACCENT or ui.MUTED)
  menu(self.items, 32, 114, self.sel, 16, 256)
end
function Pause:update(dt)
  -- Janitors come and go; refresh the count once a second.
  self.t = (self.t or 0) + dt
  if self.t > 1 then self.t = 0; invalidate() end
end
function Pause:button(key)
  if key == "b" then pop() else menu_button(self, key) end
end

-- The shift record: every bottle there is, yours in colour, the rest in plaster.
-- Painted progressively (a dozen thumbnails a frame) and, after that, only the
-- cells the cursor leaves and enters are repainted.
Record = { name = "record", static = true }
Record.__index = Record
local COLS, CW, CH, GX, GY, ROWS = 15, 20, 28, 10, 30, 3
function Record.new() return setmetatable({ sel = 1, full = true, painted = 0, repaint = {}, scroll = 0 }, Record) end
function Record:resume() self.full = true end
function Record:cell(i)
  local p = DATA.pieces[i]
  local row, col = (i - 1) // COLS - self.scroll, (i - 1) % COLS
  if row < 0 or row >= ROWS then return end
  local x, y = GX + col * CW, GY + row * CH
  g.fill_rect(x, y, CW, CH, ui.BG)
  if record.state.found[p.idx] then ui.thumb(p, x + 2, y + 2, 1)
  else ui.thumb(p, x + 2, y + 2, 1, (p.tier == "legendary" or p.tier == "mythical") and ui.CAST or ui.DIM) end
  if i == self.sel then g.rect(x, y, CW, CH, ui.ACCENT) end
end
function Record:details()
  local n = #DATA.pieces
  local ry = GY + ROWS * CH - 2
  g.fill_rect(0, ry, 320, 240 - ry, ui.BG)
  if self.sel > n then g.fill_rect(GX - 2, ry, 84, 12, ui.PAPER) end
  g.text("SHIFT REPORT", GX + 4, ry + 2, self.sel > n and ui.PAPER_INK or ui.DIM)
  local y = GY + ROWS * CH + 10
  g.line(10, y, 310, y, ui.DIM)
  y = y + 10
  if self.sel <= n then
    local p = DATA.pieces[self.sel]
    ui.tracked(ui.TIER[p.tier] or "", 10, y, ui.MUTED, 1, 2)
    if record.state.found[p.idx] then
      g.text(ui.fit(p.title, 300, 2), 10, y + 14, ui.INK, 2)
      g.text(ui.fit("by " .. p.artist, 300), 10, y + 34, ui.MUTED)
      ui.hints({ "a", "museum link", "b", "back" }, 226)
    else
      g.text("Not found yet", 10, y + 14, ui.MUTED, 2)
      g.text("Somewhere in the dark. Keep sweeping.", 10, y + 34, ui.DIM)
      ui.hints({ "b", "back" }, 226)
    end
  else
    ui.tracked("SHIFT REPORT", 10, y, ui.INK, 1, 2)
    ui.paragraph("Everything you found tonight, as one code. Scan it into the museum to carry your shift over.", 10, y + 14, 300, ui.MUTED)
    ui.hints({ "a", "show code", "b", "back" }, 226)
  end
end
function Record:draw()
  local n = #DATA.pieces
  if self.full then
    self.full, self.painted, self.repaint = false, self.scroll * COLS, {}
    g.clear(ui.BG)
    ui.header("SHIFT RECORD", record.found_count() .. " / " .. n)
    self:details()
  end
  local last = math.min(n, (self.scroll + ROWS) * COLS)
  local budget = 12
  while self.painted < last and budget > 0 do
    self.painted = self.painted + 1
    self:cell(self.painted)
    budget = budget - 1
  end
  if #self.repaint > 0 then
    for _, i in ipairs(self.repaint) do if i <= n and i <= self.painted then self:cell(i) end end
    self.repaint = {}
    self:details()
  end
  if self.painted < last then invalidate() end
end
function Record:move(to)
  local n = #DATA.pieces
  to = math.max(1, math.min(n + 1, to))
  if to == self.sel then return end
  local old = self.sel
  self.sel = to
  local row = (math.min(to, n) - 1) // COLS
  local scroll = self.scroll
  if row < scroll then scroll = row elseif row >= scroll + ROWS then scroll = row - ROWS + 1 end
  if scroll ~= self.scroll then self.scroll = scroll; self.full = true; return end
  self.repaint = { old, to }
end
function Record:button(key)
  local n = #DATA.pieces
  if key == "b" then pop(); return end
  if self.sel > n then
    if key == "up" or key == "left" then self:move(n)
    elseif key == "a" then
      push(Code.new(report_url(), "SHIFT REPORT", record.found_count() .. " of " .. n .. " bottles",
        "Scan to carry your night shift into M.O.S.A."))
    end
    return
  end
  if key == "left" then self:move(self.sel - 1)
  elseif key == "right" then self:move(self.sel + 1)
  elseif key == "up" then self:move(self.sel - COLS)
  elseif key == "down" then self:move(self.sel + COLS)
  elseif key == "a" then
    local p = DATA.pieces[self.sel]
    if record.state.found[p.idx] then push(Code.new(p.url, "FIND IT IN THE MUSEUM", p.title, "by " .. p.artist)) end
  end
end

-- The visitor map: every room, stamped or not, with its goals.
Map = { name = "map", static = true }
Map.__index = Map
function Map.new() return setmetatable({ sel = 1 }, Map) end
function Map:draw()
  g.clear(ui.BG)
  local visited = util.count(record.state.rooms)
  ui.header("VISITOR MAP", visited .. " / " .. #DATA.rooms .. " ROOMS")
  local first = math.max(1, math.min(self.sel - 4, #DATA.rooms - 9))
  for i = first, math.min(#DATA.rooms, first + 9) do
    local r = DATA.rooms[i]
    local y = 36 + (i - first) * 13
    local seen = record.state.rooms[r.idx]
    if seen then g.fill_rect(12, y, 7, 7, ui.ACCENT) else g.rect(12, y, 7, 7, ui.DIM) end
    if i == self.sel then g.fill_rect(24, y - 3, 288, 13, ui.PAPER) end
    g.text(seen and r.name or "????????", 28, y, i == self.sel and ui.PAPER_INK or (seen and ui.MUTED or ui.DIM))
    local got, total = 0, #(r.goals or {})
    for _, goal in ipairs(r.goals or {}) do if record.state.goals[r.id .. "/" .. goal.id] then got = got + 1 end end
    if total > 0 then g.text_right(got .. "/" .. total, 308, y, i == self.sel and ui.PAPER_INK or (got == total and ui.ACCENT or ui.DIM)) end
  end
  local r = DATA.rooms[self.sel]
  g.fill_rect(0, 170, 320, 2, ui.INK)
  local y = 178
  for _, goal in ipairs(r.goals or {}) do
    local done = record.state.goals[r.id .. "/" .. goal.id]
    g.text((done and "* " or "- ") .. goal.name:upper(), 10, y, done and ui.INK or ui.MUTED)
    if done then g.text(ui.fit(goal.text, 300), 22, y + 10, ui.MUTED) end
    y = y + (done and 22 or 12)
    if y > 214 then break end
  end
  ui.hints({ "b", "back" }, 228)
end
function Map:button(key)
  if key == "b" then pop()
  elseif key == "up" then self.sel = math.max(1, self.sel - 1)
  elseif key == "down" then self.sel = math.min(#DATA.rooms, self.sel + 1) end
end

About = { name = "about", static = true }
function About:draw()
  g.clear(ui.BG)
  ui.header("ABOUT", ui.no(1))
  local y = 38
  y = y + ui.paragraph("M.O.S.A., the Museum of Sirius Art, is a walkable 3D archive: brutalist rooms, huge white walls, balloons that carry the work. This is its night shift.", 10, y, 300, ui.INK, 1, 11) + 8
  y = y + ui.paragraph("Sweep the rooms in the dark. Every bottle you find is a real piece in the museum, made by a real artist; its link takes you to where it stands, in full resolution, to collect it on Solana.", 10, y, 300, ui.MUTED, 1, 11) + 8
  y = y + ui.paragraph("Blow into the badge to pop balloons. Other badges running Night Shift show up when they are near.", 10, y, 300, ui.MUTED, 1, 11)
  g.text("v" .. BUILD.version .. "  MOSA " .. DATA.source.mosa:sub(1, 7) .. "  data schema " .. DATA.schema, 10, 206, ui.DIM)
  ui.hints({ "a", "museum link", "b", "back" }, 226)
end
function About:button(key)
  if key == "a" then push(Code.new(DATA.home, "M.O.S.A.", "The Museum of Sirius Art", "Walk in at full resolution."))
  elseif key == "b" then pop() end
end

-- ── LEDs ─────────────────────────────────────────────────────────────────────

local led_t = 0
local function leds(dt)
  led_t = led_t + dt
  if led_t < 0.05 then return end
  led_t = 0
  if pulse and t < pulse[4] then
    local k = (pulse[4] - t) * 2
    if k > 1 then k = 1 end
    led.all(math.floor(pulse[1] * k), math.floor(pulse[2] * k), math.floor(pulse[3] * k))
    led.show()
    return
  end
  pulse = nil
  local s = top()
  if getmetatable(s) == Game and s.room then
    -- A metal detector: the nearest bottle's colour, blinking faster as you close in.
    local best, bd = nil, 144
    for _, b in ipairs(s.room.bottles) do
      if not b.taken then
        local dx, dy = b.x - s.px, b.y - s.py
        local d = dx * dx + dy * dy
        if d < bd then best, bd = b, d end
      end
    end
    if best then
      local near = 1 - math.sqrt(bd) / 12
      local on = (t * (1 + near * 7)) % 1 < 0.45
      local r, gg, b = rgb(best.piece.tint)
      local k = on and (0.15 + near * 0.85) or 0
      led.all(math.floor(r * k), math.floor(gg * k), math.floor(b * k))
    else
      led.off()
    end
  elseif s == Title or s == Lanyard then
    local p = DATA.pieces[s.art] or DATA.pieces[1]
    local r, gg, b = rgb(p.tint)
    local k = 0.25 + 0.25 * math.sin(t * 1.5)
    led.set(0, math.floor(r * k), math.floor(gg * k), math.floor(b * k))
    k = 0.25 + 0.25 * math.sin(t * 1.5 + 1.6)
    led.set(1, math.floor(r * k), math.floor(gg * k), math.floor(b * k))
  else
    led.off()
  end
  led.show()
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function on_start()
  if DATA.schema ~= DATA_SCHEMA then
    error("data schema " .. tostring(DATA.schema) .. " needs a newer app (expects " .. DATA_SCHEMA .. ")")
  end
  local bytes = badge.system.random_bytes(4)
  local seed = 0
  for i = 1, #bytes do seed = (seed << 8) | bytes:byte(i) end
  rng = util.rng(seed ~ badge.millis())
  record.load()
  pcall(led.take)
  net.start()
  push(Splash)
  badge.log("M.O.S.A. Night Shift " .. BUILD.version .. ", MOSA " .. DATA.source.mosa)
end

function on_update(dt)
  t = t + dt
  idle = idle + dt
  local s = top()
  if s and s.update then s:update(dt) end
  if toast and not (getmetatable(top()) == Game or top() == Title) then
    toast.til = toast.til + dt -- paused while something else is up
  end
  if toast and t > toast.til then toast = nil; dirty = true end
  leds(dt)
end

function on_draw()
  local n = #stack
  if n > 0 and stack[n].static and not dirty then return end
  dirty = false
  local first = n
  while first > 1 and stack[first].under do first = first - 1 end
  for i = first, n do stack[i]:draw() end
  -- A toast never covers a QR code, a card or a list: it waits for the walk.
  local s = top()
  if toast and (getmetatable(s) == Game or s == Title) then
    -- A toast is a rubber stamp: paper, a double rule, a hard shadow.
    local h = toast.sub and 34 or 22
    local sub = toast.sub and ui.fit(toast.sub, 290)
    local w = math.max(ui.tracked_width(toast.text, 1, 2), sub and #sub * 6 or 0) + 24
    local x, y = (ui.W - w) // 2, 190 - h
    ui.slab(x, y, w, h, ui.PAPER, 3)
    g.rect(x + 2, y + 2, w - 4, h - 4, ui.PAPER_INK); g.rect(x + 4, y + 4, w - 8, h - 8, ui.PAPER_INK)
    ui.tracked_center(toast.text, 160, y + 8, ui.PAPER_INK, 1, 2)
    if sub then g.text_center(sub, 160, y + 20, ui.MUTED) end
  end
end

function on_button(key, pressed)
  if not pressed then return end
  idle = 0
  dirty = true
  local s = top()
  if s and s.button then s:button(key) end
end

function on_espnow(mac, data)
  local who = net.receive(mac, data)
  if who then
    say(who:upper() .. " WAVED", "Another janitor is on shift nearby.", 3)
    flash(ui.ACCENT, 1.2)
  end
end

function on_stop()
  record.flush()
  net.stop()
  pcall(led.off)
end

-- Test seam for tools/preview.mjs and test/app.test.mjs. Harmless on a badge.
mosa_debug = {
  state = function()
    local s = top()
    local game
    for i = #stack, 1, -1 do if getmetatable(stack[i]) == Game then game = stack[i]; break end end
    return string.format("scene=%s room=%s found=%d depth=%d", s and s.name or "none",
      game and game.room and game.room.data.id or "-", record.found_count(), #stack)
  end,
  game = function()
    for i = #stack, 1, -1 do
      local gm = stack[i]
      if getmetatable(gm) == Game then
        while not gm:step_loading() do end
        return gm
      end
    end
  end,
  travel = function(id)
    local gm = mosa_debug.game()
    gm:travel(id, nil)
    while not gm:step_loading() do end
  end,
  report = function() return record.report_code(piece_count) end,
  nearby = function() return net.nearby() end,
  tiers = function()
    local gm, out = mosa_debug.game(), {}
    for _, room in pairs(gm.built) do
      for _, b in ipairs(room.bottles) do out[#out + 1] = b.piece.tier end
    end
    return table.concat(out, ",")
  end,
  to_bottle = function()
    local gm = mosa_debug.game()
    for _, b in ipairs(gm.room.bottles) do
      if not b.taken then gm.px, gm.py = b.x, b.y; return b.piece.title end
    end
  end,
  near = function(kind)
    local gm = mosa_debug.game()
    local list = kind == "balloon" and gm.room.balloons or gm.room.data.marks
    for _, b in ipairs(list) do
      if not b.popped then
        local x, y = (b.x or 0) + (kind == "balloon" and 0 or 0.5), (b.y or 0) + (kind == "balloon" and 1 or 1.5)
        if gm.room:walkable(x, y) then gm.px, gm.py = x, y; gm.fx, gm.fy = 0, -1; return true end
      end
    end
    return false
  end,
}
