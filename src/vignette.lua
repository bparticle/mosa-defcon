-- Vignettes: the night's small scenes, in the footage's language. They say
-- what just happened instead of a counter saying it, and they never play the
-- same way twice: what they show is tonight's thieves, by kind, and tonight's
-- cards.
--
--   vignette.cell(...)  the holding cell, drawn small: on a RECOVERED card and
--                       at dawn, everyone caught tonight, behind bars
--   Holding             a break-in cleared: CAM 00 in the holding cell, this
--                       wave's thieves walk in, the bars come down, and one of
--                       them flicks a calling card at the camera
--   CallingCard         the card itself, paper and ink; the clipboard keeps it
--   InTheAct            the janitor was waiting in the room a card named: the
--                       thief reaches for the work, and the light comes on
--
-- main.lua hands them what they need through `vignette.scenes(ctx)`, so they
-- don't count against main.lua's 64 KB.
local g = require("gfx")
local ui = require("kit")
local sprites = require("sprites")
local light = require("light")

local vignette = {}

local BAR, RAIL = g.color(150, 146, 140), g.color(78, 76, 72)
local PLINTH, PLINTH_TOP = g.color(160, 157, 150), g.color(228, 224, 215)
local SKIN, SLEEVE = g.color(226, 182, 142), g.color(40, 40, 46)
local BENCH = g.color(58, 56, 52)
local SCAN = g.color(0, 0, 0)

--- One caught thief, passing the time the way their kind does. Feet at (x, y).
--- `t` moves them (0 holds a pose, for a static card); `i` sets them apart.
local function inmate(kind, x, y, t, s, i)
  local face, step = "down", 0
  if kind == "statue" then
    -- Still posing, out of habit, on a plinth of their own.
    g.fill_rect(x - 6 * s, y - 3 * s, 12 * s, 3 * s, PLINTH)
    g.fill_rect(x - 6 * s, y - 3 * s, 12 * s, s, PLINTH_TOP)
    y = y - 3 * s
    face = (i % 2 == 0) and "left" or "right"
  elseif kind == "dodger" then
    -- Pacing.
    local k = math.sin(t * 2.2 + i)
    x = x + math.floor(k * 3 * s)
    face = math.cos(t * 2.2 + i) > 0 and "right" or "left"
    step = t > 0 and (math.floor(t * 6 + i) % 2 + 1) or 0
  elseif kind == "swindler" then
    -- A card, between the fingers, now and then.
    if t == 0 or (t + i * 0.7) % 1.8 < 0.9 then g.fill_rect(x + 4 * s, y - 10 * s, 3 * s, 4 * s, ui.PAPER) end
  elseif t > 0 and (t * 0.5 + i) % 4 < 1 then
    face = "up" -- the creep: looking for a way out
  end
  sprites.draw("thief", face, step, x, y, s)
end

