-- The museum after hours, top-down.
--
-- A room's floor is MOSA's own claim volumes rasterised by the sync (rects in
-- tile units); doors are its portals; the furniture is its vitrines, boards
-- and machines; the works hang where the HD museum hangs them and the bottles
-- lie on its find spots. Nothing here knows any particular room: a new room in
-- MOSA-ROOMS.blend appears on the badge after `pnpm sync` with no code change.
--
-- Rendering is a flashlight (light.lua): the lit room inside one cone and a
-- small pool at the janitor's feet, darkness outside. Tiles once seen stay as
-- a faint memory, and the exits always show, so nobody is lost in the dark.
local g = require("gfx")
local ui = require("kit")
local light = require("light")
local sprites = require("sprites")

local world = {}

local TILE = 14
world.TILE = TILE
local VOID, FLOOR, DOOR, BLOCK, WALL, PANEL = 0, 1, 2, 3, 4, 5

-- Lit: poured concrete and white walls, flat, the way a torch shows them.
local FLOOR_L, SEAM_L = g.color(96, 93, 88), g.color(78, 76, 72)
local WALL_L, FACE_L = g.color(228, 224, 215), g.color(160, 157, 150)
local MARK_L, MARK_EDGE = g.color(122, 128, 134), ui.MUTED
-- Remembered: just enough to know where the walls were.
local FLOOR_M, WALL_M, FACE_M = g.color(17, 17, 18), g.color(36, 36, 35), g.color(25, 25, 25)

-- The cone: 6.8 tiles long, 48 degrees wide; a pool of 1.5 tiles round the feet.
local REACH, HALF, POOL = 6.8 * TILE, 0.42, 1.5 * TILE

local Room = {}
Room.__index = Room

-- Laying out a room is the heaviest thing the app does, and Solana OS stops
-- any callback that runs past 200 000 Lua instructions. So it runs as a
-- coroutine: `pause` is called as the work adds up and the caller spreads it
-- over frames (main.lua shows a threshold while it does). The work is counted
-- in cell lookups, not rows: a wide room has long rows, and the badge counts
-- every instruction a coroutine runs against the tick that resumed it.
local SLICE = 1000 -- cell lookups per tick, about 25 000 instructions

--- A meter for `pause`: charge it the lookups done, and it pauses when a
--- slice is spent. Without a pause (a plain call) it never stops.
local function pacer(pause)
  if not pause then return function() end end
  local spent = 0
  return function(n)
    spent = spent + n
    if spent >= SLICE then spent = 0; pause() end
  end
end

--- Lay out the grid (floor, doors, landmarks, walls) from synced data.
--- Pure function of the data, so a suspended room can be re-laid on return.
function Room:lay(pause)
  local charge = pacer(pause)
  local data, w, h = self.data, self.w, self.h
  local cells, door_at, art_at = {}, {}, {}
  for i = 1, w * h do cells[i] = VOID end
  for _, rect in ipairs(data.rects) do
    for y = math.max(0, rect[2]), math.min(h - 1, rect[2] + rect[4] - 1) do
      local row = y * w + 1
      for x = math.max(0, rect[1]), math.min(w - 1, rect[1] + rect[3] - 1) do cells[row + x] = FLOOR end
    end
  end
  for _, d in ipairs(data.doors) do
    local i = d.y * w + d.x + 1
    cells[i] = DOOR
    door_at[i] = d
  end
  for _, m in ipairs(data.marks) do
    for y = m.y, m.y + m.h - 1 do
      for x = m.x, m.x + m.w - 1 do
        local i = y * w + x + 1
        if cells[i] == FLOOR then cells[i] = BLOCK end
      end
    end
  end
  -- A work with no wall beside it hangs on a free-standing panel.
  for _, a in ipairs(self.art) do
    local i = a.y * w + a.x + 1
    art_at[i] = a
    if not a.s and cells[i] == FLOOR then cells[i] = PANEL end
  end
  charge(SLICE)
  -- Walls: every void cell touching something you can stand next to.
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local c = cells[row + x + 1]
      if c ~= VOID and c ~= WALL then
        for ny = math.max(0, y - 1), math.min(h - 1, y + 1) do
          local nrow = ny * w + 1
          for nx = math.max(0, x - 1), math.min(w - 1, x + 1) do
            if cells[nrow + nx] == VOID then cells[nrow + nx] = WALL end
          end
        end
      end
    end
    charge(w * 10)
  end
  -- What the torch has already shown, one byte per tile ("1" = seen).
  local explored, seen = {}, self.seen
  for i = 1, w * h do explored[i] = seen ~= nil and seen:byte(i) == 49 end
  self.cells, self.door_at, self.art_at = cells, door_at, art_at
  self.explored, self.seen = explored, nil
