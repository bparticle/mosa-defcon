-- The museum after hours, top-down.
--
-- A room's floor is MOSA's own claim volumes rasterised by the sync (rects in
-- tile units); doors are its portals; the furniture is its vitrines, boards
-- and machines. Nothing here knows any particular room: a new room in
-- MOSA-ROOMS.blend appears on the badge after `pnpm sync` with no code change.
--
-- Rendering is a flashlight: a small pool of light around the janitor and a
-- cone ahead of them. Tiles once seen stay faintly remembered.
local g = badge.gfx
local ui = require("ui")

local world = {}

local TILE = 14
world.TILE = TILE
local VOID, FLOOR, DOOR, BLOCK, WALL = 0, 1, 2, 3, 4

-- Light levels 0 (remembered) .. 3 (full). Concrete floor, white walls.
local FLOOR_C = { [0] = g.color(20, 20, 20), g.color(36, 35, 34), g.color(60, 58, 55), g.color(92, 89, 84) }
local WALL_C = { [0] = g.color(38, 38, 38), g.color(84, 82, 79), g.color(150, 147, 141), g.color(226, 222, 213) }
local MARK_C = { [0] = g.color(28, 28, 30), g.color(48, 50, 52), g.color(78, 82, 86), g.color(120, 126, 132) }
local SEAM_C = g.color(14, 14, 14)

local Room = {}
Room.__index = Room

-- Laying out a room is the heaviest thing the app does, and the badge kills
-- any callback that runs past 250 ms. So it runs as a coroutine: `pause` is
-- called between row bands and the caller spreads the work over frames
-- (main.lua shows a threshold while it does).
local BAND = 6

--- Lay out the grid (floor, doors, landmarks, walls) from synced data.
--- Pure function of the data, so a suspended room can be re-laid on return.
function Room:lay(pause)
  pause = pause or function() end
  local data, w, h = self.data, self.w, self.h
  local cells, door_at, mark_at = {}, {}, {}
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
        if cells[i] == FLOOR then cells[i] = BLOCK; mark_at[i] = m end
      end
    end
  end
  pause()
  -- Walls: every void cell touching something you can stand next to.
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local c = cells[row + x + 1]
      if c == FLOOR or c == DOOR or c == BLOCK then
        for ny = math.max(0, y - 1), math.min(h - 1, y + 1) do
          local nrow = ny * w + 1
          for nx = math.max(0, x - 1), math.min(w - 1, x + 1) do
            if cells[nrow + nx] == VOID then cells[nrow + nx] = WALL end
          end
        end
      end
    end
    if y % BAND == BAND - 1 then pause() end
  end
  -- What the torch has already shown, one byte per tile ("1" = seen).
  local explored, seen = {}, self.seen
  for i = 1, w * h do explored[i] = seen ~= nil and seen:byte(i) == 49 end
  self.cells, self.door_at, self.mark_at, self.explored, self.seen = cells, door_at, mark_at, explored, nil
end

--- Leaving a room: keep what is in it (bottles, balloons) but give back the
--- grid. With twelve rooms and a 1 MB heap, only the current one is laid out.
function Room:suspend()
  if not self.cells then return end
  local parts = {}
  for i = 1, self.w * self.h do parts[i] = self.explored[i] and "1" or "0" end
  self.seen = table.concat(parts)
  self.cells, self.explored, self.door_at, self.mark_at = nil, nil, nil, nil
end

function Room:resume(pause)
  if not self.cells then self:lay(pause) end
end