--- The holding cell, small: everyone in `kinds` (tonight's catches, in order)
--- behind bars, the latest at the front of the queue when there are too many.
function vignette.cell(x, y, w, h, kinds, t, s)
  s = s or 1
  g.fill_rect(x, y, w, h, ui.CONC)
  local n = #kinds
  local gap = 13 * s
  local fit = math.max(1, (w - 4 * s) // gap)
  local first = math.max(1, n - fit + 1)
  for i = first, n do
    inmate(kinds[i], x + 7 * s + (i - first) * gap, y + h - 2 * s, t, s, i)
  end
  for bx = x + 4 * s, x + w - 2 * s, 9 * s do g.fill_rect(bx, y, s, h, BAR) end
  g.fill_rect(x, y, w, 2 * s, RAIL)
  g.fill_rect(x, y + h - 2 * s, w, 2 * s, RAIL)
end

--- The camera's own marks round a monitor: scanlines, corner brackets, a label, REC.
local function camera(x, y, w, h, label, clock, T)
  for yy = y + 1, y + h - 1, 3 do g.fill_rect(x, yy, w, 1, SCAN) end
  local c = ui.INK
  for _, p in ipairs({ { x + 4, y + 4, 1, 1 }, { x + w - 5, y + 4, -1, 1 }, { x + 4, y + h - 5, 1, -1 }, { x + w - 5, y + h - 5, -1, -1 } }) do
    g.fill_rect(math.min(p[1], p[1] + p[3] * 9), p[2], 10, 1, c)
    g.fill_rect(p[1], math.min(p[2], p[2] + p[4] * 9), 1, 10, c)
  end
  g.text(label, x + 10, y + 8, c)
  if math.floor(T * 2) % 2 == 0 then g.fill_circle(x + w - 34, y + 11, 3, c) end
  g.text("REC", x + w - 28, y + 8, c)
  g.text_right(clock, x + w - 10, y + h - 14, c)
  g.rect(x - 2, y - 2, w + 4, h + 4, ui.DIM)
end

function vignette.scenes(ctx)
  local Holding, CallingCard, InTheAct = { name = "holding" }, { name = "callingcard" }, { name = "intheact" }

  -- ── the holding cell ──────────────────────────────────────────────────────
  Holding.__index = Holding
  local SX, SY, SW, SH = 8, 6, 304, 124
  local FEET = SY + SH - 10
  local IN, BARS, FLICK, DONE = 1.3, 1.7, 2.3, 3.0

  --- `kinds`: everyone caught tonight; the last `new` of them are this wave's.
  --- `card`: the calling card they leave for the next one, or nil.
  function Holding.new(kinds, new, card, clock)
    return setmetatable({ kinds = kinds, new = new, card = card, clock = clock, t = 0 }, Holding)
  end
  function Holding:update(dt)
    self.t = self.t + dt
    if self.t >= DONE + (self.card and 0.7 or 0.4) then self:finish() end
  end
  function Holding:finish()
    if ctx.top() ~= self then return end
    ctx.pop()
    if self.card then ctx.push(CallingCard.new(self.card)) end
  end

  --- Where the i-th of n stands, and whether they're still walking in.
  local function spot(i, n, old, T)
    local gap = math.min(40, 232 // math.max(1, n))
    local x = SX + 44 + (i - 1) * gap
    if i <= old then return x, "down", 0 end
    local start = (i - old - 1) * 0.22
    local k = math.max(0, math.min(1, (T - start) / (IN - 0.5)))
    if k >= 1 then return x, "down", 0 end
    return math.floor(SX + SW + 20 + (x - SX - SW - 20) * k), "left", (math.floor(T * 8) % 2) + 1
  end

  function Holding:draw()
    local T = self.t
    g.clear(ui.BG)
    -- The cell: a back wall, a bench, a floor.
    ui.concrete(SX, SY, SW, FEET - 24 - SY)
    g.fill_rect(SX, FEET - 24, SW, SY + SH - FEET + 24, g.color(22, 22, 21))
    g.fill_rect(SX + 20, FEET - 40, SW - 40, 6, BENCH)
    g.fill_rect(SX, FEET - 24, SW, 1, ui.SHADOW)
    local n, old = #self.kinds, #self.kinds - self.new
    local s = n <= 5 and 3 or 2
    local fx, fy
    for i, kind in ipairs(self.kinds) do
      local x, face, step = spot(i, n, old, T)
      if face == "down" then inmate(kind, x, FEET, i > old and T or T + 3, s, i)
      else sprites.draw("thief", face, step, x, FEET, s) end
      if i == n then fx, fy = x, FEET - 10 * s end
    end
    -- The bars come down.
    local k = math.max(0, math.min(1, (T - IN) / (BARS - IN)))
    if k > 0 then
      local len = math.floor((SH - 4) * k * k)
      for bx = SX + 30, SX + SW - 30, 22 do g.fill_rect(bx, SY + 2, 2, len, BAR) end
      g.fill_rect(SX + 26, SY + 2, SW - 52, 4, RAIL)
      if len > SH - 30 then g.fill_rect(SX + 26, SY + len - 6, SW - 52, 4, RAIL) end
    end
    -- Nothing outside the picture.
    g.fill_rect(0, SY, SX, SH, ui.BG); g.fill_rect(SX + SW, SY, ui.W - SX - SW, SH, ui.BG)
    camera(SX, SY, SW, SH, "CAM 00  HOLDING", self.clock, T)
    -- A card, flicked through the bars at the camera.
    if self.card and T >= FLICK and fx then
      local c = math.min(1, (T - FLICK) / 0.6)
      local w, h = math.floor(6 + 70 * c * c), math.floor(4 + 46 * c * c)
      local x = math.floor(fx + (160 - fx) * c) - w // 2
      local y = math.floor(fy + (SY + SH // 2 - fy) * c) - h // 2
      g.fill_rect(x + 2, y + 2, w, h, ui.SHADOW)
      g.fill_rect(x, y, w, h, ui.PAPER)
      if w > 30 then g.fill_rect(x + 6, y + 6, w - 12, 1, ui.PAPER_INK) end
    end
    if T > 0.3 then
      ui.tracked_center("ALL CLEAR, FOR NOW", 160, SY + SH + 12, ui.INK, 1, 3)
      local line = n .. (n == 1 and " thief" or " thieves") .. " behind bars tonight."
      if T > BARS then line = self.card and "One of them left you a card." or line end
      g.text_center(line, 160, SY + SH + 28, ui.MUTED)
    end
  end
  function Holding:button() self:finish() end

  -- ── the calling card ──────────────────────────────────────────────────────
  CallingCard.__index = CallingCard
  CallingCard.under = true
  CallingCard.static = true
  function CallingCard.new(card) return setmetatable({ card = card }, CallingCard) end
  function CallingCard:draw()
    local c = self.card
    local x, y, w, h = 46, 10, 228, 176
    g.fill_rect(x + 4, y + 4, w, h, ui.SHADOW)
    ui.slab(x, y, w, h)
    g.rect(x + 5, y + 5, w - 10, h - 10, ui.PAPER_INK)
    ui.tracked_center("WITH COMPLIMENTS", 160, y + 14, ui.PAPER_INK, 1, 3)
    g.fill_rect(x + 60, y + 26, w - 120, 1, ui.PAPER_INK)
    ui.paragraph(c.body, x + 16, y + 36, w - 32, ui.PAPER_INK, 1, 11)
    local sx = x + w - 16 - ui.tracked_width(c.sign, 1, 2)
    ui.tracked(c.sign, sx, y + h - 40, ui.PAPER_INK, 1, 2)
    g.fill_rect(sx - 10, y + h - 37, 6, 1, ui.PAPER_INK)
    sprites.draw("thief", "down", 0, x + 26, y + h - 12, 2)
    g.text("Be there when they come.", x + 52, y + h - 20, ui.MUTED)
    ui.hints({ "a", "back to work" })
  end
  function CallingCard:button(key) if key == "a" or key == "b" then ctx.pop() end end

  -- ── caught in the act ─────────────────────────────────────────────────────
  InTheAct.__index = InTheAct
  local FLOOR, JX, TX = 168, 48, 196
  local CLICK, SPOT, HANDS, WORDS, END = 0.9, 1.1, 1.4, 1.7, 4.2
  local BEAM_WALL, BEAM_FLOOR = g.color(168, 164, 156), g.color(104, 100, 94)

  function InTheAct.new(work, kind) return setmetatable({ work = work, kind = kind or "creep", t = 0 }, InTheAct) end
  function InTheAct:update(dt)
    local before = self.t
    self.t = self.t + dt
    if before < CLICK and self.t >= CLICK then ctx.flash(sprites.LENS, 0.3) end
    if self.t >= END then self:button() end
  end
  function InTheAct:draw()
    local T, work = self.t, self.work
    g.clear(ui.BG)
    local pw, ph = ui.size(work)
    local k = math.max(1, math.min(48 // pw, 48 // ph))
    local fw, fh = pw * k + 6, ph * k + 6
    local fx, fy = TX - fw // 2, 30
    if T < CLICK then
      -- The dark: the frame's edge, and two eyes under it.
      g.rect(fx, fy, fw, fh, ui.DIM)
      if (T * 3) % 1 < 0.7 then
        g.fill_rect(TX - 5, FLOOR - 37, 3, 3, ui.INK); g.fill_rect(TX + 3, FLOOR - 37, 3, 3, ui.INK)
      end
      if T > 0.2 then g.text("Someone came in. You were waiting.", 16, 196, ui.MUTED) end
      return
    end
    -- In the beam: the wall, the work still on it, and who was reaching for it.
    local lx, ly = JX + 12, FLOOR - 18
    local L = light.new(lx + 16, ly + 3, 0.915, -0.405, 300, 0.42, JX, FLOOR - 22, 34)
    for y = math.max(0, L.top), math.min(ui.H - 1, L.bottom) do
      local a1, b1, a2, b2 = light.row(L, y)
      local col = y < FLOOR - 20 and BEAM_WALL or BEAM_FLOOR
      if a1 then g.fill_rect(a1, y, b1 - a1 + 1, 1, col) end
      if a2 then g.fill_rect(a2, y, b2 - a2 + 1, 1, col) end
    end
    g.fill_rect(fx, fy, fw, fh, ui.PAPER)
    ui.thumb(work, fx + 3, fy + 3, k)
    g.fill_rect(TX - 1, fy - 4, 2, 3, ui.MUTED)
    local face = T < SPOT and "up" or "down"
    if T < HANDS then
      if T < SPOT then
        -- Reaching up: two sleeves to the frame.
        g.fill_rect(TX - 9, FLOOR - 72, 5, 26, SLEEVE); g.fill_rect(TX + 4, FLOOR - 72, 5, 26, SLEEVE)
        g.fill_rect(TX - 9, FLOOR - 76, 5, 4, SKIN); g.fill_rect(TX + 4, FLOOR - 76, 5, 4, SKIN)
      end
    else
      -- Hands up.
      g.fill_rect(TX - 17, FLOOR - 64, 5, 34, SLEEVE); g.fill_rect(TX + 12, FLOOR - 64, 5, 34, SLEEVE)
      g.fill_rect(TX - 17, FLOOR - 68, 5, 4, SKIN); g.fill_rect(TX + 12, FLOOR - 68, 5, 4, SKIN)
    end
    sprites.draw("thief", face, 0, TX, FLOOR, 3)
    if self.kind == "statue" and T >= SPOT then
      g.text("(not a sculpture)", TX - 50, FLOOR + 6, ui.MUTED)
    end
    if T >= SPOT and T < WORDS + 0.8 then
      g.fill_rect(TX + 22, FLOOR - 62, 9, 14, ui.INK)
      g.text("!", TX + 24, FLOOR - 59, ui.BG)
    end
    sprites.draw("janitor", "right", 0, JX, FLOOR, 3)
    g.fill_rect(lx, ly, 14, 6, sprites.TORCH)
    g.fill_rect(lx + 14, ly - 1, 3, 8, sprites.LENS)
    if T >= WORDS then
      ui.tracked("CAUGHT IN THE ACT", 16, 186, ui.INK, 1, 3)
      g.text(ui.fit(work.title, 160) .. " never left its wall.", 16, 200, ui.MUTED)
    end
  end
  function InTheAct:button()
    if self.t < CLICK + 0.1 then self.t = CLICK + 0.1; return end
    if ctx.top() == self then ctx.pop() end
  end

  return Holding, CallingCard, InTheAct
end

return vignette
