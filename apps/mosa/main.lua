-- M.O.S.A. Night Shift: walk the museum after hours, catch the art thieves,
-- look at the real works on their walls, scan into the HD museum.
--
-- A Solana OS app (docs/ARCHITECTURE.md). Solana OS runs this file once, then
-- calls on_tick every 30 ms and on_key on a button. Scenes are small tables
-- (enter / update / draw / button) on a stack; overlays draw the scene beneath
-- them first, onto the one canvas gfx.lua keeps. All museum content comes
-- from data/mosa_data.lua, generated from MOSA by `pnpm sync`.
local g = require("gfx")
local util = require("util")
local ui = require("kit")
local world = require("world")
local sprites = require("sprites")
local light = require("light")
local record = require("record")
local net = require("net")
local DATA = require("data.mosa_data")
local ok_build, BUILD = pcall(require, "build_info")
if not ok_build then BUILD = { version = "dev", built = "", repo = "" } end

local DATA_SCHEMA = 2

-- ── shared state ─────────────────────────────────────────────────────────────

local t = 0
local idle = 0
local stack = {}
local toast = nil
local rng
local rooms_by_id, piece_count = {}, 0
local works_by_idx = {}
local pulse = nil -- { r, g, b, until }
local held = {} -- the buttons down this tick (sys.keys)

for _, r in ipairs(DATA.rooms) do rooms_by_id[r.id] = r end
for _, p in ipairs(DATA.pieces) do
  piece_count = math.max(piece_count, p.idx + 1)
  p.tint = g.from565(p.tint) -- the sync speaks RGB565; the canvas takes 0xRRGGBB
end
for _, w in ipairs(DATA.works) do
  w.tint = g.from565(w.tint)
  works_by_idx[w.idx] = w
end
local collections = {}
for _, c in ipairs(DATA.collections) do collections[c.slug] = c end

