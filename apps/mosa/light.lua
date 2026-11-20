-- The flashlight: one hard-edged area of light, and darkness everywhere else.
--
-- The lit area is a cone from the lens (a circular sector, `reach` long and
-- 2 x `half` wide) joined to a small pool around the janitor's feet. Both are
-- convex, so every screen row crosses each in one interval: the renderer asks
-- for a row's spans and paints the lit room only inside them. A row costs a
-- few multiplications, so a whole frame of light is ~200 of them.
local light = {}

--- A light from the lens at (ax, ay) along unit (fx, fy), with a pool of
--- radius `pool` centred at (px, py). Lengths in pixels, `half` in radians.
function light.new(ax, ay, fx, fy, reach, half, px, py, pool)
  local c, s = math.cos(half), math.sin(half)
  -- Inward normals of the cone's two edges (edge directions f rotated by ±half).
  local e1x, e1y = fx * c - fy * s, fx * s + fy * c
  local e2x, e2y = fx * c + fy * s, -fx * s + fy * c
  local L = {
    ax = ax, ay = ay, fx = fx, fy = fy, reach = reach,
    n1x = e1y, n1y = -e1x, n2x = -e2y, n2y = e2x,
    px = px, py = py, pool = pool,
  }
  -- Make sure both normals point into the cone (toward f).
  if L.n1x * fx + L.n1y * fy < 0 then L.n1x, L.n1y = -L.n1x, -L.n1y end
  if L.n2x * fx + L.n2y * fy < 0 then L.n2x, L.n2y = -L.n2x, -L.n2y end
  -- The rows it can touch.
  L.top = math.floor(math.min(ay - reach, py - pool))
  L.bottom = math.ceil(math.max(ay + reach, py + pool))
  return L
end

-- Clip [lo, hi] by the half-plane n . (x - ax, dy) >= 0 on one row.
local function clip(lo, hi, nx, ny, ax, dy)
  local k = -ny * dy
  if nx > 1e-6 then
    local x = ax + k / nx
    if x > lo then lo = x end
  elseif nx < -1e-6 then
    local x = ax + k / nx
    if x < hi then hi = x end
  elseif k > 0 then
    return 1, 0
  end
  return lo, hi
end

--- The lit spans of screen row y: up to two { a, b } pairs, as integers,
--- returned flat (a1, b1, a2, b2); nil when the row is dark.
function light.row(L, y)
  local yy = y + 0.5
  local a1, b1, a2, b2
  local dy = yy - L.ay
  if dy * dy <= L.reach * L.reach then
    local h = math.sqrt(L.reach * L.reach - dy * dy)
    local lo, hi = L.ax - h, L.ax + h
    lo, hi = clip(lo, hi, L.n1x, L.n1y, L.ax, dy)
    lo, hi = clip(lo, hi, L.n2x, L.n2y, L.ax, dy)
    if lo <= hi then a1, b1 = lo, hi end
  end
  local py = yy - L.py
  if py * py <= L.pool * L.pool then
    local h = math.sqrt(L.pool * L.pool - py * py)
    local lo, hi = L.px - h, L.px + h
    if not a1 then a1, b1 = lo, hi
    elseif lo <= b1 + 1 and hi >= a1 - 1 then
      if lo < a1 then a1 = lo end
      if hi > b1 then b1 = hi end
    else
      a2, b2 = lo, hi
    end
  end
  if not a1 then return nil end
  a1, b1 = math.floor(a1 + 0.5), math.floor(b1 - 0.5)
  if a2 then a2, b2 = math.floor(a2 + 0.5), math.floor(b2 - 0.5) end
  return a1, b1, a2, b2
end

--- Is the point (x, y) in the light?
function light.lit(L, x, y)
  local dx, dy = x - L.px, y - L.py
  if dx * dx + dy * dy <= L.pool * L.pool then return true end
  dx, dy = x - L.ax, y - L.ay
  if dx * dx + dy * dy > L.reach * L.reach then return false end
  return dx * L.n1x + dy * L.n1y >= 0 and dx * L.n2x + dy * L.n2y >= 0
end

return light