end

--- Leaving a room: keep what is in it (bottles, works, a thief) but give back
--- the grid. Only the current room is laid out: the heap stays small and the
--- collector has little to walk.
function Room:suspend()
  if not self.cells then return end
  local parts = {}
  for i = 1, self.w * self.h do parts[i] = self.explored[i] and "1" or "0" end
  self.seen = table.concat(parts)
  self.cells, self.explored, self.door_at, self.art_at = nil, nil, nil, nil
  for _, a in ipairs(self.art) do a.mini = nil end
end

function Room:resume(pause)
  if not self.cells then self:lay(pause) end
  -- A thief who ran in here while the room was folded away.
  local inc = self.incoming
  if inc then self.incoming = nil; self:let_in(inc[1], inc[2]) end
end

--- Build a playable room from synced data.
---   opts.rng, opts.pause
---   opts.stock()   picks the next bottle that litters it
---   opts.works     work idx -> synced work, for what hangs here
---   opts.heist     a work idx a thief has taken from this room tonight, or nil
function world.build(data, opts)
  local charge = pacer(opts.pause)
  local rng = opts.rng
  local w, h = data.w, data.h
  local r = setmetatable({ data = data, w = w, h = h, bottles = {}, art = {} }, Room)
  for _, a in ipairs(data.art or {}) do
    local work = opts.works[a.w]
    if work then r.art[#r.art + 1] = { x = a.x, y = a.y, s = a.s, work = work, missing = opts.heist == a.w } end
  end
  r:lay(opts.pause)

  -- Free floor cells (as flat indices), for bottles and the thief.
  local free = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if r.cells[y * w + x + 1] == FLOOR and not r:near_door(x, y, 2) then free[#free + 1] = y * w + x end
    end
    charge(w * (1 + 2 * #data.doors))
  end
  local taken = {}
  local function spot()
    for _ = 1, 40 do
      local i = free[rng:int(#free)]
      if not taken[i] then taken[i] = true; return i % w + 0.5, i // w + 0.5 end
    end
    return nil
  end
  -- Bottles lie on the HD museum's own find spots first, in a shuffled order.
  local spots = {}
  for _, s in ipairs(data.spots or {}) do
    local i = s[2] * w + s[1]
    if r.cells[i + 1] == FLOOR and not taken[i] then spots[#spots + 1] = i end
  end
  for i = #spots, 2, -1 do
    local j = rng:int(i)
    spots[i], spots[j] = spots[j], spots[i]
  end
  if #free > 0 then
    for n = 1, data.bottles do
      local piece = opts.stock()
      local x, y
      local s = spots[n]
      if s then taken[s] = true; x, y = s % w + 0.5, s // w + 0.5 else x, y = spot() end
      if piece and x then r.bottles[#r.bottles + 1] = { x = x, y = y, piece = piece } end
    end
    if opts.heist then
      local work = opts.works[opts.heist]
      local x, y = spot()
      if work and x then
        r.thief = { x = x, y = y, work = work, fx = 0, fy = 1, heat = 0, step = 0, turn = 0, seen = false }
      end
    end
  end
  return r
end

function Room:cell(x, y)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return VOID end
  return self.cells[y * self.w + x + 1]
end

function Room:near_door(x, y, radius)
  for _, d in ipairs(self.data.doors) do
    if math.abs(d.x - x) <= radius and math.abs(d.y - y) <= radius then return true end
  end
  return false
end

function Room:walkable(x, y)
  local c = self:cell(math.floor(x), math.floor(y))
  return c == FLOOR or c == DOOR
end

--- Can a body of radius r stand at (x, y)?
function Room:fits(x, y, r)
  return self:walkable(x - r, y - r) and self:walkable(x + r, y - r)
    and self:walkable(x - r, y + r) and self:walkable(x + r, y + r)
end

--- Move a body by (dx, dy), sliding along walls. Returns the new position.
function Room:slide(x, y, dx, dy, r)
  if self:fits(x + dx, y, r) then x = x + dx end
  if self:fits(x, y + dy, r) then y = y + dy end
  return x, y
end

--- Where to stand when arriving through the door that leads back to `from`.
function Room:arrival(from, pause)
  local door
  for _, d in ipairs(self.data.doors) do if d.to == from then door = d; break end end
  if not door then
    -- No door back (a teleport, or the first room): the most open floor cell,
    -- the one with the most floor in the 5x5 around it. Rows are read straight
    -- from the grid (a 92-wide room is 2 300 lookups a row), metered by `pause`.
    local charge = pacer(pause)
    local cells, w, h = self.cells, self.w, self.h
    local best, bx, by = -1, 1, 1
    for y = 2, h - 3 do
      for x = 2, w - 3 do
        if cells[y * w + x + 1] == FLOOR then
          local n = 0
          for dy = -2, 2 do
            local row = (y + dy) * w + x + 1
            for i = row - 2, row + 2 do if cells[i] == FLOOR then n = n + 1 end end
          end
          if n > best then best, bx, by = n, x, y end
        end
      end
      charge(w * 26)
    end
    return bx + 0.5, by + 0.5
  end
  -- The neighbour of the door with the most floor around it, so we face inward.
  local best, bx, by = -1, door.x, door.y
  for dy = -1, 1 do
    for dx = -1, 1 do
      local x, y = door.x + dx, door.y + dy
      if (dx ~= 0 or dy ~= 0) and self:cell(x, y) == FLOOR then
        local n = 0
        for ey = -1, 1 do for ex = -1, 1 do if self:cell(x + ex, y + ey) == FLOOR then n = n + 1 end end end
        if n > best then best, bx, by = n, x, y end
      end
    end
  end
  return bx + 0.5, by + 0.5
end

function Room:door_under(x, y)
  return self.door_at[math.floor(y) * self.w + math.floor(x) + 1]
end

--- The work within reach of (x, y): hung beside the tile you stand on or next to.
function Room:art_near(x, y)
  local best, bd = nil, 2.6
  for _, a in ipairs(self.art) do
    local dx, dy = a.x + 0.5 - x, a.y + 0.5 - y
    local d = dx * dx + dy * dy
    if d < bd then best, bd = a, d end
  end
  return best
end

function Room:nearest_door(x, y, radius)
  local best, bd = nil, radius * radius
  for _, d in ipairs(self.data.doors) do
    local dx, dy = d.x + 0.5 - x, d.y + 0.5 - y
    local dd = dx * dx + dy * dy
    if dd < bd then best, bd = d, dd end
  end
  return best
end

-- ── the thief ───────────────────────────────────────────────────────────────
-- A thief creeps about the dark with a work under one arm. In the light they
-- are dazzled: slow, and making for the nearest door away from the janitor.
-- Footsteps close by in the dark send them for a door too. Held in the beam
-- long enough (HEAT seconds), they drop the work; reach a door first and they
-- are away into the next room, work and all.

local SNEAK, DAZZLED, HEAT, HEAR = 1.7, 1.25, 1.1, 3.2

--- The door a thief would run for: the nearest one on the far side from the
--- janitor, into a room `ok(to)` allows.
function Room:escape_door(th, jx, jy, ok)
  local best, bd = nil, nil
  local ax, ay = th.x - jx, th.y - jy
  for _, d in ipairs(self.data.doors) do
    local dx, dy = d.x + 0.5 - th.x, d.y + 0.5 - th.y
    if dx * ax + dy * ay > 0 and (not ok or ok(d.to)) then
      local dd = dx * dx + dy * dy
      if not bd or dd < bd then best, bd = d, dd end
    end
  end
  return best
end

--- A thief arriving through the door from `from` (one that got away next door).
function Room:let_in(work, from)
  if not self.cells then self.incoming = { work, from }; return end
  -- Always through a door: this runs inside a tick, with no pause to spread
  -- the open-floor search over.
  local back = false
  for _, d in ipairs(self.data.doors) do if d.to == from then back = true end end
  if not back and self.data.doors[1] then from = self.data.doors[1].to end
  local x, y = self:arrival(from)
  self.thief = { x = x, y = y, work = work, fx = 0, fy = 1, heat = 0, step = 0, turn = 0.6, seen = false }
end

--- Advance the thief; returns "caught" the moment they give up, or "fled" and
--- the door they got away through.
function Room:update_thief(dt, jx, jy, lit, rng, ok)
  local th = self.thief
  if not th or th.gone then return nil end
  if th.caught then
    th.caught = th.caught - dt
    if th.caught <= 0 then th.gone = true end
    return nil
  end
  local speed = SNEAK
  local ax, ay = th.x - jx, th.y - jy
  local heard = not lit and ax * ax + ay * ay < HEAR * HEAR
  local run = not th.stay and (lit or heard) and self:escape_door(th, jx, jy, ok)
  -- The moment they hear you: a "!" over their head, even in the dark.
  if run and not th.running then th.alert = 0.8 end
  th.running = run and true or false
  if th.alert then th.alert = th.alert > dt and th.alert - dt or nil end
  if lit then
    th.seen = true
    th.heat = th.heat + dt
    speed = DAZZLED
    if th.heat >= HEAT then
      th.caught = 0.6
      return "caught"
    end
  else
    th.heat = math.max(0, th.heat - dt * 0.5)
  end
  if run then
    local dx, dy = run.x + 0.5 - th.x, run.y + 0.5 - th.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 0.01 then th.fx, th.fy = dx / d, dy / d end
  elseif lit then
    -- Nowhere to run: away from the janitor.
    local d = math.sqrt(ax * ax + ay * ay)
    if d > 0.01 then th.fx, th.fy = ax / d, ay / d end
  else
    th.turn = th.turn - dt
    if th.turn <= 0 then
      th.turn = 0.8 + rng:float() * 1.6
      local a = rng:float() * 6.283
      th.fx, th.fy = math.cos(a), math.sin(a)
    end
  end
  local ox, oy = th.x, th.y
  th.x, th.y = self:slide(th.x, th.y, th.fx * speed * dt, th.fy * speed * dt, 0.3)
  local moved = math.abs(th.x - ox) + math.abs(th.y - oy)
  if moved < speed * dt * 0.3 then
    -- Cornered: turn and try another way next tick.
    local a = rng:float() * 6.283
    th.fx, th.fy, th.turn = math.cos(a), math.sin(a), 0.5
  end
  th.step = th.step + moved
  if run then
    local door = self:door_under(th.x, th.y)
    if door then th.gone = true; return "fled", door end
  end
  return nil
end

--- A work's frame-sized miniature: n x n colours sampled from its sprite,
--- made when the room is laid out and dropped when it is left.
local function mini(a, n)
  if a.mini then return a.mini end
  a.mini = ui.sample(a.work, n)
  return a.mini
end

-- ── drawing ─────────────────────────────────────────────────────────────────

--- Camera: top-left of the view in pixels, centred on the janitor.
function Room:camera(px, py)
  local vw, vh = ui.W, ui.H
  local rw, rh = self.w * TILE, self.h * TILE
  local cx = rw <= vw and (rw - vw) // 2 or math.floor(math.max(0, math.min(rw - vw, px * TILE - vw / 2)))
  local cy = rh <= vh and (rh - vh) // 2 or math.floor(math.max(0, math.min(rh - vh, py * TILE - vh / 2)))
  return cx, cy
end

-- The lit room is drawn a scanline at a time, but all TILE scanlines of a
-- tile row cross the same tiles. So each tile row is turned once into colour
-- runs, one list per kind of scanline (plain, a pour seam, a board mark, a
-- wall's face), plus the insides of its doors, landmarks and panels; a
-- scanline then only clips its list to the light. A frame of light is a few
-- hundred rects.
local hline = g.hline
local PLAIN, SEAM, BOARD, FACE = 1, 2, 3, 4

-- One kind of scanline across a tile row, as runs { x0, x1, colour, ... }.
local function build(tr, kind)
  local cells, w, row, cx = tr.cells, tr.w, tr.row, tr.cx
  local list, run_c, run_x, n = {}, nil, 0, 0
  for tx = tr.tx0, tr.tx1 do
    local i = row + tx
    local c = cells[i]
    local col
    if c == WALL then
      col = WALL_L
      if kind == BOARD then col = FACE_L
      elseif kind == FACE then
        local below = cells[i + w]
        if below and below ~= WALL then col = FACE_L end
      end
    elseif c ~= VOID then
      col = kind == SEAM and SEAM_L or FLOOR_L
    end
    if col ~= run_c then
      local sx = tx * TILE - cx
      if run_c then list[n + 1], list[n + 2], list[n + 3] = run_x, sx - 1, run_c; n = n + 3 end
      run_x, run_c = sx, col
    end
  end
  if run_c then list[n + 1], list[n + 2], list[n + 3] = run_x, (tr.tx1 + 1) * TILE - cx - 1, run_c end
  return list
end

-- A tile row between tx0 and tx1: its insides now, its runs as they're needed
-- (a row with no wall in it draws every kind of line the same way).
local function tile_row(self, ty, tx0, tx1, cx)
  local cells, w = self.cells, self.w
  local row = ty * w + 1
  local tr = { cells = cells, w = w, row = row, cx = cx, tx0 = tx0, tx1 = tx1, insides = {} }
  local walls, ins = false, tr.insides
  for tx = tx0, tx1 do
    local c = cells[row + tx]
    if c == WALL then walls = true
    elseif c == BLOCK or c == PANEL or c == DOOR then
      local sx = tx * TILE - cx
      ins[#ins + 1] = sx; ins[#ins + 1] = sx + TILE - 1; ins[#ins + 1] = c
    end
  end
  tr.walls = walls
  return tr
end

local function runs_for(tr, kind)
  if not tr.walls and (kind == BOARD or kind == FACE) then kind = PLAIN end
  local list = tr[kind]
  if not list then list = build(tr, kind); tr[kind] = list end
  return list
end

local function inside_colour(c, r)
  local inset = c == DOOR and 2 or 1
  if r < inset or r > TILE - 1 - inset then return nil, inset end
  if c == DOOR then return (r >= 5 and r <= 8) and ui.ACCENT or ui.DIM, inset end
  if c == PANEL then return ui.CONC, inset end
  return (r == inset or r == TILE - 1 - inset) and MARK_EDGE or MARK_L, inset
end

-- One lit scanline (or h identical ones): the tile row's runs for this kind
-- of line, clipped to [xa, xb].
local function lit_span(tr, kind, r, yy, xa, xb, h)
  local list, insides = runs_for(tr, kind), tr.insides
  for k = 1, #list, 3 do
    local x0, x1 = list[k], list[k + 1]
    if x1 >= xa and x0 <= xb then
      if x0 < xa then x0 = xa end
      if x1 > xb then x1 = xb end
      hline(x0, yy, x1 - x0 + 1, list[k + 2], h)
    end
  end
  for k = 1, #insides, 3 do
    local col, inset = inside_colour(insides[k + 2], r)
    if col then
      local x0, x1 = insides[k] + inset, insides[k + 1] - inset
      if x1 >= xa and x0 <= xb then
        if x0 < xa then x0 = xa end
        if x1 > xb then x1 = xb end
        hline(x0, yy, x1 - x0 + 1, col, h)
      end
    end
  end
end

local function line_kind(r, ty)
  if r == 0 and ty % 3 == 0 then return SEAM elseif r == 4 then return BOARD elseif r >= TILE - 5 then return FACE end
  return PLAIN
end

-- Can scanline r + 1 of this tile row be drawn as a copy of scanline r?
local function same_next(insides, r, ty)
  if r >= TILE - 1 or line_kind(r, ty) ~= line_kind(r + 1, ty) then return false end
  for k = 3, #insides, 3 do
    if inside_colour(insides[k], r) ~= inside_colour(insides[k], r + 1) then return false end
  end
  return true
end

-- Where a work hangs on screen: the middle of its wall tile, nudged toward
-- the floor it faces; on its own tile when it hangs on a panel.
local SIDE = { n = { 0, -1 }, s = { 0, 1 }, e = { 1, 0 }, w = { -1, 0 } }
local function hang_at(a, cx, cy)
  local d = SIDE[a.s]
  local x, y = a.x * TILE - cx + TILE // 2, a.y * TILE - cy + TILE // 2
  if d then x, y = x + d[1] * (TILE - 3), y + d[2] * (TILE - 3) end
  return x, y
end

local function draw_frame(a, x, y)
  if a.missing then
    -- The empty frame: a pale outline round a dark rectangle, and the nail.
    g.rect(x - 5, y - 5, 11, 11, ui.MUTED)
    g.fill_rect(x - 4, y - 4, 9, 9, ui.BG)
    g.pixel(x, y - 3, ui.INK)
    return
  end
  g.fill_rect(x - 6, y - 6, 13, 13, ui.SHADOW)
  g.rect(x - 5, y - 5, 11, 11, ui.PAPER)
  local m = mini(a, 9)
  for j = 0, 8 do
    for i = 0, 8 do g.fill_rect(x - 4 + i, y - 4 + j, 1, 1, m[j * 9 + i + 1]) end
  end
end

-- The beam fades out: from FADE of its reach on, an ordered (4x4 Bayer)
-- pattern lets the dark back in, a little more in each of the bands, until
-- the cone's end. The pool round the feet stays a hard circle. The dark
-- pixels are the memory's colours, so the beam dissolves into what the
-- room looks like after the torch has passed.
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local FADE = 0.5
local DARK = { 3, 6, 9, 12 } -- of 16 pixels, band by band
-- MASK[band][row % 4 + 1]: a bit per x (mod 4) that goes dark on that row.
local MASK = {}
for k, n in ipairs(DARK) do
  MASK[k] = {}
  for r = 0, 3 do
    local m = 0
    for x = 0, 3 do if BAYER[r * 4 + x + 1] < n then m = m | (1 << x) end end
    MASK[k][r + 1] = m
  end
end

-- The memory's colour of tile (tx, ty) on scanline r of its row.
local function memory_colour(cells, w, h, tx, ty, r)
  if ty < 0 or ty >= h or tx < 0 or tx >= w then return ui.BG end
  local i = ty * w + tx + 1
  local c = cells[i]
  if c == VOID then return ui.BG end
  if c == WALL then
    local below = cells[i + w]
    return (r >= TILE - 5 and below and below ~= WALL) and FACE_M or WALL_M
  end
  return FLOOR_M
end

-- Dots are 2x2 screen pixels: the pattern reads as pixel art, and it is a
-- quarter of the draws a 1-pixel dither would cost. Which dots go dark
-- depends only on the beam's direction (the d-pad gives eight), so each
-- direction's dots are worked out once, relative to the lens, and a frame
-- only places them: the pattern travels with the light.
local fades = {}
local function fade_key(fx, fy) return math.floor(fx * 100 + 0.5) * 1000 + math.floor(fy * 100 + 0.5) end
local function fade_dots(fx, fy)
  local dots = {}
  local R, n = REACH, #DARK
  local q = {}
  for k = 0, n do local rk = R * (FADE + (1 - FADE) * k / n); q[k + 1] = rk * rk end
  local L = light.new(0, 0, fx, fy, R, HALF, 0, 0, 0)
  local top = math.floor(-R) // 2 * 2
  for oy = top, math.ceil(R), 2 do
    local lo, hi = light.cone(L, oy)
    if lo then
      local v = (oy // 2) % 4
      for u = math.ceil(lo / 2), math.floor((hi - 1) / 2) do
        local dx, dy = u * 2 + 1, oy + 1
        local dd = dx * dx + dy * dy
        if dd >= q[1] then
          local band = 1
          while band < n and dd >= q[band + 1] do band = band + 1 end
          if (MASK[band][v + 1] >> (u % 4)) & 1 == 1 then dots[#dots + 1] = string.char(u + 128, oy // 2 + 128) end
        end
      end
    end
  end
  -- Two bytes a dot (its column and row, in dots, offset by 128): a few
  -- hundred bytes a direction instead of a table of numbers.
  fades[fade_key(fx, fy)] = table.concat(dots)
end

--- Work out the fade for the eight directions the d-pad gives, one a call
--- to `pause`; the room loader runs it once (a frame draws no fade for a
--- direction it doesn't have yet).
function world.warm(pause)
  local s = math.sqrt(0.5)
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { s, s }, { -s, s }, { s, -s }, { -s, -s } }) do
    if not fades[fade_key(d[1], d[2])] then fade_dots(d[1], d[2]); if pause then pause() end end
  end
end

local function dither(self, L, cx, cy)
  local cells, w, h = self.cells, self.w, self.h
  local bx, by = math.floor(L.ax), math.floor(L.ay)
  local dots = fades[fade_key(L.fx, L.fy)]
  if not dots then return end
  local W1, H1 = ui.W - 2, ui.H - 2
  local tile, ty, col = -1, -1, nil
  local byte = string.byte
  for i = 1, #dots, 2 do
    local du, dv = byte(dots, i, i + 1)
    local x, y = bx + du * 2 - 256, by + dv * 2 - 256
    if x >= 0 and x <= W1 and y >= 0 and y <= H1 then
      local tx, sy = (x + cx) // TILE, y + cy
      local t2 = sy // TILE
      if tx ~= tile or t2 ~= ty then
        tile, ty = tx, t2
        col = memory_colour(cells, w, h, tx, t2, sy % TILE)
      elseif sy % TILE == TILE - 5 or sy % TILE == TILE - 4 then
        col = memory_colour(cells, w, h, tx, t2, sy % TILE)
      end
      hline(x, y, 2, col, 2)
    end
  end
end

--- Draw the room around a janitor at (px, py) facing (fx, fy). `walk` is the
--- janitor's stride (0, 1, 2). Returns the light, for asking what it shows.
function Room:draw(px, py, fx, fy, t, walk)
  local cx, cy = self:camera(px, py)
  local x0, y0 = math.max(0, cx // TILE), math.max(0, cy // TILE)
  local x1, y1 = math.min(self.w - 1, (cx + ui.W) // TILE), math.min(self.h - 1, (cy + ui.H) // TILE)
  local w, cells, explored = self.w, self.cells, self.explored

  -- The memory: what the torch has shown before, barely there. Runs of the
  -- same kind along a tile row are one rect.
  for y = y0, y1 do
    local sy = y * TILE - cy
    local row = y * w + 1
    local run_x, run_c = 0, nil
    for x = x0, x1 + 1 do
      local i = row + x
      local c = x <= x1 and cells[i] or VOID
      local col
      if c ~= VOID and explored[i] then col = c == WALL and WALL_M or FLOOR_M end
      if col ~= run_c then
        local sx = x * TILE - cx
        if run_c then g.fill_rect(run_x, sy, sx - run_x, TILE, run_c) end
        run_x, run_c = sx, col
      end
    end
    for x = x0, x1 do
      local i = row + x
      if cells[i] == WALL and explored[i] then
        local below = cells[i + w]
        if below and below ~= WALL then g.fill_rect(x * TILE - cx, sy + TILE - 5, TILE, 5, FACE_M) end
      end
    end
  end

  -- The light, from the lens in the janitor's hand.
  local face = sprites.facing(fx, fy)
  local jx, jy = math.floor(px * TILE) - cx, math.floor(py * TILE) - cy
  local hx, hy = sprites.hand(face)
  local L = light.new(jx + hx + fx * 4, jy + hy + fy * 4, fx, fy, REACH, HALF, jx, jy - 5, POOL)
  local top, bottom = math.max(0, L.top), math.min(ui.H - 1, L.bottom)
  local lx0 = math.max(x0, (math.floor(math.min(L.ax - L.reach, L.px - L.pool)) + cx) // TILE)
  local lx1 = math.min(x1, (math.ceil(math.max(L.ax + L.reach, L.px + L.pool)) + cx) // TILE)
  local cur, runs, lo, hi = -1, nil, 9999, -9999
  local function remember()
    -- Everything the light crossed on the tile row just finished.
    if cur >= 0 and lo <= hi then
      local row = cur * w + 1
      for tx = math.max(0, (lo + cx) // TILE), math.min(w - 1, (hi + cx) // TILE) do explored[row + tx] = true end
    end
  end
  -- Scanlines go two at a time where the second would repeat the first: the
  -- cone's edge steps by two pixels, which the pixel art doesn't mind.
  local yy = top
  while yy <= bottom do
    local ty = (yy + cy) // TILE
    if ty ~= cur then
      remember()
      cur, lo, hi = ty, 9999, -9999
      runs = nil
      if ty >= 0 and ty < self.h then
        -- Only the tiles the light reaches on this row: its widest at the
        -- band's top, middle or bottom (each part of the light is round or straight).
        local band = ty * TILE - cy
        local e0, e1 = 9999, -9999
        for _, sy in ipairs({ band, band + TILE // 2, band + TILE - 1 }) do
          local p, q, p2, q2 = light.row(L, math.max(top, math.min(bottom, sy)))
          if p then
            if p < e0 then e0 = p end
            if (q2 or q) > e1 then e1 = q2 or q end
          end
        end
        local tx0 = math.max(lx0, (e0 - 8 + cx) // TILE)
        local tx1 = math.min(lx1, (e1 + 8 + cx) // TILE)
        if tx0 <= tx1 then runs = tile_row(self, ty, tx0, tx1, cx) end
      end
    end
    local r = (yy + cy) % TILE
    local h = 1
    if runs and yy < bottom and same_next(runs.insides, r, ty) then h = 2 end
    if runs then
      local a1, b1, a2, b2 = light.row(L, yy)
      if a1 then
        local kind = line_kind(r, ty)
        if a1 < 0 then a1 = 0 end
        if b1 > ui.W - 1 then b1 = ui.W - 1 end
        lit_span(runs, kind, r, yy, a1, b1, h)
        if a1 < lo then lo = a1 end
        if b1 > hi then hi = b1 end
        if a2 then
          if a2 < 0 then a2 = 0 end
          if b2 > ui.W - 1 then b2 = ui.W - 1 end
          lit_span(runs, kind, r, yy, a2, b2, h)
          if a2 < lo then lo = a2 end
          if b2 > hi then hi = b2 end
        end
      end
    end
    yy = yy + h
  end
  remember()
  dither(self, L, cx, cy)

  -- Exits glow in the dark like exit signs, so the way out is never lost: a
  -- chevron pointing through the doorway, for the doors within a few rooms' walk.
  for _, d in ipairs(self.data.doors) do
    local sx, sy = d.x * TILE - cx, d.y * TILE - cy
    local ddx, ddy = d.x + 0.5 - px, d.y + 0.5 - py
    if sx > -TILE and sx < ui.W and sy > -TILE and sy < ui.H and ddx * ddx + ddy * ddy < 196
      and not light.lit(L, sx + 7, sy + 7) then
      if not d.ox then
        d.ox, d.oy = 0, -1
        for _, o in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
          if self:cell(d.x + o[1], d.y + o[2]) == VOID then d.ox, d.oy = o[1], o[2]; break end
        end
      end
      local mx, my = sx + 7, sy + 7
      for i = 0, 2 do
        -- Three rows of a chevron, its tip toward the way out.
        local along, across = 2 - i, i + 1
        if d.oy ~= 0 then g.fill_rect(mx - across, my + d.oy * along, 1, 1, ui.ACCENT); g.fill_rect(mx + across - 1, my + d.oy * along, 1, 1, ui.ACCENT)
        else g.fill_rect(mx + d.ox * along, my - across, 1, 1, ui.ACCENT); g.fill_rect(mx + d.ox * along, my + across - 1, 1, 1, ui.ACCENT) end
      end
    end
  end

  -- Works on the walls, in the light.
  for _, a in ipairs(self.art) do
    local sx, sy = hang_at(a, cx, cy)
    if sx > -8 and sx < ui.W + 8 and sy > -8 and sy < ui.H + 8 and light.lit(L, sx, sy) then draw_frame(a, sx, sy) end
  end

  -- Bottles: drawn when lit; a far glint every couple of seconds otherwise,
  -- so the dark always has something to walk toward.
  for _, b in ipairs(self.bottles) do
    if not b.taken then
      local sx, sy = math.floor(b.x * TILE) - cx, math.floor(b.y * TILE) - cy
      if light.lit(L, sx, sy) then
        local col = b.piece.tint
        g.fill_rect(sx - 3, sy - 3, 7, 8, col)
        g.fill_rect(sx - 1, sy - 7, 3, 4, col)
        g.fill_rect(sx - 1, sy - 8, 3, 1, ui.INK)
        g.fill_rect(sx - 2, sy - 2, 1, 4, ui.INK)
      else
        local dx, dy = b.x - px, b.y - py
        if dx * dx + dy * dy < 196 and (t + b.x * 0.37) % 2.2 < 0.12 then
          g.pixel(sx, sy - 3, ui.INK)
          g.pixel(sx - 1, sy - 3, b.piece.tint); g.pixel(sx + 1, sy - 3, b.piece.tint)
        end
      end
    end
  end

  -- The thief: seen only in the light. In the dark, now and then, two eyes.
  local th = self.thief
  local behind = th and not th.gone and th.y < py
  local function draw_thief()
    local sx, sy = math.floor(th.x * TILE) - cx, math.floor(th.y * TILE) - cy
    if th.caught then
      -- Gone in a scatter of dust, the work left behind.
      local k = math.floor((0.6 - th.caught) * 30)
      for i = 0, 5 do
        local a = i * 1.047
        g.fill_rect(sx + math.floor(math.cos(a) * k), sy - 8 + math.floor(math.sin(a) * k), 2, 2, ui.MUTED)
      end
      return
    end
    if light.lit(L, sx, sy - 6) then
      local stride = (th.step * 3) // 1 % 4
      local tface = sprites.facing(th.fx, th.fy)
      sprites.draw("thief", tface, stride == 1 and 1 or (stride == 3 and 2 or 0), sx, sy)
      -- The loot: the stolen work, frame and all, under an arm.
      local lx = sx + (tface == "left" and -9 or 4)
      g.rect(lx, sy - 11, 6, 7, ui.PAPER)
      g.fill_rect(lx + 1, sy - 10, 4, 5, th.work.tint)
      if th.alert then
        g.fill_rect(sx - 3, sy - 31, 7, 11, ui.INK)
        g.text("!", sx - 2, sy - 29, ui.BG)
      end
      -- How long they have been dazzled: a bar over their head that fills.
      if th.heat > 0 then
        local w = math.min(12, math.floor(12 * th.heat / HEAT))
        g.fill_rect(sx - 7, sy - 22, 14, 4, ui.SHADOW)
        g.fill_rect(sx - 6, sy - 21, 12, 2, ui.DIM)
        g.fill_rect(sx - 6, sy - 21, w, 2, ui.INK)
      end
    elseif th.alert then
      g.fill_rect(sx - 3, sy - 31, 7, 11, ui.INK)
      g.text("!", sx - 2, sy - 29, ui.BG)
    elseif (t * 0.7 + th.x) % 3 < 0.35 then
      local dx, dy = th.x - px, th.y - py
      if dx * dx + dy * dy < 81 then
        g.pixel(sx - 2, sy - 11, ui.INK); g.pixel(sx + 1, sy - 11, ui.INK)
      end
    end
  end
  if behind then draw_thief() end

  -- The janitor, and the flashlight in hand.
  sprites.draw("janitor", face, walk or 0, jx, jy)
  if face ~= "up" then sprites.torch(jx + hx, jy + hy, fx, fy) end

  if th and not th.gone and not behind then draw_thief() end
  return L, cx, cy
end

--- Is the thief in the light `L` (as Room:draw returned it)?
function Room:thief_lit(L, cx, cy)
  local th = self.thief
  if not th or th.gone or th.caught or not L then return false end
  return light.lit(L, th.x * TILE - cx, th.y * TILE - cy - 6)
end

return world