--- Build a playable room from synced data. `stock` picks what litters it.
function world.build(data, rng, stock, pause)
  pause = pause or function() end
  local w, h = data.w, data.h
  local r = setmetatable({ data = data, w = w, h = h, bottles = {}, balloons = {}, debris = {} }, Room)
  r:lay(pause)

  -- Free floor cells (as flat indices), for scattering bottles and balloons.
  local free = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if r.cells[y * w + x + 1] == FLOOR and not r:near_door(x, y, 2) then free[#free + 1] = y * w + x end
    end
    if y % BAND == BAND - 1 then pause() end
  end
  local taken = {}
  local function spot()
    for _ = 1, 40 do
      local i = free[rng:int(#free)]
      if not taken[i] then taken[i] = true; return i % w + 0.5, i // w + 0.5 end
    end
    return nil
  end
  if #free > 0 then
    for _ = 1, data.bottles do
      local piece = stock()
      local x, y = spot()
      if piece and x then r.bottles[#r.bottles + 1] = { x = x, y = y, piece = piece } end
    end
    for _ = 1, data.balloons do
      local x, y = spot()
      if x then
        r.balloons[#r.balloons + 1] = { x = x, y = y, phase = rng:float() * 6.28, colour = g.hsv(rng:int(360) - 1, 0.55, 0.95) }
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

--- Where to stand when arriving through the door that leads back to `from`.
function Room:arrival(from)
  local door
  for _, d in ipairs(self.data.doors) do if d.to == from then door = d; break end end
  if not door then
    -- No door back (a one-way warp, or the first room): the most open floor cell.
    local best, bx, by = -1, 1, 1
    for y = 1, self.h - 2 do
      for x = 1, self.w - 2 do
        if self:cell(x, y) == FLOOR then
          local n = 0
          for dy = -2, 2 do for dx = -2, 2 do if self:cell(x + dx, y + dy) == FLOOR then n = n + 1 end end end
          if n > best then best, bx, by = n, x, y end
        end
      end
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

--- The landmark within reach of (x, y), if any.
function Room:mark_near(x, y)
  local cx, cy = math.floor(x), math.floor(y)
  for dy = -1, 1 do
    for dx = -1, 1 do
      local m = self.mark_at[(cy + dy) * self.w + (cx + dx) + 1]
      if m and cx + dx >= 0 and cx + dx < self.w then return m end
    end
  end
  return nil
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

function Room:balloons_left()
  local n = 0
  for _, b in ipairs(self.balloons) do if not b.popped then n = n + 1 end end
  return n
end

--- Pop a balloon: debris flies, and sometimes a bottle falls out.
function Room:pop(b, rng, stock)
  b.popped = true
  for i = 1, 10 do
    local a = i * 0.628 + rng:float()
    local s = 2 + rng:float() * 3
    self.debris[#self.debris + 1] = { x = b.x, y = b.y - 0.3, vx = math.cos(a) * s, vy = math.sin(a) * s, life = 0.6, colour = b.colour }
  end
  if rng:float() < 0.35 then
    local piece = stock()
    if piece then self.bottles[#self.bottles + 1] = { x = b.x, y = b.y, piece = piece, dropped = 0.4 } end
  end
end

function Room:update(dt)
  for i = #self.debris, 1, -1 do
    local d = self.debris[i]
    d.life = d.life - dt
    if d.life <= 0 then table.remove(self.debris, i)
    else
      d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
      d.vx, d.vy = d.vx * 0.9, d.vy * 0.9 + 6 * dt
    end
  end
  for _, b in ipairs(self.bottles) do
    if b.dropped then b.dropped = b.dropped - dt; if b.dropped <= 0 then b.dropped = nil end end
  end
end

-- ── the flashlight ──────────────────────────────────────────────────────────

local function light_at(dx, dy, fx, fy)
  local d2 = dx * dx + dy * dy
  if d2 < 3.2 then return 3 end
  if d2 > 72 then return 0 end
  local d = math.sqrt(d2)
  local dot = (dx * fx + dy * fy) / d
  if dot > 0.8 then -- the torch beam
    if d < 4.5 then return 3 elseif d < 6.5 then return 2 else return 1 end
  elseif dot > 0.55 and d < 5.5 then
    return d < 3.5 and 2 or 1
  end
  if d2 < 6.5 then return 2 end
  if d2 < 11 then return 1 end
  return 0
end

--- Camera: top-left of the view in pixels, centred on the janitor.
function Room:camera(px, py)
  local vw, vh = ui.W, ui.H
  local rw, rh = self.w * TILE, self.h * TILE
  local cx = rw <= vw and (rw - vw) // 2 or math.floor(math.max(0, math.min(rw - vw, px * TILE - vw / 2)))
  local cy = rh <= vh and (rh - vh) // 2 or math.floor(math.max(0, math.min(rh - vh, py * TILE - vh / 2)))
  return cx, cy
end

--- Draw the room around a janitor at (px, py) facing (fx, fy).
local light = {} -- reused every frame: cell index → light level
function Room:draw(px, py, fx, fy, t)
  local cx, cy = self:camera(px, py)
  local x0, y0 = math.max(0, cx // TILE), math.max(0, cy // TILE)
  local x1, y1 = math.min(self.w - 1, (cx + ui.W) // TILE), math.min(self.h - 1, (cy + ui.H) // TILE)
  for k in pairs(light) do light[k] = nil end
  local w = self.w
  for y = y0, y1 do
    local sy = y * TILE - cy
    for x = x0, x1 do
      local i = y * w + x + 1
      local c = self.cells[i]
      if c ~= VOID then
        local l = light_at(x + 0.5 - px, y + 0.5 - py, fx, fy)
        if l > 0 then self.explored[i] = true end
        light[i] = l
        if l > 0 or self.explored[i] then
          local sx = x * TILE - cx
          if c == WALL then
            g.fill_rect(sx, sy, TILE, TILE, WALL_C[l])
          else
            g.fill_rect(sx, sy, TILE, TILE, FLOOR_C[l])
            if l >= 2 and y % 3 == 0 then g.line(sx, sy, sx + TILE - 1, sy, SEAM_C) end -- concrete pour seams
            if c == BLOCK then
              g.fill_rect(sx + 1, sy + 1, TILE - 2, TILE - 2, MARK_C[l])
              if l == 3 then g.rect(sx + 1, sy + 1, TILE - 2, TILE - 2, ui.MUTED) end
            elseif c == DOOR then
              -- A threshold: a lit strip and a notch of accent when close.
              g.fill_rect(sx + 2, sy + 2, TILE - 4, TILE - 4, l >= 2 and ui.DIM or FLOOR_C[0])
              if l == 3 then g.fill_rect(sx + 5, sy + 5, 4, 4, ui.ACCENT) end
            end
          end
        end
      end
    end
  end

  -- Bottles: drawn when lit; a far glint every couple of seconds otherwise,
  -- so the dark always has something to walk toward.
  for _, b in ipairs(self.bottles) do
    if not b.taken then
      local tx, ty = math.floor(b.x), math.floor(b.y)
      local l = light[ty * w + tx + 1] or 0
      local sx, sy = math.floor(b.x * TILE) - cx, math.floor(b.y * TILE) - cy
      local lift = b.dropped and math.floor(b.dropped * 20) or 0
      if l >= 1 then
        local col = b.piece.tint
        g.fill_rect(sx - 3, sy - 3 - lift, 7, 8, col)
        g.fill_rect(sx - 1, sy - 7 - lift, 3, 4, col)
        g.fill_rect(sx - 1, sy - 8 - lift, 3, 1, ui.INK)
        if l == 3 then g.fill_rect(sx - 2, sy - 2 - lift, 1, 4, ui.INK) end
      else
        local dx, dy = b.x - px, b.y - py
        if dx * dx + dy * dy < 196 and (t + b.x * 0.37) % 2.2 < 0.12 then
          g.pixel(sx, sy - 3, ui.INK)
          g.pixel(sx - 1, sy - 3, b.piece.tint); g.pixel(sx + 1, sy - 3, b.piece.tint)
        end
      end
    end
  end

  -- Balloons bob on their strings.
  for _, b in ipairs(self.balloons) do
    if not b.popped then
      local tx, ty = math.floor(b.x), math.floor(b.y)
      local l = light[ty * w + tx + 1] or 0
      if l >= 1 then
        local sx = math.floor(b.x * TILE) - cx
        local sy = math.floor(b.y * TILE + math.sin(t * 2 + b.phase) * 2) - cy - 6
        g.line(sx, sy + 6, sx + 2, sy + 13, ui.MUTED)
        g.fill_circle(sx, sy, 6, b.colour)
        g.fill_rect(sx - 3, sy - 3, 2, 2, ui.INK)
      end
    end
  end

  for _, d in ipairs(self.debris) do
    g.fill_rect(math.floor(d.x * TILE) - cx, math.floor(d.y * TILE) - cy, 2, 2, d.colour)
  end

  -- The janitor: overalls, a cap, and the torch in front.
  local sx, sy = math.floor(px * TILE) - cx, math.floor(py * TILE) - cy
  g.fill_rect(sx - 4, sy - 4, 9, 9, ui.INK)
  g.fill_rect(sx - 3, sy - 3, 7, 7, ui.DIM)
  g.fill_rect(sx - 1, sy - 1, 3, 3, ui.INK)
  local hx, hy = sx + math.floor(fx * 7 + 0.5), sy + math.floor(fy * 7 + 0.5)
  g.fill_rect(hx - 1, hy - 1, 3, 3, ui.ACCENT)
  return light
end

return world