-- The canvas keeps its pixels between ticks, so a `static` scene (a card, a
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

local rgb = g.rgb

local function flash(c, seconds)
  local r, gg, b = rgb(c)
  pulse = { r, gg, b, t + (seconds or 0.5) }
end

local function report_url()
  return DATA.home .. "?shift=" .. record.report_code(piece_count)
end

local function short_url(url)
  return (url:gsub("^https?://", ""))
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function room_name(id)
  local r = rooms_by_id[id]
  return r and r.name or "the museum"
end

-- A room nobody has catalogued (another room's goal is to discover it) keeps
-- its name and place to itself until you walk in.
local function known(r) return not r.hidden or record.state.rooms[r.idx] end

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

-- ── tonight's heist ─────────────────────────────────────────────────────────

-- Thieves take one work each from THIEVES different rooms that have art on the
-- walls. The first is always one door from where the shift starts, so a new
-- janitor meets one within a minute; the rest lean toward walls you haven't
-- looked at yet.
local THIEVES = 3
local function plan_heist()
  local start = rooms_by_id[DATA.start]
  local near = {}
  for _, d in ipairs(start and start.doors or {}) do near[d.to] = true end
  local options = {}
  for _, r in ipairs(DATA.rooms) do
    if #(r.art or {}) > 0 and not r.hidden then
      local unseen = 0
      for _, a in ipairs(r.art) do if not record.state.seen[a.w] then unseen = unseen + 1 end end
      options[#options + 1] = { weight = 1 + math.min(6, #r.art) + unseen * 0.5, near = near[r.id], room = r }
    end
  end
  local plan = {}
  local function take(pick)
    for i, o in ipairs(options) do if o == pick then table.remove(options, i); break end end
    local art = pick.room.art
    plan[#plan + 1] = { room = pick.room.id, work = art[rng:int(#art)].w }
  end
  local close = {}
  for _, o in ipairs(options) do if o.near then close[#close + 1] = o end end
  if #close > 0 then take(rng:weighted(close)) end
  while #plan < THIEVES and #options > 0 do take(rng:weighted(options)) end
  return plan
end

-- ── scenes ───────────────────────────────────────────────────────────────────

local Splash, Title, Lanyard, Intro, Briefing, Game, Pause, Card, ArtCard, Plaque, Code, Grid, Map, Finale, About

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

-- What a title panel or a lanyard shows: the works and the bottles, in turn.
local function on_show(i)
  local nw, np = #DATA.works, #DATA.pieces
  if nw > 0 and (i % 2 == 1 or np == 0) then return DATA.works[(i // 2) % nw + 1] end
  return DATA.pieces[(i // 2) % np + 1]
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
  if n > 0 then ui.block(LOGO:sub(1, n), x, 62, k, ui.INK, ui.SHADOW) end
  if T > 1.45 then
    g.fill_rect(x, 126, math.floor(w * math.min(1, (T - 1.45) / 0.3)), 3, ui.INK)
  end
  if T > 1.8 then
    ui.tracked(("MUSEUM OF SIRIUS ART"):sub(1, math.floor((T - 1.8) * 40)), x, 42, ui.MUTED, 1, 4)
  end
  if T > 2.3 then
    local lw = ui.tracked_width("NIGHT SHIFT", 2, 4)
    g.fill_rect(x, 138, lw + 16, 24, ui.PAPER)
    ui.tracked("NIGHT SHIFT", x + 8, 142, ui.PAPER_INK, 2, 4)
    -- The museum's crosshair, the one thing on screen in colour.
    local cx, cy = x + w - 9, 150
    g.fill_rect(cx - 8, cy, 6, 1, ui.ACCENT); g.fill_rect(cx + 3, cy, 6, 1, ui.ACCENT)
    g.fill_rect(cx, cy - 8, 1, 6, ui.ACCENT); g.fill_rect(cx, cy + 3, 1, 6, ui.ACCENT)
  end
  if T > 2.7 then
    g.text(ui.no(1), x, 196, ui.MUTED)
    g.text_right("v" .. BUILD.version, x + w, 196, ui.DIM)
  end
end
function Splash:button()
  if top() == self then pop(); push(Title) end
end

-- Title: the museum's front door, and an advert when nobody is touching it.
Title = { sel = 1, art = 1, art_t = 0, name = "title", static = true }
function Title:enter()
  self.items = {
    { "CLOCK IN", function() push(Intro.new()) end },
    { "THE ART", function() push(Grid.new("art")) end },
    { "BOTTLES", function() push(Grid.new("bottles")) end },
    { "LANYARD", function() push(Lanyard) end },
    { "ABOUT", function() push(About) end },
  }
end
function Title:resume() self:enter() end
function Title:update(dt)
  self.art_t = self.art_t + dt
  if self.art_t > 3 then self.art_t = 0; self.art = self.art + 1; invalidate() end
  -- Janitors come and go: look again once a second.
  local near = net.nearby()
  if near ~= self.near then self.near = near; invalidate() end
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
  menu(self.items, 16, 104, self.sel, 18, 184)
  -- The art panel, cantilevered over the band: a work, then a bottle, every few seconds.
  local p = on_show(self.art)
  ui.slab(212, 14, 94, 174)
  ui.mat(p, 218, 20, 82, 108)
  g.text(p.sw and ui.fit(room_name(p.room), 84) or ui.no(p.idx + 1), 218, 134, ui.PAPER_INK)
  g.fill_rect(218, 144, 82, 1, ui.PAPER_INK)
  g.text(ui.fit(p.title, 84), 218, 150, ui.PAPER_INK)
  g.text(ui.fit(p.artist, 84), 218, 162, ui.MUTED)
  ui.tracked(p.sw and "ON THE WALL" or (ui.TIER[p.tier] or ""), 218, 175, ui.MUTED, 1, 1)
  g.fill_rect(0, 196, ui.W, 1, ui.DIM)
  g.text("v" .. BUILD.version, 16, 204, ui.DIM)
  local near = net.nearby()
  if near > 0 then g.text_right(plural(near, "JANITOR"):upper() .. " NEARBY", 306, 204, ui.ACCENT)
  elseif record.seen_count() + record.found_count() > 0 then
    g.text_right(record.seen_count() .. " WORKS  " .. record.found_count() .. " BOTTLES", 306, 204, ui.MUTED)
  end
end
Title.button = menu_button

-- Lanyard: wear the badge and it hands the museum to whoever reads it.
Lanyard = { art = 1, art_t = 0, name = "lanyard", static = true }
function Lanyard:update(dt)
  self.art_t = self.art_t + dt
  if self.art_t > 4 then self.art_t = 0; self.art = self.art + 1; invalidate() end
end
function Lanyard:qr() return { DATA.home, 12, 14, 186 } end
function Lanyard:draw()
  g.clear(ui.PAPER)
  local x = 206
  ui.block("MOSA", x, 26, 3, ui.PAPER_INK)
  g.fill_rect(x, 54, 100, 13, ui.PAPER_INK)
  ui.tracked("SCAN TO ENTER", x + 3, 57, ui.PAPER, 1, 1)
  g.text("The Museum of", x, 74, ui.MUTED)
  g.text("Sirius Art", x, 84, ui.MUTED)
  local p = on_show(self.art)
  ui.mat(p, x, 94, 100, 84)
  g.text(ui.fit(p.title, 100), x, 184, ui.PAPER_INK)
  g.text(ui.fit(p.artist, 100), x, 194, ui.MUTED)
  ui.tracked(short_url(DATA.site):upper(), 14, 206, ui.PAPER_INK, 1, 2)
end
function Lanyard:button() pop() end

-- The QR view: a link into the museum, full screen, dark on light.
Code = { name = "code", static = true }
Code.__index = Code
function Code.new(url, heading, title, body)
  return setmetatable({ url = url, heading = heading, title = title, body = body }, Code)
end
function Code:qr() return { self.url, 8, 8, 202 } end
function Code:draw()
  g.clear(ui.PAPER)
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
  if #lines > 3 then lines = { ui.fit(short_url(self.url), w) } end
  local yy = 194 - #lines * 10
  for _, l in ipairs(lines) do g.text((l:gsub("/ ", "/")), x, yy, ui.PAPER_INK); yy = yy + 10 end
  g.text("BACK", x + ui.key("b", x, 206, true) + 5, 206, ui.MUTED)
end
function Code:button(key) if key == "b" or key == "a" then pop() end end

local function hd_code(w)
  return Code.new(w.url, "SEE IT IN HD", w.title, "by " .. w.artist .. ". On " .. w.via .. ".")
end

-- ── the intro: the janitor's cupboard ───────────────────────────────────────
-- The janitor walks in, takes the flashlight off its hook, and clicks it on.
-- The bulb goes out and the night begins. Any button skips it.
Intro = { name = "intro" }
Intro.__index = Intro
function Intro.new() return setmetatable({ t = 0 }, Intro) end
local WALK_IN, TURN, TAKE, CLICK, DONE = 1.5, 1.7, 2.3, 2.9, 6.2
local HOOK_X, FLOOR_Y = 190, 178
function Intro:update(dt)
  local before = self.t
  self.t = self.t + dt
  if before < CLICK and self.t >= CLICK then flash(sprites.LENS, 0.25) end
  if self.t >= DONE then self:button() end
end
-- After the click: only what the beam touches, the wall and floor pale in it.
local BEAM_WALL, BEAM_MARK, BEAM_FLOOR = g.color(168, 164, 156), g.color(140, 137, 130), g.color(104, 100, 94)
function Intro:dark(T, jx, lx, ly)
  local a = math.sin((T - CLICK) * 1.3) * 0.2
  local L = light.new(lx + 16, ly + 3, math.cos(a), math.sin(a), 240, 0.3, jx, FLOOR_Y - 22, 36)
  for y = math.max(0, L.top), math.min(ui.H - 1, L.bottom) do
    local a1, b1, a2, b2 = light.row(L, y)
    local col = y < FLOOR_Y - 20 and ((y % 7 == 6) and BEAM_MARK or BEAM_WALL) or BEAM_FLOOR
    if a1 then g.fill_rect(a1, y, b1 - a1 + 1, 1, col) end
    if a2 then g.fill_rect(a2, y, b2 - a2 + 1, 1, col) end
  end
  if light.lit(L, 262, 140) then
    g.line(268, 66, 262, 150, ui.PAPER_INK)
    g.fill_rect(250, 140, 26, 18, g.color(58, 56, 52))
  end
  if light.lit(L, 160, 51) then
    g.fill_rect(118, 44, 84, 14, ui.PAPER)
    ui.tracked("STAFF ONLY", 124, 47, ui.PAPER_INK, 1, 2)
  end
end

function Intro:draw()
  local T = self.t
  g.clear(ui.BG)
  local x = math.min(1, T / WALK_IN)
  local jx = math.floor(-20 + (HOOK_X - 10 + 20) * x)
  local lx, ly = jx + 12, FLOOR_Y - 18
  if T >= CLICK then
    self:dark(T, jx, lx, ly)
    sprites.draw("janitor", "right", 0, jx, FLOOR_Y, 3)
    g.fill_rect(lx, ly, 14, 6, sprites.TORCH)
    g.fill_rect(lx + 14, ly - 1, 3, 8, sprites.LENS)
    if T > CLICK + 0.8 then ui.tracked("23:58. THE MUSEUM IS CLOSED.", 16, 192, ui.MUTED, 1, 1) end
    if T > CLICK + 1.8 then ui.tracked("BUT IT IS NOT EMPTY.", 16, 204, ui.INK, 1, 1) end
    return
  end
  -- The cupboard: a concrete wall, a lino floor, a bulb, a locker, a mop.
  ui.concrete(0, 0, ui.W, FLOOR_Y - 20)
  g.fill_rect(0, FLOOR_Y - 20, ui.W, ui.H - FLOOR_Y + 20, g.color(26, 25, 24))
  for x = 0, ui.W, 24 do g.line(x, FLOOR_Y - 20, x - 30, ui.H, g.color(34, 33, 31)) end
  g.fill_rect(0, FLOOR_Y - 21, ui.W, 2, ui.SHADOW)
  g.line(160, 0, 160, 18, ui.DIM)
  g.fill_circle(160, 23, 5, T < CLICK and g.color(255, 244, 210) or ui.DIM)
  ui.slab(28, 58, 44, 100, ui.DIM, 3)
  for y = 66, 84, 4 do g.line(36, y, 64, y, ui.CONC) end
  g.fill_rect(64, 104, 3, 10, ui.MUTED)
  g.line(268, 66, 262, 150, ui.MUTED)
  g.fill_rect(250, 140, 26, 18, g.color(74, 72, 68))
  g.fill_rect(252, 136, 22, 4, g.color(96, 94, 88))
  -- A plate on the wall, and the hook with the flashlight on it.
  g.fill_rect(118, 44, 84, 14, ui.PAPER)
  ui.tracked("STAFF ONLY", 124, 47, ui.PAPER_INK, 1, 2)
  g.fill_rect(HOOK_X - 2, 92, 5, 3, ui.MUTED)
  if T < TAKE then
    g.fill_rect(HOOK_X - 3, 95, 7, 20, sprites.TORCH)
    g.fill_rect(HOOK_X - 4, 115, 9, 4, sprites.TORCH)
    g.fill_rect(HOOK_X - 3, 119, 7, 2, sprites.LENS)
  end
  -- The janitor: in, up to the hook, and the flashlight comes down.
  local face, step = "right", 0
  if T < WALK_IN then step = (math.floor(T * 6) % 2 == 0) and 1 or 0
  elseif T < TAKE then face = "up" end
  sprites.draw("janitor", face, step, jx, FLOOR_Y, 3)
  if T >= TAKE then
    g.fill_rect(lx, ly, 14, 6, sprites.TORCH)
    g.fill_rect(lx + 14, ly - 1, 3, 8, ui.MUTED)
  elseif T >= TURN then
    -- Reaching up for it.
    g.fill_rect(jx + 6, FLOOR_Y - 66, 6, 22, g.color(216, 212, 202))
    g.fill_rect(jx + 6, FLOOR_Y - 72, 6, 6, g.color(226, 182, 142))
  end
  if T < 0.6 then ui.tracked_center("NIGHT SHIFT", 160, 200, ui.INK, 1, 3) end
end
function Intro:button()
  if top() ~= self then return end
  pop()
  push(Briefing.new(plan_heist()))
end

-- ── the briefing: tonight's assignment, on the curator's notepaper ─────────
Briefing = { name = "briefing", static = true }
Briefing.__index = Briefing
function Briefing.new(plan) return setmetatable({ plan = plan }, Briefing) end
function Briefing:draw()
  g.clear(ui.BG)
  ui.slab(20, 6, 280, 202)
  g.fill_rect(20, 6, 280, 14, ui.PAPER_INK)
  ui.tracked("TONIGHT'S ROUNDS", 28, 9, ui.PAPER, 1, 2)
  g.text_right("FROM THE CURATOR", 292, 9, ui.MUTED)
  local n = #self.plan
  local y = 30
  if n == 0 then
    y = y + ui.paragraph("A quiet night. Walk the rooms, look at the works on their walls, and pick up any bottles left lying about.", 32, y, 256, ui.PAPER_INK, 1, 11)
  else
    y = y + ui.paragraph("Someone got in after closing. " .. (n == 1 and "One work is" or (n == 2 and "Two works are" or plural(n, "work") .. " are")) .. " off the walls.", 32, y, 256, ui.PAPER_INK, 1, 11) + 4
    y = y + ui.paragraph("Find the thieves in the dark and hold your flashlight on them. Dazzled, they drop the art.", 32, y, 256, ui.PAPER_INK, 1, 11) + 6
    ui.tracked("SEEN IN", 32, y, ui.MUTED, 1, 2)
    y = y + 12
    for _, h in ipairs(self.plan) do
      g.fill_rect(34, y + 2, 3, 3, ui.PAPER_INK)
      ui.tracked(room_name(h.room):upper(), 44, y, ui.PAPER_INK, 1, 2)
      y = y + 11
    end
  end
  y = math.max(y + 6, 150)
  g.fill_rect(32, y - 4, 256, 1, ui.MUTED)
  g.text("D-PAD walk   " .. ui.label("a") .. " look   " .. ui.label("b") .. " clipboard", 32, y + 2, ui.MUTED)
  ui.hints({ "a", "start the shift", "b", "not tonight" }, 188, ui.MUTED, true)
end
function Briefing:button(key)
  if key == "a" then local plan = self.plan; pop(); push(Game.new(plan))
  elseif key == "b" then pop() end
end

-- ── the janitor's walk ──────────────────────────────────────────────────────
Game = { name = "game" }
Game.__index = Game
function Game.new(plan)
  local s = setmetatable({ built = {}, fx = 0, fy = -1, armed = false, step = 0, heist = {}, plan = plan or {},
    caught = 0, tonight = { seen = 0, bottles = 0 } }, Game)
  for _, h in ipairs(s.plan) do s.heist[h.room] = h.work end
  return s
end

function Game:enter()
  record.clock_in()
  self:travel(DATA.start, nil)
end
function Game:leave()
  record.flush()
end
function Game:resume()
  if self.all_clear then self.all_clear = false; push(Finale.new(self)) end
end

function Game:thieves_left() return #self.plan - self.caught end

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
  self.room, self.L = nil, nil
  self.loading = coroutine.create(function()
    local room = self.built[to]
    if not room then
      room = world.build(data, { rng = rng, stock = stocker(net.nearby() > 0), pause = coroutine.yield,
        works = works_by_idx, heist = self.heist[to] })
      self.built[to] = room
    else
      room:resume(coroutine.yield)
    end
    self.px, self.py = room:arrival(from, coroutine.yield)
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
  local th = self.room.thief
  if th and not th.gone and not th.caught then
    say("SOMEONE IS IN HERE", "Sweep the dark with your light.", 3.2)
  end
end

--- A thief gave up: the work goes back on its wall.
function Game:recovered(work)
  for _, a in ipairs(self.room.art) do if a.work == work then a.missing = false end end
  self.heist[self.room.data.id] = nil
  self.caught = self.caught + 1
  record.catch()
  if record.see(work) then self.tonight.seen = self.tonight.seen + 1 end
  flash(work.tint, 1.4)
  if self:thieves_left() == 0 then self.all_clear = true end
  push(ArtCard.new(work, "recovered", self.room.data))
end

function Game:update(dt)
  -- A few slices of a room being laid out per tick: each is well under a
  -- tenth of the 200 000-instruction budget (test/app.test.mjs measures it).
  local ready = false
  for _ = 1, 4 do
    ready = self:step_loading()
    if ready then break end
  end
  if not ready then return end
  local room = self.room
  local mx, my = 0, 0
  if held.left then mx = mx - 1 end
  if held.right then mx = mx + 1 end
  if held.up then my = my - 1 end
  if held.down then my = my + 1 end
  if mx ~= 0 or my ~= 0 then
    local len = math.sqrt(mx * mx + my * my)
    self.fx, self.fy = mx / len, my / len
    local ox, oy = self.px, self.py
    self.px, self.py = room:slide(self.px, self.py, self.fx * 4.5 * dt, self.fy * 4.5 * dt, 0.3)
    self.step = self.step + math.abs(self.px - ox) + math.abs(self.py - oy)
    self.walking = true
  else
    self.walking = false
  end

  -- Doors: step on one to go through; you must step off before it works again.
  local door = room:door_under(self.px, self.py)
  if not door then self.armed = true
  elseif self.armed then
    self:travel(door.to, room.data.id)
    return
  end

  -- The thief, caught in last frame's light.
  local lit = room:thief_lit(self.L, self.cx, self.cy)
  if lit and not self.coached then
    self.coached = true
    say("HOLD THE LIGHT ON THEM", "Keep them in the beam.", 2.4)
  end
  if room:update_thief(dt, self.px, self.py, lit, rng) == "caught" then
    self:recovered(room.thief.work)
    return
  end

  -- Bottles are picked up by walking into them.
  for _, b in ipairs(room.bottles) do
    if not b.taken then
      local dx, dy = b.x - self.px, b.y - self.py
      if dx * dx + dy * dy < 0.36 then
        b.taken = true
        local new = record.find(b.piece)
        self.tonight.bottles = self.tonight.bottles + 1
        flash(b.piece.tint, (b.piece.tier == "legendary" or b.piece.tier == "mythical") and 1.4 or 0.6)
        push(Card.new(b.piece, new))
        return
      end
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
  local stride = 0
  if self.walking then
    local k = math.floor(self.step * 2.2) % 4
    stride = k == 1 and 1 or (k == 3 and 2 or 0)
  end
  self.L, self.cx, self.cy = room:draw(self.px, self.py, self.fx, self.fy, t, stride)
  if top() ~= self then return end
  if self.banner and t < self.banner then
    ui.tracked(room.data.name:upper(), 10, 10, ui.INK, 1, 3)
  end
  local hint
  local a = room:art_near(self.px, self.py)
  if a then hint = { "a", a.missing and "empty frame" or "look" }
  elseif room:mark_near(self.px, self.py) then hint = { "a", "read" } end
  if hint then ui.hints(hint)
  else
    local d = room:nearest_door(self.px, self.py, 2.6)
    if d and rooms_by_id[d.to] then
      local to = rooms_by_id[d.to]
      g.text_center("> " .. (known(to) and to.name:upper() or "?"), 160, ui.HINTS_Y, ui.MUTED)
    end
  end
end

function Game:button(key)
  if not self.room then return end
  if key == "b" then push(Pause.new(self))
  elseif key == "a" then
    local a = self.room:art_near(self.px, self.py)
    if a then
      if a.missing then push(Plaque.empty(a.work, self.room.data))
      else
        if record.see(a.work) then self.tonight.seen = self.tonight.seen + 1; a.new = true end
        push(ArtCard.new(a.work, a.new and "new" or "look", self.room.data))
        a.new = nil
      end
      return
    end
    local m = self.room:mark_near(self.px, self.py)
    if m then push(Plaque.new(m, self.room.data)) end
  end
end

-- A stamp in a double rule: NEW TO YOUR RECORD, RECOVERED.
local function stamp(label, x, y)
  local lw = ui.tracked_width(label, 1, 1)
  g.rect(x, y, lw + 10, 16, ui.PAPER_INK); g.rect(x + 1, y + 1, lw + 8, 14, ui.PAPER_INK)
  ui.tracked(label, x + 5, y + 4, ui.PAPER_INK, 1, 1)
end

-- A work, up close: its pixel miniature on a mat, its label, and the way to
-- the real thing.
ArtCard = { name = "artcard" }
ArtCard.__index = ArtCard
ArtCard.under = true
ArtCard.static = true
function ArtCard.new(work, mode, room) return setmetatable({ work = work, mode = mode, room = room }, ArtCard) end
function ArtCard:draw()
  local w = self.work
  ui.slab(14, 6, 292, 202)
  g.fill_rect(14, 6, 292, 14, ui.PAPER_INK)
  ui.tracked(self.mode == "recovered" and "RECOVERED" or "ON THE WALL", 22, 9, ui.PAPER, 1, 2)
  g.text_right(ui.fit(room_name(w.room):upper(), 150), 298, 9, ui.PAPER)
  ui.mat(w, 24, 28, 128, 128)
  local x, cw = 162, 136
  local y = 30
  local size = (#w.title * 12 <= cw) and 2 or 1
  for i, l in ipairs(ui.wrap(w.title, cw, size)) do
    if i <= 4 then g.text(l, x, y, ui.PAPER_INK, size); y = y + 9 * size + 2 end
  end
  y = y + 4
  for i, l in ipairs(ui.wrap("by " .. w.artist, cw, 1)) do
    if i <= 2 then g.text(l, x, y, ui.PAPER_INK); y = y + 10 end
  end
  if w.set then g.text(ui.fit(w.set, cw), x, y + 2, ui.MUTED) end
  if self.mode == "recovered" then stamp("RECOVERED", x, 112)
  elseif self.mode == "new" then stamp("NEW TO YOUR RECORD", x, 112)
  else ui.tracked("IN YOUR RECORD", x, 116, ui.MUTED, 1, 1) end
  ui.paragraph(self.mode == "recovered" and "Back on its wall. The real one hangs in M.O.S.A., in full resolution."
    or "This is a miniature. The real work is on " .. w.via .. ", in full resolution.", x, 136, cw, ui.MUTED, 1, 10)
  ui.hints({ "a", "see it in hd", "b", "back" }, 190, ui.MUTED, true)
end
function ArtCard:button(key)
  if key == "a" then local w = self.work; pop(); push(hd_code(w))
  elseif key == "b" then pop() end
end

-- A bottle picked up: the label card, paper and ink with square corners.
Card = { name = "card" }
Card.__index = Card
Card.under = true
Card.static = true
function Card.new(piece, new) return setmetatable({ piece = piece, new = new }, Card) end
function Card:draw()
  local p = self.piece
  ui.slab(18, 8, 284, 198)
  g.fill_rect(18, 8, 284, 14, ui.PAPER_INK)
  ui.tracked(ui.TIER[p.tier] or "", 26, 11, ui.PAPER, 1, 2)
  g.text_right(ui.no(p.idx + 1), 294, 11, ui.PAPER)
  ui.mat(p, 30, 32, 66, 96)
  local x, w = 108, 184
  local y = 34
  local size = (#p.title * 12 <= w) and 2 or 1
  for i, l in ipairs(ui.wrap(p.title, w, size)) do
    if i <= 3 then g.text(l, x, y, ui.PAPER_INK, size); y = y + 9 * size + 2 end
  end
  y = y + 4
  g.text(ui.fit("by " .. p.artist, w), x, y, ui.PAPER_INK)
  local c = collections[p.c]
  if c then g.text(ui.fit(c.name, w), x, y + 12, ui.MUTED) end
  if self.new then stamp("NEW TO YOUR RECORD", x, 106)
  else ui.tracked("ALREADY IN YOUR RECORD", x, 110, ui.MUTED, 1, 1) end
  ui.paragraph("Someone left it lying about. It stands somewhere in the museum, in full resolution: find it there to collect it on Solana.", 30, 138, 260, ui.MUTED, 1, 11)
  ui.hints({ "a", "museum link", "b", "back to work" }, 188, ui.MUTED, true)
end
function Card:button(key)
  if key == "a" then
    pop()
    push(Code.new(self.piece.url, "FIND IT IN THE MUSEUM", self.piece.title, "by " .. self.piece.artist))
  elseif key == "b" then pop() end
end

-- A plaque for the museum's furniture, and for an empty frame.
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
function Plaque.empty(work, room)
  return setmetatable({ room = room, work = work, info = { "EMPTY FRAME",
    work.title .. " by " .. work.artist .. " hangs here. Tonight there is only a nail. The thief can't be far." } }, Plaque)
end
function Plaque:info_for()
  return self.info or PLAQUES[self.mark.kind] or { self.mark.kind:upper(), "" }
end
function Plaque:url() return self.mark.url or self.room.link or DATA.home end
function Plaque:draw()
  local info = self:info_for()
  ui.slab(40, 36, 240, 138)
  g.fill_rect(40, 36, 240, 14, ui.PAPER_INK)
  ui.tracked(info[1], 48, 39, ui.PAPER, 1, 2)
  g.text(ui.fit(self.mark and (self.mark.label or self.room.name) or self.room.name, 212), 54, 60, ui.MUTED)
  ui.paragraph(info[2], 54, 78, 214, ui.PAPER_INK, 1, 11)
  ui.hints(self.work and { "b", "back" } or { "a", "museum link", "b", "back" }, 156, ui.MUTED, true)
end
function Plaque:button(key)
  if key == "a" and not self.work then
    local info = self:info_for()
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
    { "MUSEUM MAP", function() push(Map.new(game)) end },
    { "THE ART", function() push(Grid.new("art")) end },
    { "BOTTLES", function() push(Grid.new("bottles")) end },
    { "WAVE", function()
        if net.nearby() == 0 then say("NOBODY IN RANGE", "No other janitor is on shift nearby.")
        elseif net.wave() then say("YOU WAVED", "Every janitor in range saw it.")
        else say("NO WAVE", "The radio is busy. Try again in a moment.") end
      end },
    { "CLOCK OUT", function() pop(); pop() end },
  }
  return s
end
function Pause:draw()
  local game = self.game
  g.fill_rect(28, 10, 272, 202, ui.SHADOW)
  ui.concrete(24, 6, 272, 202)
  g.fill_rect(24, 6, 272, 16, ui.PAPER)
  ui.tracked("ON SHIFT", 32, 10, ui.PAPER_INK, 1, 3)
  g.text(ui.fit(game.room.data.name, 240, 2), 36, 30, ui.INK, 2)
  local left, total = game:thieves_left(), #game.plan
  if total == 0 then g.text("A quiet night", 36, 52, ui.MUTED)
  elseif left == 0 then g.text("Every work is back on its wall", 36, 52, ui.ACCENT)
  else g.text(plural(left, "thie" .. (left == 1 and "f" or "ve")) .. " still in the museum", 36, 52, ui.INK) end
  local art = game.room.art
  if #art > 0 then
    local n = 0
    for _, a in ipairs(art) do if record.state.seen[a.work.idx] then n = n + 1 end end
    g.text(n .. " of " .. plural(#art, "work") .. " here looked at", 36, 64, ui.MUTED)
  else
    g.text("No works hang in this room", 36, 64, ui.MUTED)
  end
  local near = net.nearby()
  g.text(near == 0 and "No other janitors in range" or (plural(near, "other janitor") .. " on shift nearby"),
    36, 76, near > 0 and ui.ACCENT or ui.MUTED)
  menu(self.items, 32, 98, self.sel, 17, 256)
end
function Pause:update(dt)
  -- Janitors come and go; refresh the count once a second.
  self.t = (self.t or 0) + dt
  if self.t > 1 then self.t = 0; invalidate() end
end
function Pause:button(key)
  if key == "b" then pop() else menu_button(self, key) end
end

-- ── the collection: the works and the bottles, as grids ─────────────────────
-- Yours in colour; the rest as an empty frame (a work) or plaster (a bottle).
-- Painted progressively (a dozen thumbnails a frame) and, after that, only the
-- cells the cursor leaves and enters are repainted.
Grid = { name = "grid", static = true }
Grid.__index = Grid
local KINDS = {
  art = { title = "THE ART", list = function() return DATA.works end, have = function(p) return record.state.seen[p.idx] end,
    cols = 11, cw = 28, ch = 28, rows = 4, gx = 6, gy = 30 },
  bottles = { title = "BOTTLES", list = function() return DATA.pieces end, have = function(p) return record.state.found[p.idx] end,
    cols = 15, cw = 20, ch = 28, rows = 3, gx = 10, gy = 30, report = true },
}
function Grid.new(kind)
  local k = KINDS[kind]
  return setmetatable({ kind = kind, k = k, list = k.list(), sel = 1, full = true, painted = 0, repaint = {}, scroll = 0, name = kind }, Grid)
end
function Grid:resume() self.full = true end
function Grid:count()
  local n = 0
  for _, p in ipairs(self.list) do if self.k.have(p) then n = n + 1 end end
  return n
end
function Grid:cell(i)
  local k, p = self.k, self.list[i]
  local row, col = (i - 1) // k.cols - self.scroll, (i - 1) % k.cols
  if row < 0 or row >= k.rows then return end
  local x, y = k.gx + col * k.cw, k.gy + row * k.ch
  g.fill_rect(x, y, k.cw, k.ch, ui.BG)
  local pw, ph = ui.size(p)
  local ox, oy = x + (k.cw - pw) // 2, y + (k.ch - ph) // 2
  if k.have(p) then ui.thumb(p, ox, oy, 1)
  elseif p.sw then g.rect(ox, oy, pw, ph, ui.DIM)
  else ui.thumb(p, ox, oy, 1, (p.tier == "legendary" or p.tier == "mythical") and ui.CAST or ui.DIM) end
  if i == self.sel then g.rect(x, y, k.cw, k.ch, ui.ACCENT) end
end
function Grid:details()
  local k, n = self.k, #self.list
  local ry = k.gy + k.rows * k.ch
  g.fill_rect(0, ry, ui.W, ui.H - ry, ui.BG)
  local y = ry + 2
  if k.report then
    if self.sel > n then g.fill_rect(k.gx - 2, ry, 84, 12, ui.PAPER) end
    g.text("SHIFT REPORT", k.gx + 4, ry + 2, self.sel > n and ui.PAPER_INK or ui.DIM)
    y = ry + 12
  end
  g.line(10, y + 2, 310, y + 2, ui.DIM)
  y = y + 8
  if self.sel > n then
    ui.tracked("SHIFT REPORT", 10, y, ui.INK, 1, 2)
    ui.paragraph("Everything you found, as one code. Scan it into the museum to carry your shift over.", 10, y + 14, 300, ui.MUTED)
    ui.hints({ "a", "show code", "b", "back" })
    return
  end
  local p = self.list[self.sel]
  if p.sw then
    local r = rooms_by_id[p.room]
    ui.tracked(ui.fit(((r and known(r)) and r.name or "Uncatalogued"):upper(), 300), 10, y, ui.MUTED, 1, 2)
  else
    ui.tracked(ui.TIER[p.tier] or "", 10, y, ui.MUTED, 1, 2)
  end
  if k.have(p) then
    g.text(ui.fit(p.title, 300, 2), 10, y + 12, ui.INK, 2)
    g.text(ui.fit("by " .. p.artist, 300), 10, y + 31, ui.MUTED)
    ui.hints({ "a", p.sw and "see it in hd" or "museum link", "b", "back" })
  else
    g.text(p.sw and "Not looked at yet" or "Not found yet", 10, y + 12, ui.MUTED, 2)
    g.text(p.sw and "It hangs on a wall in that room. Bring a light." or "Somewhere in the dark. Keep sweeping.", 10, y + 31, ui.DIM)
    ui.hints({ "b", "back" })
  end
end
function Grid:draw()
  local k, n = self.k, #self.list
  if self.full then
    self.full, self.painted, self.repaint = false, self.scroll * k.cols, {}
    g.clear(ui.BG)
    ui.header(k.title, self:count() .. " / " .. n)
    self:details()
  end
  local last = math.min(n, (self.scroll + k.rows) * k.cols)
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
function Grid:move(to)
  local k, n = self.k, #self.list
  to = math.max(1, math.min(n + (k.report and 1 or 0), to))
  if to == self.sel then return end
  local old = self.sel
  self.sel = to
  local row = (math.min(to, n) - 1) // k.cols
  local scroll = self.scroll
  if row < scroll then scroll = row elseif row >= scroll + k.rows then scroll = row - k.rows + 1 end
  if scroll ~= self.scroll then self.scroll = scroll; self.full = true; return end
  self.repaint = { old, to }
end
function Grid:button(key)
  local k, n = self.k, #self.list
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
  elseif key == "up" then self:move(self.sel - k.cols)
  elseif key == "down" then self:move(self.sel + k.cols)
  elseif key == "a" then
    local p = self.list[self.sel]
    if k.have(p) then
      if p.sw then push(hd_code(p))
      else push(Code.new(p.url, "FIND IT IN THE MUSEUM", p.title, "by " .. p.artist)) end
    end
  end
end

-- ── the museum map: MOSA's real floorplan ───────────────────────────────────
-- Every room where it stands in the HD museum (the sync lays them out from
-- MOSA's world). Rooms you've walked are filled in; the one you're in carries
-- the crosshair; a room with a thief in it tonight blinks.
Map = { name = "map", static = true }
Map.__index = Map
local MX, MY = (320 - DATA.map.w) // 2, 30 + (148 - DATA.map.h) // 2
function Map.new(game)
  local s = setmetatable({ game = game, blink = 0, on = true, rooms = {} }, Map)
  for _, r in ipairs(DATA.rooms) do if known(r) then s.rooms[#s.rooms + 1] = r end end
  local function cx(r) local p = r.plan[1]; return p[1] + p[3] / 2 end
  table.sort(s.rooms, function(a, b) return cx(a) < cx(b) end)
  local here = game and game.room and game.room.data.id or DATA.start
  s.sel = 1
  for i, r in ipairs(s.rooms) do if r.id == here then s.sel = i end end
  return s
end
function Map:update(dt)
  self.blink = self.blink + dt
  if self.blink > 0.45 then self.blink = 0; self.on = not self.on; invalidate() end
end
function Map:draw()
  g.clear(ui.BG)
  local visited = util.count(record.state.rooms)
  ui.header("MUSEUM MAP", visited .. " / " .. #DATA.rooms .. " ROOMS WALKED")
  local game = self.game
  local here = game and game.room and game.room.data.id
  local sel = self.rooms[self.sel]
  -- Outlines first, then fills inset by one, so a room's own claims merge.
  for pass = 1, 2 do
    for _, r in ipairs(self.rooms) do
      local walked = record.state.rooms[r.idx]
      local edge = r == sel and ui.INK or (walked and ui.MUTED or ui.DIM)
      local fill = r.id == here and g.color(92, 90, 86) or (walked and g.color(44, 43, 41) or ui.BG)
      for _, p in ipairs(r.plan) do
        if pass == 1 then g.rect(MX + p[1], MY + p[2], p[3], p[4], edge)
        else g.fill_rect(MX + p[1] + 1, MY + p[2] + 1, p[3] - 2, p[4] - 2, fill) end
      end
    end
  end
  -- Thieves reported tonight.
  if game then
    for _, h in ipairs(game.plan) do
      local r = rooms_by_id[h.room]
      if r and game.heist[h.room] and self.on then
        local p = r.plan[1]
        local x, y = MX + p[1] + p[3] // 2, MY + p[2] + p[4] // 2
        g.fill_rect(x - 4, y - 5, 9, 11, ui.INK)
        g.text("!", x - 2, y - 3, ui.BG)
      end
    end
    -- You are here.
    if game.room then
      local at = game.room.data.at
      local x, y = MX + math.floor(at.x + game.px * at.k), MY + math.floor(at.y + game.py * at.k)
      g.fill_rect(x - 4, y, 3, 1, ui.ACCENT); g.fill_rect(x + 2, y, 3, 1, ui.ACCENT)
      g.fill_rect(x, y - 4, 1, 3, ui.ACCENT); g.fill_rect(x, y + 2, 1, 3, ui.ACCENT)
    end
  end
  -- The selected room.
  g.fill_rect(0, 180, ui.W, 1, ui.DIM)
  local y = 185
  ui.tracked(ui.fit(sel.name:upper(), 300), 10, y, ui.INK, 1, 2)
  local line
  if game and game.heist[sel.id] then line = "A thief was seen in here tonight."
  elseif not record.state.rooms[sel.idx] then line = "Not walked yet."
  elseif #(sel.art or {}) > 0 then
    local n = 0
    for _, a in ipairs(sel.art) do if record.state.seen[a.w] then n = n + 1 end end
    line = n .. " of " .. plural(#sel.art, "work") .. " looked at."
  else line = "No works hang here." end
  g.text_right(line, 310, y, ui.MUTED)
  ui.hints({ "b", "back" }, 204)
end
function Map:button(key)
  if key == "b" then pop()
  elseif key == "left" or key == "up" then self.sel = (self.sel - 2) % #self.rooms + 1
  elseif key == "right" or key == "down" then self.sel = self.sel % #self.rooms + 1 end
end

-- ── all clear: every work back on its wall ──────────────────────────────────
-- The lights come up, the night is tallied, and the museum is one scan away.
Finale = { name = "finale" }
Finale.__index = Finale
function Finale.new(game)
  record.clear()
  return setmetatable({ game = game, t = 0 }, Finale)
end
function Finale:update(dt) self.t = self.t + dt end
function Finale:draw()
  local T, game = self.t, self.game
  g.clear(ui.BG)
  local up = math.min(1, T / 0.8)
  ui.concrete(0, 0, ui.W, math.floor(96 * (1 - (1 - up) ^ 3)))
  g.fill_rect(0, 96, ui.W, 2, ui.INK)
  if T > 0.5 then
    ui.tracked("THE LIGHTS COME UP", 16, 14, ui.MUTED, 1, 3)
    ui.block("ALL", 16, 34, 5, ui.INK, ui.SHADOW)
    local lw = ui.tracked_width("CLEAR", 2, 4)
    g.fill_rect(16, 76, lw + 16, 22, ui.PAPER)
    ui.tracked("CLEAR", 24, 80, ui.PAPER_INK, 2, 4)
  end
  if T > 1.1 then
    local rows = {
      { plural(game.caught, "thie" .. (game.caught == 1 and "f" or "ve")) .. " caught", ui.INK },
      { plural(game.tonight.seen, "new work") .. " looked at", ui.MUTED },
      { plural(game.tonight.bottles, "bottle") .. " picked up", ui.MUTED },
    }
    for i, r in ipairs(rows) do
      if T > 1.1 + i * 0.25 then g.text(r[1], 16, 108 + i * 14, r[2]) end
    end
  end
  if T > 2.2 then
    ui.paragraph("Every work is back on its wall. See them in full resolution: your shift comes with you.", 16, 174, 288, ui.MUTED, 1, 10)
  end
  -- The thieves' loot, back where it belongs: one work per thief, side by side.
  local x = 300
  for i = #game.plan, 1, -1 do
    local w = works_by_idx[game.plan[i].work]
    if w and T > 0.7 + i * 0.2 then
      x = x - 40
      ui.mat(w, x, 112, 36, 36)
    end
  end
  if T > 2.6 then ui.hints({ "a", "into mosa", "b", "keep walking" }, ui.HINTS_Y) end
end
function Finale:button(key)
  if self.t < 1 then return end
  if key == "a" then
    pop()
    push(Code.new(report_url(), "ALL CLEAR", "Every work is back on its wall.", "Scan to walk into M.O.S.A. in full resolution."))
  elseif key == "b" then pop() end
end

About = { name = "about", static = true }
function About:draw()
  g.clear(ui.BG)
  ui.header("ABOUT", ui.no(1))
  local y = 36
  y = y + ui.paragraph("M.O.S.A., the Museum of Sirius Art, is a walkable 3D archive: brutalist rooms, huge white walls, real art by real artists. This is its night shift.", 10, y, 300, ui.INK, 1, 11) + 6
  y = y + ui.paragraph("Thieves get in after closing. Find them in the dark and hold your flashlight on them until they drop the art. Every work on these walls hangs in the HD museum; its miniature here links to the real one.", 10, y, 300, ui.MUTED, 1, 11) + 6
  y = y + ui.paragraph("Walk into a bottle to pick it up. Other badges running Night Shift show up when they are near.", 10, y, 300, ui.MUTED, 1, 11)
  g.text("v" .. BUILD.version .. "  MOSA " .. DATA.source.mosa:sub(1, 7) .. "  data schema " .. DATA.schema, 10, 192, ui.DIM)
  ui.hints({ "a", "museum link", "b", "back" })
end
function About:button(key)
  if key == "a" then push(Code.new(DATA.home, "M.O.S.A.", "The Museum of Sirius Art", "Walk in at full resolution."))
  elseif key == "b" then pop() end
end

-- ── LEDs ─────────────────────────────────────────────────────────────────────
-- Eight of them: six across the top, two on the right edge. Solana OS shows a
-- change at the end of the callback and turns them off when the app closes.

local led_t = 0
local function leds(dt)
  if not led then return end
  led_t = led_t + dt
  if led_t < 0.05 then return end
  led_t = 0
  if pulse and t < pulse[4] then
    local k = (pulse[4] - t) * 2
    if k > 1 then k = 1 end
    led.fill(math.floor(pulse[1] * k), math.floor(pulse[2] * k), math.floor(pulse[3] * k))
    return
  end
  pulse = nil
  local s = top()
  local n = led.count or 8
  if getmetatable(s) == Game and s.room then
    local th = s.room.thief
    local td = 999
    if th and not th.gone and not th.caught then td = math.sqrt((th.x - s.px) ^ 2 + (th.y - s.py) ^ 2) end
    if td < 10 then
      -- Someone is close: a scanner sweeps the row, faster as you close in.
      local near = 1 - td / 10
      local pos = (math.sin(t * (2 + near * 6)) * 0.5 + 0.5) * (n - 1)
      local r, gg, b = rgb(th.work.tint)
      for i = 1, n do
        local k = math.max(0, 1 - math.abs(i - 1 - pos)) * (0.3 + near * 0.7)
        led.set(i, math.floor(r * k), math.floor(gg * k), math.floor(b * k))
      end
      return
    end
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
      led.fill(math.floor(r * k), math.floor(gg * k), math.floor(b * k))
    else
      led.off()
    end
  elseif getmetatable(s) == Finale then
    local r, gg, b = rgb(ui.ACCENT)
    for i = 1, n do
      local k = 0.2 + 0.4 * (math.sin(t * 3 - i * 0.7) * 0.5 + 0.5)
      led.set(i, math.floor(r * k), math.floor(gg * k), math.floor(b * k))
    end
  elseif s == Title or s == Lanyard then
    -- The work on show breathes, a slow wave along the row.
    local p = on_show(s.art)
    local r, gg, b = rgb(p.tint)
    for i = 1, n do
      local k = 0.25 + 0.25 * math.sin(t * 1.5 + i * 0.8)
      led.set(i, math.floor(r * k), math.floor(gg * k), math.floor(b * k))
    end
  else
    led.off()
  end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

local function update(dt)
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

local function draw()
  local n = #stack
  if n == 0 or (stack[n].static and not dirty) then return end
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
    local x, y = (ui.W - w) // 2, 176 - h
    ui.slab(x, y, w, h, ui.PAPER, 3)
    g.rect(x + 2, y + 2, w - 4, h - 4, ui.PAPER_INK); g.rect(x + 4, y + 4, w - 8, h - 8, ui.PAPER_INK)
    ui.tracked_center(toast.text, 160, y + 8, ui.PAPER_INK, 1, 2)
    if sub then g.text_center(sub, 160, y + 20, ui.MUTED) end
  end
  -- The QR code belongs to the top scene; Solana OS draws it over the canvas.
  local spec = s.qr and s:qr() or nil
  if not g.show_qr(spec) then
    ui.tracked("NO QR ON THIS BADGE", spec[2] + 8, spec[3] + spec[4] // 2 - 10, ui.PAPER_INK, 1, 1)
    g.text("Update Solana OS", spec[2] + 8, spec[3] + spec[4] // 2 + 4, ui.MUTED)
  end
end

function on_tick(ms)
  -- Movement is by time, never by counting ticks; a stall is not a teleport.
  local dt = ms / 1000
  if dt > 0.1 then dt = 0.1 end
  held = sys.keys and sys.keys() or {}
  update(dt)
  draw()
end

-- Solana OS names the buttons up/down/left/right/select/back; the scenes speak
-- of "a" and "b" (kit.label prints them as SELECT and CANCEL).
local KEYS = { select = "a", back = "b" }
function on_key(key, rep)
  local k = KEYS[key] or key
  if rep and (k == "a" or k == "b") then return true end -- one press, one step back
  idle = 0
  dirty = true
  local s = top()
  if k == "b" and s == Title then return false end -- CANCEL at the front door leaves the app
  if s and s.button then s:button(k) end
  return true
end

function on_mesh(from, msg)
  local who = net.receive(from, msg)
  if who then
    say(who:upper() .. " WAVED", "Another janitor is on shift nearby.", 3)
    flash(ui.ACCENT, 1.2)
  end
end

function on_exit()
  record.flush()
  net.stop()
end

if DATA.schema ~= DATA_SCHEMA then
  error("data schema " .. tostring(DATA.schema) .. " needs a newer app (expects " .. DATA_SCHEMA .. ")")
end
rng = util.rng(math.random(1, 0x7FFFFFFF) ~ sys.millis())
record.load()
net.start()
push(Splash)
print("M.O.S.A. Night Shift " .. BUILD.version .. ", MOSA " .. DATA.source.mosa)

-- Test seam for tools/preview.mjs and test/app.test.mjs. Harmless on a badge.
mosa_debug = {
  state = function()
    local s = top()
    local game
    for i = #stack, 1, -1 do if getmetatable(stack[i]) == Game then game = stack[i]; break end end
    return string.format("scene=%s room=%s found=%d seen=%d left=%s depth=%d", s and s.name or "none",
      game and game.room and game.room.data.id or "-", record.found_count(), record.seen_count(),
      game and tostring(game:thieves_left()) or "-", #stack)
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
  heist = function()
    local gm, out = mosa_debug.game(), {}
    for _, h in ipairs(gm.plan) do out[#out + 1] = h.room end
    return table.concat(out, ",")
  end,
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
  -- Stand a couple of tiles from the thief in this room, facing them.
  face_thief = function()
    local gm = mosa_debug.game()
    local th = gm.room.thief
    if not th or th.gone then return false end
    for _, d in ipairs({ { 0, 2 }, { 0, -2 }, { 2, 0 }, { -2, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) do
      local x, y = th.x + d[1], th.y + d[2]
      if gm.room:fits(x, y, 0.3) then
        gm.px, gm.py = x, y
        local l = math.sqrt(d[1] * d[1] + d[2] * d[2])
        gm.fx, gm.fy = -d[1] / l, -d[2] / l
        th.turn, th.fx, th.fy = 99, 0, 0
        return true
      end
    end
    return false
  end,
  near = function(kind)
    local gm = mosa_debug.game()
    local list = (kind == "art" or kind == "missing") and gm.room.art or gm.room.data.marks
    for _, b in ipairs(list) do
      if (kind == "missing") == (b.missing == true) then
        for _, d in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 }, { 0, 2 } }) do
          local x, y = b.x + 0.5 + d[1], b.y + 0.5 + d[2]
          if gm.room:walkable(x, y) then
            gm.px, gm.py = x, y
            local s = b.s
            gm.fx, gm.fy = s == "e" and 1 or (s == "w" and -1 or 0), s == "s" and 1 or ((s == "e" or s == "w") and 0 or -1)
            return true
          end
        end
      end
    end
    return false
  end,
}
