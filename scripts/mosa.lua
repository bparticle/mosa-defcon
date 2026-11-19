-- M.O.S.A. Night Shift: walk the museum after hours, find the bottles, scan into the HD museum.
-- v0.1.0 · MOSA f1d804c · data 38243503a8b7a901
-- Built by tools/bundle.mjs from src/. Edit the sources, not this file.
package.preload["util"] = function(...)
local util = {}
local Rng = {}
Rng.__index = Rng
function util.rng(seed)
local s = seed & 0xFFFFFFFF
if s == 0 then s = 0x2545F491 end
return setmetatable({ s = s }, Rng)
end
function Rng:next()
local x = self.s
x = x ~ ((x << 13) & 0xFFFFFFFF)
x = x ~ ((x & 0xFFFFFFFF) >> 17)
x = x ~ ((x << 5) & 0xFFFFFFFF)
self.s = x & 0xFFFFFFFF
return self.s
end
function Rng:float()
return ((self:next() >> 8) & 0xFFFFFF) / 16777216
end
function Rng:int(n)
return ((self:next() >> 1) & 0x7FFFFFFF) % n + 1
end
function Rng:weighted(list)
local total = 0
for _, item in ipairs(list) do total = total + item.weight end
if total <= 0 then return nil end
local r = self:float() * total
for _, item in ipairs(list) do
r = r - item.weight
if r < 0 then return item end
end
return list[#list]
end
local B32 = "0123456789abcdefghjkmnpqrstvwxyz"
function util.base32(bits)
local out = {}
for i = 1, #bits, 5 do
local v = 0
for j = 0, 4 do v = (v << 1) | (bits[i + j] or 0) end
out[#out + 1] = B32:sub(v + 1, v + 1)
end
return table.concat(out)
end
function util.bits_from_hex(s)
local set = {}
for i = 1, #(s or "") do
local v = tonumber(s:sub(i, i), 16) or 0
for b = 0, 3 do
if (v >> b) & 1 == 1 then set[(i - 1) * 4 + b] = true end
end
end
return set
end
function util.bits_to_hex(set, n)
local out = {}
for i = 0, (n + 3) // 4 - 1 do
local v = 0
for b = 0, 3 do
if set[i * 4 + b] then v = v | (1 << b) end
end
out[#out + 1] = string.format("%x", v)
end
return table.concat(out)
end
function util.count(set)
local n = 0
for _ in pairs(set) do n = n + 1 end
return n
end
function util.clamp(v, lo, hi)
if v < lo then return lo elseif v > hi then return hi end
return v
end
return util
end
package.preload["qr"] = function(...)
local qr = {}
local SPEC = {
{ ec = 10, blocks = { { 1, 16 } } },
{ ec = 16, blocks = { { 1, 28 } } },
{ ec = 26, blocks = { { 1, 44 } } },
{ ec = 18, blocks = { { 2, 32 } } },
{ ec = 24, blocks = { { 2, 43 } } },
{ ec = 16, blocks = { { 4, 27 } } },
{ ec = 18, blocks = { { 4, 31 } } },
{ ec = 22, blocks = { { 2, 38 }, { 2, 39 } } },
{ ec = 22, blocks = { { 3, 36 }, { 2, 37 } } },
{ ec = 26, blocks = { { 4, 43 }, { 1, 44 } } },
}
local ALIGN = {
{}, { 6, 18 }, { 6, 22 }, { 6, 26 }, { 6, 30 }, { 6, 34 },
{ 6, 22, 38 }, { 6, 24, 42 }, { 6, 26, 46 }, { 6, 28, 50 },
}
qr.MAX_VERSION = #SPEC
local function data_capacity(v)
local n = 0
for _, b in ipairs(SPEC[v].blocks) do n = n + b[1] * b[2] end
return n
end
local EXP, LOG = {}, {}
do
local x = 1
for i = 0, 254 do
EXP[i] = x
LOG[x] = i
x = x << 1
if x & 0x100 ~= 0 then x = x ~ 0x11D end
end
for i = 255, 511 do EXP[i] = EXP[i - 255] end
end
local function gmul(a, b)
if a == 0 or b == 0 then return 0 end
return EXP[LOG[a] + LOG[b]]
end
local divisors = {}
local function divisor(degree)
if divisors[degree] then return divisors[degree] end
local r = {}
for i = 1, degree - 1 do r[i] = 0 end
r[degree] = 1
local root = 1
for _ = 1, degree do
for j = 1, degree do
r[j] = gmul(r[j], root)
if j < degree then r[j] = r[j] ~ r[j + 1] end
end
root = gmul(root, 2)
end
divisors[degree] = r
return r
end
local function rs_remainder(data, degree)
local div = divisor(degree)
local res = {}
for i = 1, degree do res[i] = 0 end
for _, b in ipairs(data) do
local factor = b ~ res[1]
table.remove(res, 1)
res[degree] = 0
for i = 1, degree do res[i] = res[i] ~ gmul(div[i], factor) end
end
return res
end
local function codewords(text, v)
local bits = {}
local function put(value, n)
for i = n - 1, 0, -1 do bits[#bits + 1] = (value >> i) & 1 end
end
put(4, 4) -- byte mode
put(#text, v <= 9 and 8 or 16)
for i = 1, #text do put(text:byte(i), 8) end
local cap = data_capacity(v) * 8
for _ = 1, math.min(4, cap - #bits) do bits[#bits + 1] = 0 end
while #bits % 8 ~= 0 do bits[#bits + 1] = 0 end
local data = {}
for i = 1, #bits, 8 do
local byte = 0
for j = 0, 7 do byte = (byte << 1) | bits[i + j] end
data[#data + 1] = byte
end
local pad = 0xEC
while #data < data_capacity(v) do
data[#data + 1] = pad
pad = (pad == 0xEC) and 0x11 or 0xEC
end
local spec, blocks, pos = SPEC[v], {}, 1
for _, group in ipairs(spec.blocks) do
for _ = 1, group[1] do
local d = {}
for i = 1, group[2] do d[i] = data[pos]; pos = pos + 1 end
blocks[#blocks + 1] = { data = d, ec = rs_remainder(d, spec.ec) }
end
end
local out, longest = {}, 0
for _, b in ipairs(blocks) do longest = math.max(longest, #b.data) end
for i = 1, longest do
for _, b in ipairs(blocks) do
if b.data[i] then out[#out + 1] = b.data[i] end
end
end
for i = 1, spec.ec do
for _, b in ipairs(blocks) do out[#out + 1] = b.ec[i] end
end
return out
end
local function new_grid(size)
local g = {}
for i = 1, size * size do g[i] = 0 end
return g
end
local function function_patterns(v)
local size = v * 4 + 17
local m, fn = new_grid(size), new_grid(size)
local function set(x, y, dark)
local i = y * size + x + 1
m[i] = dark and 1 or 0
fn[i] = 1
end
for i = 0, size - 1 do
set(6, i, i % 2 == 0)
set(i, 6, i % 2 == 0)
end
local function finder(cx, cy)
for dy = -4, 4 do
for dx = -4, 4 do
local x, y = cx + dx, cy + dy
if x >= 0 and x < size and y >= 0 and y < size then
local d = math.max(math.abs(dx), math.abs(dy))
set(x, y, d ~= 2 and d ~= 4)
end
end
end
end
finder(3, 3); finder(size - 4, 3); finder(3, size - 4)
local a = ALIGN[v]
for i = 1, #a do
for j = 1, #a do
local corner = (i == 1 and j == 1) or (i == 1 and j == #a) or (i == #a and j == 1)
if not corner then
for dy = -2, 2 do
for dx = -2, 2 do
set(a[i] + dx, a[j] + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
end
end
end
end
end
for i = 0, 8 do
if i ~= 6 then set(8, i, false); set(i, 8, false) end
end
for i = 0, 7 do set(size - 1 - i, 8, false) end
for i = 0, 6 do set(8, size - 1 - i, false) end
set(8, size - 8, true) -- the dark module
if v >= 7 then
local rem = v
for _ = 1, 12 do rem = (rem << 1) ~ ((rem >> 11) * 0x1F25) end
local bits = (v << 12) | rem
for i = 0, 17 do
local bit = (bits >> i) & 1 == 1
local p, q = size - 11 + i % 3, i // 3
set(p, q, bit); set(q, p, bit)
end
end
return m, fn, size
end
local function place_data(m, fn, size, data)
local i, total = 0, #data * 8
local right = size - 1
while right >= 1 do
if right == 6 then right = 5 end
for vert = 0, size - 1 do
for j = 0, 1 do
local x = right - j
local upward = ((right + 1) & 2) == 0
local y = upward and (size - 1 - vert) or vert
local idx = y * size + x + 1
if fn[idx] == 0 and i < total then
m[idx] = (data[(i >> 3) + 1] >> (7 - (i & 7))) & 1
i = i + 1
end
end
end
right = right - 2
end
end
local MASKS = {
[0] = function(x, y) return (x + y) % 2 == 0 end,
function(_, y) return y % 2 == 0 end,
function(x, _) return x % 3 == 0 end,
function(x, y) return (x + y) % 3 == 0 end,
function(x, y) return (x // 3 + y // 2) % 2 == 0 end,
function(x, y) return x * y % 2 + x * y % 3 == 0 end,
function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end,
}
local function apply_mask(m, fn, size, mask)
local f = MASKS[mask]
for y = 0, size - 1 do
for x = 0, size - 1 do
local idx = y * size + x + 1
if fn[idx] == 0 and f(x, y) then m[idx] = 1 - m[idx] end
end
end
end
local function draw_format(m, size, mask)
local data = (0 << 3) | mask -- ECC M is 00
local rem = data
for _ = 1, 10 do rem = (rem << 1) ~ ((rem >> 9) * 0x537) end
local bits = ((data << 10) | rem) ~ 0x5412
local function set(x, y, i) m[y * size + x + 1] = (bits >> i) & 1 end
for i = 0, 5 do set(8, i, i) end
set(8, 7, 6); set(8, 8, 7); set(7, 8, 8)
for i = 9, 14 do set(14 - i, 8, i) end
for i = 0, 7 do set(size - 1 - i, 8, i) end
for i = 8, 14 do set(8, size - 15 + i, i) end
m[(size - 8) * size + 8 + 1] = 1
end
local function penalty(m, size)
local score, dark = 0, 0
local rows, cols = {}, {}
for y = 0, size - 1 do
local r = {}
for x = 0, size - 1 do
local v = m[y * size + x + 1]
r[x + 1] = v
dark = dark + v
end
rows[y + 1] = table.concat(r)
end
for x = 0, size - 1 do
local c = {}
for y = 0, size - 1 do c[y + 1] = m[y * size + x + 1] end
cols[x + 1] = table.concat(c)
end
local function lines(list)
for _, s in ipairs(list) do
for run in s:gmatch("1+") do if #run >= 5 then score = score + #run - 2 end end
for run in s:gmatch("0+") do if #run >= 5 then score = score + #run - 2 end end
local padded = "0000" .. s .. "0000"
local start = 1
while true do
local a = padded:find("1011101", start, true)
if not a then break end
if padded:sub(a - 4, a - 1) == "0000" or padded:sub(a + 7, a + 10) == "0000" then score = score + 40 end
start = a + 1
end
end
end
lines(rows); lines(cols)
for y = 0, size - 2 do
local r1, r2 = rows[y + 1], rows[y + 2]
for x = 1, size - 1 do
local a = r1:byte(x)
if a == r1:byte(x + 1) and a == r2:byte(x) and a == r2:byte(x + 1) then score = score + 3 end
end
end
local total = size * size
local k = (math.abs(dark * 20 - total * 10) + total - 1) // total - 1
if k > 0 then score = score + k * 10 end
return score
end
function qr.version_for(text)
for v = 1, #SPEC do
local header = 4 + (v <= 9 and 8 or 16)
if header + #text * 8 <= data_capacity(v) * 8 then return v end
end
return nil
end
function qr.encoder(text)
local v = qr.version_for(text)
if not v then error("text too long for a version " .. #SPEC .. " QR code (" .. #text .. " bytes)") end
local co = coroutine.create(function()
local data = codewords(text, v)
local base, fn, size = function_patterns(v)
place_data(base, fn, size, data)
coroutine.yield()
local best, best_mask, best_score = nil, 0, math.huge
for mask = 0, 7 do
local m = {}
for i = 1, #base do m[i] = base[i] end
apply_mask(m, fn, size, mask)
draw_format(m, size, mask)
local s = penalty(m, size)
if s < best_score then best, best_mask, best_score = m, mask, s end
coroutine.yield()
end
return { size = size, modules = table.concat(best), version = v, mask = best_mask }
end)
return function()
local ok, result = coroutine.resume(co)
if not ok then error(result) end
return result
end
end
function qr.dark(code, x, y)
return code.modules:byte(y * code.size + x + 1) == 49
end
function qr.encode(text)
local step = qr.encoder(text)
while true do
local r = step()
if r then return r end
end
end
return qr
end
package.preload["ui"] = function(...)
local g = badge.gfx
local ui = {}
ui.BG = g.color(11, 11, 12)
ui.INK = g.color(236, 232, 224)
ui.PAPER = g.color(236, 232, 224)
ui.PAPER_INK = g.color(18, 18, 18)
ui.MUTED = g.color(132, 128, 120)
ui.DIM = g.color(58, 56, 54)
ui.CAST = g.color(170, 166, 158) -- plaster
ui.ACCENT = g.color(0x7e, 0xe8, 0xa8)
ui.W, ui.H = 320, 240
function ui.tracked(s, x, y, col, size, gap)
size, gap = size or 1, gap or 2
local step = 6 * size + gap
for i = 1, #s do
g.text(s:sub(i, i), x + (i - 1) * step, y, col, size)
end
return #s * step - gap
end
function ui.tracked_width(s, size, gap)
size, gap = size or 1, gap or 2
return #s * (6 * size + gap) - gap
end
function ui.tracked_center(s, cx, y, col, size, gap)
return ui.tracked(s, cx - ui.tracked_width(s, size, gap) // 2, y, col, size, gap)
end
function ui.wrap(text, width, size)
local per = math.max(1, width // (6 * (size or 1)))
local lines, line = {}, ""
for word in tostring(text):gmatch("%S+") do
while #word > per do
if #line > 0 then lines[#lines + 1] = line; line = "" end
lines[#lines + 1] = word:sub(1, per)
word = word:sub(per + 1)
end
if #line == 0 then line = word
elseif #line + 1 + #word <= per then line = line .. " " .. word
else lines[#lines + 1] = line; line = word end
end
if #line > 0 then lines[#lines + 1] = line end
return lines
end
function ui.paragraph(text, x, y, width, col, size, leading)
size = size or 1
leading = leading or (10 * size)
local lines = ui.wrap(text, width, size)
for i, l in ipairs(lines) do g.text(l, x, y + (i - 1) * leading, col, size) end
return #lines * leading
end
function ui.fit(s, width, size)
local per = width // (6 * (size or 1))
if #s <= per then return s end
return s:sub(1, math.max(1, per - 1)) .. "~"
end
function ui.hints(list, y, col)
y = y or 228
local parts = {}
for i = 1, #list, 2 do
parts[#parts + 1] = { badge.input.label(list[i]), list[i + 1] }
end
local width = 0
for _, p in ipairs(parts) do width = width + (#p[1] + #p[2] + 1) * 6 + 14 end
local x = (ui.W - width + 14) // 2
for _, p in ipairs(parts) do
g.text(p[1], x, y, ui.ACCENT)
x = x + #p[1] * 6 + 6
g.text(p[2], x, y, col or ui.MUTED)
x = x + #p[2] * 6 + 14
end
end
function ui.qr(code, x, y, scale, dark, light)
dark, light = dark or ui.PAPER_INK, light or ui.PAPER
local q = 3 * scale -- quiet zone (3 modules reads fine on an LCD)
local size = code.size * scale + q * 2
g.fill_rect(x, y, size, size, light)
local m, n = code.modules, code.size
for row = 0, n - 1 do
local base, run = row * n, -1
for col = 0, n do
local on = col < n and m:byte(base + col + 1) == 49
if on and run < 0 then run = col
elseif not on and run >= 0 then
g.fill_rect(x + q + run * scale, y + q + row * scale, (col - run) * scale, scale, dark)
run = -1
end
end
end
return size
end
function ui.qr_scale(code, box)
return math.max(1, box // (code.size + 6))
end
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local COUNT, HEX = {}, {}
for i = 1, 64 do COUNT[B64:byte(i)] = i end
for i = 0, 15 do HEX[(string.format("%x", i)):byte()] = i end
local palettes = {}
local function palette(piece)
local pal = palettes[piece.idx]
if not pal then
pal = {}
for i = 1, #piece.pal // 4 do pal[i] = tonumber(piece.pal:sub(i * 4 - 3, i * 4), 16) end
palettes[piece.idx] = pal
end
return pal
end
function ui.thumb(piece, x, y, scale, cast)
local s = piece.rle
if not s then return end
scale = scale or 1
local pal = palette(piece)
local pos = 0
for i = 1, #s - 1, 2 do
local n, c = COUNT[s:byte(i)], HEX[s:byte(i + 1)]
if c > 0 then
local col = cast or pal[c]
local p, left = pos, n
while left > 0 do
local px = p % 16
local len = math.min(left, 16 - px)
g.fill_rect(x + px * scale, y + (p // 16) * scale, len * scale, scale, col)
p, left = p + len, left - len
end
end
pos = pos + n
end
end
ui.TIER = { common = "COMMON", rare = "RARE", legendary = "LEGENDARY", mythical = "MYTHICAL" }
return ui
end
package.preload["world"] = function(...)
local g = badge.gfx
local ui = require("ui")
local world = {}
local TILE = 14
world.TILE = TILE
local VOID, FLOOR, DOOR, BLOCK, WALL = 0, 1, 2, 3, 4
local FLOOR_C = { [0] = g.color(20, 20, 20), g.color(36, 35, 34), g.color(60, 58, 55), g.color(92, 89, 84) }
local WALL_C = { [0] = g.color(38, 38, 38), g.color(84, 82, 79), g.color(150, 147, 141), g.color(226, 222, 213) }
local MARK_C = { [0] = g.color(28, 28, 30), g.color(48, 50, 52), g.color(78, 82, 86), g.color(120, 126, 132) }
local SEAM_C = g.color(14, 14, 14)
local Room = {}
Room.__index = Room
local BAND = 6
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
local explored, seen = {}, self.seen
for i = 1, w * h do explored[i] = seen ~= nil and seen:byte(i) == 49 end
self.cells, self.door_at, self.mark_at, self.explored, self.seen = cells, door_at, mark_at, explored, nil
end
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
function world.build(data, rng, stock, pause)
pause = pause or function() end
local w, h = data.w, data.h
local r = setmetatable({ data = data, w = w, h = h, bottles = {}, balloons = {}, debris = {} }, Room)
r:lay(pause)
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
function Room:arrival(from)
local door
for _, d in ipairs(self.data.doors) do if d.to == from then door = d; break end end
if not door then
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
function Room:camera(px, py)
local vw, vh = ui.W, ui.H
local rw, rh = self.w * TILE, self.h * TILE
local cx = rw <= vw and (rw - vw) // 2 or math.floor(math.max(0, math.min(rw - vw, px * TILE - vw / 2)))
local cy = rh <= vh and (rh - vh) // 2 or math.floor(math.max(0, math.min(rh - vh, py * TILE - vh / 2)))
return cx, cy
end
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
g.fill_rect(sx + 2, sy + 2, TILE - 4, TILE - 4, l >= 2 and ui.DIM or FLOOR_C[0])
if l == 3 then g.fill_rect(sx + 5, sy + 5, 4, 4, ui.ACCENT) end
end
end
end
end
end
end
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
local sx, sy = math.floor(px * TILE) - cx, math.floor(py * TILE) - cy
g.fill_rect(sx - 4, sy - 4, 9, 9, ui.INK)
g.fill_rect(sx - 3, sy - 3, 7, 7, ui.DIM)
g.fill_rect(sx - 1, sy - 1, 3, 3, ui.INK)
local hx, hy = sx + math.floor(fx * 7 + 0.5), sy + math.floor(fy * 7 + 0.5)
g.fill_rect(hx - 1, hy - 1, 3, 3, ui.ACCENT)
return light
end
return world
end
package.preload["record"] = function(...)
local util = require("util")
local record = {}
local kv = badge.storage.kv
local SCHEMA = "1"
local state = {
found = {},   -- piece idx → true
rooms = {},   -- room idx → true (visited)
goals = {},   -- "roomId/goalId" → true
pickups = 0,
pops = 0,
shifts = 0,
mic = true,
}
record.state = state
local function getn(key)
return tonumber(kv.get(key, "0")) or 0
end
function record.load()
if kv.get("v", "") ~= SCHEMA then
kv.set("v", SCHEMA)
end
state.found = util.bits_from_hex(kv.get("found", ""))
state.rooms = util.bits_from_hex(kv.get("rooms", ""))
state.goals = {}
for g in (kv.get("goals", "")):gmatch("[^;]+") do state.goals[g] = true end
state.pickups = getn("pickups")
state.pops = getn("pops")
state.shifts = getn("shifts")
state.mic = kv.get("mic", "1") == "1"
end
local function save_bits(key, set)
local max = -1
for i in pairs(set) do if i > max then max = i end end
kv.set(key, util.bits_to_hex(set, max + 1))
end
function record.find(piece)
state.pickups = state.pickups + 1
kv.set("pickups", tostring(state.pickups))
if state.found[piece.idx] then return false end
state.found[piece.idx] = true
save_bits("found", state.found)
return true
end
function record.visit(room)
if state.rooms[room.idx] then return false end
state.rooms[room.idx] = true
save_bits("rooms", state.rooms)
return true
end
function record.stamp(room_id, goal_id)
local key = room_id .. "/" .. goal_id
if state.goals[key] then return false end
state.goals[key] = true
local list = {}
for k in pairs(state.goals) do list[#list + 1] = k end
table.sort(list)
kv.set("goals", table.concat(list, ";"))
return true
end
function record.pop()
state.pops = state.pops + 1
if state.pops % 5 == 0 then kv.set("pops", tostring(state.pops)) end
end
function record.clock_in()
state.shifts = state.shifts + 1
kv.set("shifts", tostring(state.shifts))
end
function record.set_mic(on)
state.mic = on
kv.set("mic", on and "1" or "0")
end
function record.flush()
kv.set("pops", tostring(state.pops))
end
function record.found_count()
return util.count(state.found)
end
function record.report_code(piece_count)
local bits = {}
local function put(v, n) for i = n - 1, 0, -1 do bits[#bits + 1] = (v >> i) & 1 end end
put(1, 4)
for i = 0, 15 do bits[#bits + 1] = state.rooms[i] and 1 or 0 end
for i = 0, piece_count - 1 do bits[#bits + 1] = state.found[i] and 1 or 0 end
return util.base32(bits)
end
return record
end
package.preload["net"] = function(...)
local net = { peers = {}, on = false, waves = {} }
local PREFIX = "MOSA1 "
local INTERVAL_MS = 2500
local FRESH_MS = 9000
local last = -INTERVAL_MS
function net.start()
local ok, res = pcall(badge.espnow.enable, true)
net.on = ok and res ~= false
return net.on
end
function net.stop()
if net.on then pcall(badge.espnow.enable, false) end
net.on = false
end
local function send(line)
if not net.on then return false end
local ok = pcall(badge.espnow.broadcast, PREFIX .. line)
return ok
end
function net.update(room_id, found)
if not net.on then return end
local now = badge.millis()
if now - last >= INTERVAL_MS then
last = now
send("P " .. room_id .. " " .. tostring(found))
end
end
function net.wave(name)
return send("W " .. tostring(name):gsub("%s", "_"):sub(1, 23))
end
function net.receive(mac, data)
if type(data) ~= "string" or data:sub(1, #PREFIX) ~= PREFIX then return nil end
local kind, a, b = data:sub(#PREFIX + 1):match("^(%a) (%S+) ?(%S*)")
if kind == "P" then
net.peers[mac] = { at = badge.millis(), room = a, found = tonumber(b) or 0 }
elseif kind == "W" then
net.peers[mac] = net.peers[mac] or { at = badge.millis(), room = "?", found = 0 }
net.peers[mac].at = badge.millis()
return (a:gsub("_", " "))
end
return nil
end
function net.nearby()
local n, now = 0, badge.millis()
for mac, p in pairs(net.peers) do
if now - p.at <= FRESH_MS then n = n + 1 else net.peers[mac] = nil end
end
return n
end
return net
end
package.preload["data.mosa_data"] = function(...)
return {
schema=1,
source={mosa="f1d804c59a35",rooms="d8ab158eca69d5a4",catalog="2b6af614c6bace99"},
site="https://mosa.center",
home="https://mosa.center/at/defcon",
start="room0",
thumb={w=16,h=24},
rooms={
{
id="room0",
idx=0,
name="Lobby",
m=1.5,
w=24,
h=33,
rects={
{6,18,6,14},
{11,1,4,6},
{2,1,3,6},
{17,11,6,7},
{1,6,17,13}
},
doors={
{to="room1",x=6,y=29},
{to="room12",x=20,y=11},
{to="room4",x=22,y=13},
{to="room8",x=12,y=1},
{to="room10",x=2,y=2}
},
marks={
{kind="vitrine",name="lobby",x=3,y=16,w=1,h=1},
{kind="flapboard",name="lobby",x=8,y=6,w=4,h=1},
{kind="postcards",name="lobby",x=16,y=9,w=1,h=4},
{kind="tickets",name="lobby",x=8,y=12,w=1,h=1}
},
bottles=1,
balloons=8,
goals={
{id="admission",type="visit",name="Admission",text="You entered the building."}
}
},
{
id="room1",
idx=1,
name="Floor 1",
m=3.5,
w=92,
h=10,
rects={
{1,1,90,8}
},
doors={
{to="room0",x=90,y=4},
{to="room2",x=1,y=4},
{to="room5",x=62,y=8},
{to="room6",x=62,y=1},
{to="room7",x=45,y=1},
{to="room9",x=59,y=1}
},
marks={
{kind="entrance",name="eloy",x=21,y=4,w=1,h=1,url="https://mosa.center/at/eloy",label="Dragonmaid Juice by eloy"}
},
bottles=2,
balloons=10,
goals={
{id="threshold",type="visit",name="Threshold",text="You reached the first floor."},
{id="full-floor-clearance",type="pop-all-balloons",name="Full Floor Clearance",text="Every balloon on this floor has been administratively removed."},
{id="uncatalogued-wing",type="discover-room",name="Uncatalogued",text="Somewhere on this floor, the inventory doesn't add up.",room="room9"}
}
},
{
id="room2",
idx=2,
name="Red Room",
m=1.5,
w=28,
h=21,
rects={
{1,1,26,19},
{2,14,8,3}
},
doors={
{to="room1",x=26,y=10},
{to="room3",x=3,y=14}
},
marks={},
bottles=3,
balloons=10,
goals={
{id="second-wing",type="visit",name="Second Wing",text="You found the Red Room."}
}
},
{
id="room3",
idx=3,
name="ZMB Room",
m=4,
w=38,
h=41,
rects={
{36,29,1,3},
{1,1,35,39}
},
doors={
{to="room2",x=36,y=31},
{to="room0",x=27,y=10,warp=true}
},
marks={},
bottles=7,
balloons=10,
goals={
{id="restricted-area",type="visit",name="Restricted Area",text="The ZMB Room has been located."}
}
},
{
id="room4",
idx=4,
name="Community Gallery",
m=1.5,
w=45,
h=39,
rects={
{6,1,38,37},
{1,22,6,8},
{2,21,5,2}
},
doors={
{to="room0",x=1,y=28}
},
marks={
{kind="flapboard",name="cycol",x=32,y=30,w=2,h=2},
{kind="entrance",name="0xvestica",x=18,y=17,w=1,h=1,url="https://mosa.center/at/0xvestica",label="Vestica Bottle by 0xVestica"},
{kind="entrance",name="cycol",x=34,y=25,w=1,h=1,url="https://mosa.center/at/cycol",label="Cycol Gallery @ MOSA"},
{kind="entrance",name="jose",x=24,y=17,w=1,h=1,url="https://mosa.center/at/jose",label="Caffeine Bottle by Jose Narciso"},
{kind="entrance",name="mallow",x=18,y=15,w=1,h=1,url="https://mosa.center/at/mallow",label="Mallow @ MOSA"},
{kind="entrance",name="scum",x=18,y=23,w=1,h=1,url="https://mosa.center/at/scum",label="SCUM bottle by SCUM"},
{kind="entrance",name="solana-spaces",x=11,y=17,w=1,h=1,url="https://mosa.center/at/solana-spaces",label="Solana Spaces @ MOSA"},
{kind="entrance",name="stefan",x=12,y=17,w=1,h=1,url="https://mosa.center/at/stefan",label="Perple Juice by Stefan Grosse Halbuer"},
{kind="entrance",name="tolo",x=24,y=18,w=1,h=1,url="https://mosa.center/at/tolo",label="TOLO @ MOSA"},
{kind="entrance",name="vvv",x=33,y=16,w=1,h=1,url="https://mosa.center/at/vvv",label="vvv.so @ MOSA"}
},
bottles=2,
balloons=10,
goals={
{id="found-community-gallery",type="visit",name="Community Gallery",text="You found the Community Gallery."}
}
},
{
id="room5",
idx=5,
name="Anomalies",
m=1.5,
w=32,
h=28,
rects={
{1,5,30,22},
{13,1,5,5}
},
doors={
{to="room1",x=15,y=1}
},
marks={},
bottles=1,
balloons=10,
goals={
{id="found-anomalies",type="visit",name="Anomalies",text="You found the Anomalies room."}
}
},
{
id="room6",
idx=6,
name="Pepe Sirials",
m=1.5,
w=18,
h=22,
rects={
{6,15,6,6},
{1,1,16,15}
},
doors={
{to="room1",x=8,y=20}
},
marks={},
bottles=2,
balloons=6,
goals={
{id="found-pepe-sirials",type="visit",name="Pepe Sirials",text="You found the Pepe Sirials."}
}
},
{
id="room7",
idx=7,
name="Moar Sirials",
m=1.5,
w=32,
h=33,
rects={
{14,26,5,6},
{1,1,30,26}
},
doors={
{to="room1",x=16,y=31}
},
marks={},
bottles=1,
balloons=10,
goals={
{id="found-moar-sirials",type="visit",name="Moar Sirials",text="You found the Moar Sirials room."}
}
},
{
id="room8",
idx=8,
name="Ballroom",
m=1.5,
w=16,
h=46,
rects={
{1,1,14,37},
{3,37,10,8}
},
doors={
{to="room0",x=8,y=44}
},
marks={},
bottles=2,
balloons=10,
goals={
{id="found-ballroom",type="visit",name="Ballroom",text="You found the Ballroom."}
}
},
{
id="room9",
idx=9,
name="Crocodile Vault",
m=1.5,
w=16,
h=9,
rects={
{10,2,5,6},
{1,1,10,7}
},
doors={
{to="room1",x=12,y=7}
},
marks={},
bottles=1,
balloons=2,
goals={
{id="found-crocodile-vault",type="visit",name="Crocodile Vault",text="You found the Crocodile Vault."}
}
},
{
id="room10",
idx=10,
name="MOSA Permanent",
m=1.5,
w=42,
h=35,
rects={
{1,1,37,33},
{37,13,4,5}
},
doors={
{to="room0",x=40,y=15}
},
marks={},
bottles=1,
balloons=10,
goals={
{id="found-permanent-collection",type="visit",name="Permanent Collection",text="You found the Permanent Collection."}
}
},
{
id="room12",
idx=11,
name="Janitor Room",
m=1.5,
w=9,
h=15,
rects={
{2,7,4,7},
{1,1,7,9}
},
doors={
{to="room0",x=4,y=13}
},
marks={
{kind="vending",name="bp26",x=4,y=3,w=1,h=1}
},
bottles=1,
balloons=2,
link="https://mosa.center/at/bp26",
goals={
{id="found-bp26",type="visit",name="Janitor Room",text="You found the back room."}
}
}
},
collections={
{
slug="bottle",
name="MOSA Bottles",
blurb="Stop littering! Thank you for cleaning up the bottles at MOSA.",
weights={common=1,rare=1,legendary=0.5,mythical=0},
presence={common=1,rare=0.85,legendary=1,mythical=0.05}
}
},
pieces={
{
idx=0,
c="bottle",
id="mosa-bottle",
title="MOSA Bottle",
artist="Sirius Crocodile",
tier="common",
url="https://mosa.center/at/find/bottle/mosa-bottle",
tint=44405,
pal="0000e71b212452aa42287bcfef7c31a6bdd6632c8c519cd31082ad55d699",
rle="D0AeA6AaA6C2I0AbB1A5A7B2I0A9B1A8A7B2I0A9AdA3A5C2I0AfA6B4AfA7A2I0AfA8B3A9A7A2I0AfC8AeA7A2I0A2AaA4AaAeA7A2I0A2AaA8A3AbA7A2I0A2A8B1A3AfA7I0AbB1AdA1A5A2I0A3B1BdA1AcI0AdC1BdAcI0A5AdA3A8A5A4A9I0AaAdA4A5AdA6AfI0AbA4AeAcAdA6AfI0AeA4A6A4AdAaA9I0A9A4BcA3AaA9I0AfB8AcBaA9I0A2A5AdAbA6AaAbI0A2A4AbA9C6I0A2A5AaAbB5AaI0A2A5AdB3AdA3I0A7AcA3BdA8AeE0"
},
{
idx=1,
c="bottle",
id="bottle-rare-sirius",
title="Get Sirius Bottle",
artist="Sirius Crocodile",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-rare-sirius",
tint=65502,
pal="e73cad55ef7da4f3bd75bd3383efacd2e71bd6999492ce37c5d69c50deda",
rle="D0AdA6B5C1I0AdA7AeA5C1I0AaAeA8AdC1I0AaAeA8A5A9B1I0AaAbA4A2AfB1I0AaAbA2A4AfA1A9I0AfAbA2A4AaA1A9I0AfAbA4AbAcA1A9I0A9BeA8AcA1A9I0A1A6A8A6AdA9A1I0AcA8A6B5AdA9I0B8B6A5A6AaI0BeB8B6AaI0AbAeA4A2A5A2AaI0A4AbA4A2A5A2AcI0A2A7A4A2A5A2AcI0AdA7A4A2AdA2AcI0AdA7AbA2AdA4A5I0AcB7AeA4AeA6I0AaB7AeAbA8A5I0AfA7BeA4A8A2I0A9AbA7CeA8I0A1AbA7AeB8A6I0A1AcBeA8A5AaE0"
},
{
idx=2,
c="bottle",
id="bottle-vestica",
title="Vestica Bottle",
artist="Vestica",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-vestica",
tint=63357,
pal="ef5cf77dd69952aa8c7142289cd36b2ce71bad75c61861e7294573ce8c0e",
rle="C0B9A2AaAdAbA1C9F0B9A1AbA4AbA1C9F0B9A1AbA8AaA1C9F0B9A2A3A4AaA1A9A1A9F0A1A3BaAeC7AaA9F0AaA5A7A5A6A8A5A7AeA7F0A8A5AaA5AeA6AfC5F0B4A8AeAfA8BfAeA5F0AeB6A8CcA6A8A7F0A7A8A4A6DcA6A5F0A3B4C6A8A6AdAaF0A2A5A6A4A6A4A8A6A8A3F0A1A3AeA6AdA6AdA4A5A1F0A9A1AaA4AdA8AaA4A5A2F0A9A1A3A8AcA4A5A4AbA1F0B9A1A7AdA6A4A8B9F0B9A1A9C6A5A2A9F0C9A2A5AdAcAaA2A9F0C9A1A3BcA3A1A9F0D9A2A8AcA1B9F0D9A1A7AfC9F0D9A1AbAaC9F0D9A3CbA3A9F0D9DbA3A9C0"
},
{
idx=3,
c="bottle",
id="bottle-stefan",
title="Perple Juice",
artist="Stefan Grosse Halbuer",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-stefan",
tint=46423,
pal="ef5cf79d28e5c618e71b62cc62af082449ec310a4a09184783d1732ea4f5",
rle="D0AfB7AdC5I0AfBcA7A1B5I0A4AcA8A9A1B5I0A4BcA9A5A1A5I0A4A7BeA4A1A5I0A4A6AdA7A4A1A5I0A5BeA7A4A1A5I0A5AeA6A7AfA1A5I0A5A7AaAcAdA2A5I0A1A9BcAaA5A1I0AfBcAaAcA9A5I0A9BcBaA8AfI0AcE8AfI0AeBaA9BeAfI0A6A3A9A7AbA7A4I0AdEbAfI0AfAeAdBfAbAdI0AfA3BbAeAbAdI0A4AbB6AdA6AeI0A4A6AdAeA6AbAeI0A5A3A8AbAeA9AdI0A5A6A3B6AbAeI0A1A9AbA6A3AcAaI0A1AfAaAcAaA9AfE0"
},
{
idx=4,
c="bottle",
id="bottle-jose",
title="Caffeine Bottle",
artist="Jose Narciso",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-jose",
tint=63325,
pal="ef5cef7dbd94e73bdd94ff7de6fab4b0ce5819041275b2e973b05229b5f9",
rle="G4A7B3A7D4A0F4A1A9BdA3A1C4A0F4A1AfAbAaAdA1C4A0F4A1AfAbAaAdB7A1A4A0D2B4A1A9AeAaAeBcA5A4A0C8A5A7A2A1A7AcBaBcAaAfA0AaAeCcA5A4A9AdAeAaAeAaAdA1A0AeCaDcAaAcBaA8B5A0CeCaAeBcBaBdA8A3A0BeA9A3A8AeBaBeB8C3A0AdAeD3A8BaAeE3A0AdAaE3A8BcA8C3A7A0A9AdA8F3A8AdB3A9A1A0A1A2A9C8F3A8A9A4A0B4B1A9A3A8D3B8A7A4A0C4A7A2A3BeAdB3AdA3A1A4A0D4A7AcAeAdB8A3B1B4A0C4A2AdAeAbC8AdD4A0B4A2A8AaAbAdA8A3AdAbA7C4A0A4A1A9AaBbAdA8A3BbA9A1B4A0B4AeAaBbC8BbAfA1B4A0A1A7AdCbC8AdAfD4A0A4A7AdBbAdA8A9A7B1D4A0B4AdBbAfA4A1G4A0"
},
{
idx=5,
c="bottle",
id="sirius-bottle",
title="Sirius Bottle",
artist="Sirius Crocodile",
tier="legendary",
url="https://mosa.center/at/find/bottle/sirius-bottle",
tint=54941,
pal="84757c34ef5c6b92ef5cb32d73d3e71bbdf8cc715ace9452296aa536d6ba",
rle="A0C8AeB1A2A9C3C8B0A8A3A8A2A7A2A7AeAfA9AfA3B8B0A8BeF1A2AeA3B8B0AfA4A7H1AfA3A8B0A9A4A2G1AcA9A5A8B0AeA4A2F1AcA2A1B8B0A1A4B1A2C1AcA6A1A2A9A3B0A2A4B1B6A1A2A6B2A1AeA8B0A7A4C1AbB6AcAdAbA1A2AfB0B4C1AdAbB1BdA1A7A9B0B4B2A1BdB1BdA1A7AaB0AcA4B2A1BdA1A2A4AbA1A7AaB0AcAbC2B4A1B2A1A2A7A6B0AcAbK2AcB0AcAbK2A1B0AeAbA7G2C1A2B0A9AbA7C2C1A7A4BbA7B0A3A2A4A1A2A7AbEdAbA1B0A3AfA7A2AbCdBbA4A7A4AeB0A8A3A9C4E7B4A9B0B8A5AcAbA7D4A7A4A7AfB0B8A3AfA7A4C7C4A1A8B0C8A3A9D4A7A2AeA9A3B0D8A3AeA2AeA9AfA8B3A8A0"
},
{
idx=6,
c="bottle",
id="bottle-scum",
title="SCUM bottle",
artist="SCUM",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-scum",
tint=65535,
pal="ef7cef3cb533c5b5bd74a491acf2cdf65269deb9e6fb940fe73bce588bad",
rle="P0DdA1AcB9AfA1JdA1A3A9AfA3A1B2GdA2AbAeA5B8BeAaAdA1CdA2AbAeA4A7B3A7A8C5A8AbA2AdAeA5A7A3A7A3A7A3A4A3A5A4A3A4AbA4B7AcA6A7A4A5A4A5A7B3A7A6AaAcAfDcA6A7B6A7A6BfA5A2AeFfAcAfCcA3A6AaA2A1B3A5BfAcA6BfAcAeA2A6AeB2B5A1AaBfA7AcAfA4A1AdA6A8A2A1A8A5AdA2AeA6A3AfA6A2AdA2A3A8A1A2AeA3AbAdA1A8A6AcAeB2AeA9AfAeA2AcA9A7B2AaB7AeA2AdAbAfAcAdA2AeAfAaB2AcB9A5AbAdA1B5A1A2AbA7AaA1AaA6AfA7A8A4AaA1A5A7A2AdAbA6AeAdA5A7A6B4A5A4AaA4A3A2AdA2A3B4A7A3A6A5A4B5B4A5AbAdAbA5A3B7A3A6A3A8C4A7A3A5A1A4AfA6A7A6A3A6A7A8A3A4A5A3A6A5AdAbA7AcBfA6A3A4B3A6AcA6A5AbAdB2AeA3AcAfA6A4A7B6A4AbA1A2CdA2A1AdAeC6A8AdA1A2BdP0"
},
{
idx=7,
c="bottle",
id="bottle-silo",
title="Silo has Juice",
artist="Silo",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-silo",
tint=52980,
pal="e71bef5c01a0950a1221d6b874088ca99d5163c53b058cacbe149d2e2283",
rle="D0AdC9C1I0A9A5A3A7A2B1I0AdA5A3AbA2B1I0AdBfAbC1I0A6A8AcAeA6A2A1I0A6A7B4A6A2A1I0A1A7A8A4AdA2A1I0A1A8B4AdA2A1I0A1A7AbAfA9A2A1I0A1AbB3AbA6A2I0A9A3A5AfA3AbA1I0AfA3C5A3A9I0A5E3A9I0A7BbAaA7A8AdI0AcAaA8B4A8AdI0AeAaB8BeAdI0A9AaAcC9AdI0AdAaAcA9AeA8AeI0AdAaAcA9AcA4A9I0A6AaA7D9I0A1B7AcBeA4I0A1B7A8C4I0A1AaAbBaBbI0A2A9AfA5AfAbAdE0"
},
{
idx=8,
c="bottle",
id="bottle-amir-hamz",
title="AmeT Bottle",
artist="AmeT",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-amir-hamz",
tint=50515,
pal="ef5cf77d8942e71b09e659c550e2ce3723098bcc1840ad3389e478c192a7",
rle="D0A8AcA8AcC4I0AcAdA3AaA1B4I0A8B3AfA1B4I0A8BeA6A4A1A4I0A8B5A9A8A1A4I0A8A6BaA8A1A4I0A8CaA8A1A4I0A4C9AcA2A4I0A4AfB7AaA2A4I0A4AfB3AfA4A1I0AcAeA3AdAeAfA4I0AdD3AeAcI0A7CbA7AbAcI0A5AbD5AcI0A9B5B9A5AaI0AaA5B6A9AbAaI0AaAeA3A6A5A6AcI0AcA7A3A6A5A7AaI0AcA7AeA6A5AbA6I0A8A7A3A6B5A9I0A4A6AeA3C9I0A4AaAdAfCaI0A4AfAdBfBdI0A1AcAdA3AdAfA8E0"
},
{
idx=9,
c="bottle",
id="bottle-iblolurker",
title="Ribbit Bottle",
artist="IblisX",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-iblolurker",
tint=48628,
pal="ef5c09e1f77ce71b3a88335300e07ac7b3c983ee92a461e3d699b5f7bd31",
rle="D0CdAeC4I0AeB2A5A1B4I0AeA2A7A5A1B4I0AeB2A5AdA1A4I0AdC6AdA1A4I0AdA5B6AeA3A4I0A4C5AeA3A4I0A4C6AeA1A4I0A4A5B2AaA3A4I0A1A5A7A2A5AdA1I0AfD2A5A4I0A5D2A7AfI0A2E7AfI0A8CcA8AbAfI0A9AbCaA9AfI0A9A8A2A5AaA8AfI0AfA8B5BaAfI0AfAbAaB5AaA9I0AeAbA8D9I0AdEcA8I0A4AbAcB8AbA9I0A4A9AbD9I0A1A8CcB2I0A3AfC2A5AeE0"
},
{
idx=10,
c="bottle",
id="bottle-thehome113-a",
title="DOM Bottle",
artist="DOM",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-thehome113-a",
tint=44405,
pal="2104ef3c52aa422873ae00003186f77d10a294b2ad54632c8430ce58e71b",
rle="D0AaA1A7A4AfA2AfI0AaB6A3A2BfI0AeB9A4A2BfI0AeA1A7A3AfA2AfI0AeB3AaAeA2AfI0AeB1A7AbA8AfI0AeB3A9AbA8AfI0AfAdAaA5AbA8AfI0AfAcB7AdA8AfI0A2A4A6A1A4AfA2I0AbB1A4A7A4AfI0A4A9A1A7A4A6AaI0A1C6B9AbI0A5A4A3AcA5AaAeI0C5AcAdA5AbI0A3A6A9A6A3A5AeI0A5A6A1A9B1AdI0AbA4A1B7AcAaI0AeA4AcA5A3AdAaI0AeA7A3A7C5I0AeA3B4A3A1A5I0AfAcAdB3AdAaI0A2A3A4A5AcA4A7I0A8AaA9A6A9A7AbE0"
},
{
idx=11,
c="bottle",
id="bottle-jigsawgeneral",
title="Pieces",
artist="Jigsaw",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-jigsawgeneral",
tint=44373,
pal="00204228e71b31a6632c2104ef7d52aa8c509cd3deda73aebdf7ce79ad55",
rle="D0AaA4A6A2C3I0A9B1A2A7B3I0AdB1A4A7B3I0AdB1A6AbB3I0AeB4A2AdA7A3I0AeA2A8A6AfA7A3I0AbA2A4A2AfA7A3I0AbA5A2A4AaA7A3I0A3A2A6A1AcA7A3I0A3A4B1A6AbA7I0A9D1A4A3I0A6E1AaI0F1AaI0A5A8B6A5AfAdI0AcAfA5A6A5A9AaI0BcA9A4B5A9I0AaA8A4A9AeA9A5I0AeA2A4A5AdAaAcI0AeA5A6A2AcA2AfI0AeA5A4A2B8A9I0AbA2AcAdA9A4A8I0AbB8BfA4A6I0A3A2A6A8A2B6I0A7AaA6B1A4AfE0"
},
{
idx=12,
c="bottle",
id="bottle-aleciatv1-a",
title="COSMIC drink",
artist="Cosmic",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-aleciatv1-a",
tint=58872,
pal="e73bef5c3a7499e6ba889aa7cb8ccd9579e452af72a9ca677cf7d6b9942d",
rle="D0AdA3BdC1I0A8A9A4A7C1I0AeA5AcA7C1I0A8A4A6AfAeB1I0AeBaA3AeA2A1I0AeBbAfA8A2A1I0A1BbAfA8A2A1I0A1BaA3AdA2A1I0A1CbA8A2A1I0A1A7AcB7B1I0A8B5C7A1I0A7B5B7AcA8I0B4C5A4A8I0AbA9A4A6AbA3AdI0AfA9B6AaA3AdI0AfA9B6B3AdI0AfA9A6AbB3AdI0A8A9B6AaA3AdI0A8A9A6AbAaA3AdI0AeA9A4AbB3AdI0AeA9A4AbB3AfI0A1AbB9A3AaAfI0A1A6B9AaAbA5I0A2A8B4A5A7A8E0"
},
{
idx=13,
c="bottle",
id="bottle-scubasteveart",
title="Scuba's Goblin Juice",
artist="Scuba",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-scubasteveart",
tint=48532,
pal="0020e71bef7cd69939c629247b4aacf172e7bdd583cd526762eb944fa513",
rle="D0A8B9A7C2I0AeB1AcA3B2I0AaB1A5A3B2I0AaB6AcC2I0A4B7AeA4B2I0A4AcA9AbA4B2I0A4AdAbAdAaA3A2I0A2CdAfA3A2I0A2AcB6AeA3A2I0A2A5B1A6A4A3I0AeD1A5A2I0A6E1AfI0F1AfI0A7A5AcAdAeA8AaI0AbB5AcAeA8AaI0AeC6AdAbA8I0AeA6AcB5AbAfI0AfB9AbA5A7AfI0AaBcA7A9A7AeI0A4B5AcA9AbAeI0A4C9A7AeAaI0A2AbA9A7AbB8I0A2AdA5BdA5A6I0A3AfA6B1A5AfE0"
},
{
idx=14,
c="bottle",
id="bottle-pixelsushirobot",
title="100% Sushi",
artist="PixelSushiRobot",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-pixelsushirobot",
tint=65534,
pal="f75b8c71f77b9cf3deb8ef7ddefa2944bdf6ce37b595ef1ae73bd6995b4b",
rle="D0AaBbA9CdI0AeA5BcCdI0AdB3A1CdI0A7C5CdI0AeA2BbA7BdI0AeA4AbA9AeBdI0A7A4AbA9AeBdI0A7B4AbAeBdI0AdBaA5A7BdI0AdA1B3AcBdI0A7AcA1A3A1AcAdI0B3AcC5AdI0A2CfB8A4I0F8A2I0A2B8CfA2I0A2EfA4I0A9AfC2A4A2I0AaBfC4A2I0AaB2C4AbI0AeC2B4AbI0A7A4B2B4AbI0A7B4B2A4AbI0AdB9A4AbAaA5I0BdD1AdE0"
},
{
idx=15,
c="bottle",
id="bottle-basketbskt",
title="Absolutely not weird refreshing drink",
artist="Bskt",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-basketbskt",
tint=52759,
pal="e71bef5c4207deda5b49ce58c617b5954ae79bcf72ed210383ae7a48a4b2",
rle="D0A6A8A7A8C1I0A8B9AdA2B1I0A6B9AdA2B1I0A7B3A9A4A2A1I0A7A3BbA6A2A1I0A6AbAdAaA6A2A1I0A4AbAdAaA7A2A1I0A4CbA8A2A1I0A1A5B3AfA2A1I0A1AdB9A5A4A2I0A8B9A5A9AdA1I0A5D9A3A8I0A3EcAfI0A3CcB3A8I0AdA3CbAdA8I0AaBeAbAdAaAfI0AfBeAbBaAfI0A8A3AbBdAaAfI0A7AeAbCdAfI0A6BeBbAdAfI0A4BeAbAeAaAfI0A4FbI0A1A5AcC3A9I0A2A8A5A9A5AdA7E0"
},
{
idx=16,
c="bottle",
id="bottle-papabearded",
title="Papa Bearded Bottle",
artist="Papa Bearded",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-papabearded",
tint=50871,
pal="ef5cf77d4bac638ac657e71b6ae5ff7d84f26388842ca532226542e75c4f",
rle="D0A5AbBcC6I0AcAdAeAcA1B6I0A5AaAeAbA1B6I0A5A4AfA3A6A1A6I0A5AaA9AaA5A1A6I0A6AeAaAeA5A1A6I0A6AbAeAdAcA2A6I0A6AfAaAeAcA2A6I0A6A3AaAeAcA2A6I0A1A3AdA3AbA6A1I0A5AaB9A3AbA6I0BaB9A4A7A5I0A3CdAaA7AcI0A4B7AdAaAeA9I0A4AdA7AdBeAcI0AcAeBbA4AbAcI0A9AdAbAaA3B9I0AcAdAaA7A4A9A5I0A5A4BdA4A9AcI0A5AaAdAeA3A4AbI0A6A4AdAbAfAdAfI0A6A3A4AbB3A9I0A1A3AdA4AbAdA3I0A1A5A4A7AbAfA5E0"
},
{
idx=17,
c="bottle",
id="bottle-officialfadd",
title="DRAGON SPIT",
artist="FADD",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-officialfadd",
tint=50741,
pal="e73bef7ca4cb00201922defa1840528931a4b594d60d10a17beebd8ed677",
rle="D0AaA9A5A8C1I0AaB3AeC1I0A6CbC1I0AfC3A6B1I0AaB4A9AfA2A1I0AfA4A5A8AaA2A1I0AfAcB8AaA2A1I0A6C8AaA2A1I0A1AeB3AaA2A1I0A1CbAeA6A1I0AfAeCbAeA6I0AeBbBeA3AfI0A3A8D9AaI0A8A7BcB5AdI0AdA7BcB5AdI0A3A9A5AcA9A5AdI0AaA5AcA5A9A5AdI0AaA8A9AcA5A9A8I0AfA8A5AcB9A8I0A6A9A4B9A5A8I0A6AdC9AcA9I0A6AdA8A5A8AdA8I0A1AeCdA3AeI0A1AfDbAfE0"
},
{
idx=18,
c="bottle",
id="bottle-the-ao8-a",
title="Cell-A-Beer",
artist="AlphaOmega8",
tier="common",
url="https://mosa.center/at/find/bottle/bottle-the-ao8-a",
tint=52791,
pal="ef5cef7d106120c2dedac63708208c916aeaa513b5b541a68beee71b742f",
rle="D0A6CbCeI0AaA3A7A9A2BeI0A6B7AcA1BeI0A6A4AcA9A5A1AeI0A6A9AdAaA5A1AeI0A5A9AfA8A6A1AeI0A5A9AfAdA6A2AeI0A5AfAdAfAbA1AeI0AeA9BcA8A2AeI0A1AcA7A3AcA5A1I0AaD4A9AeI0AcA3C4A7AaI0A4B7A3B4AaI0A9AcB9BdA6I0A8AdB8AaA8AbI0A8A9A8AfA8AfAbI0AaA9CfA8AbI0AbA9AdA8AfA8AaI0A6A9A8BfA8AaI0A6A9CfA8AaI0A5B9AdA8AfAaI0A5AdAfBdA8AdI0AeA9AcB9BcI0A2AaA4A3A4AcAbE0"
},
{
idx=19,
c="bottle",
id="bottle-duckzzyog",
title="Die Muschimeister",
artist="Duckzzy",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-duckzzyog",
tint=54676,
pal="ef5cef7d10002020000049a583cda4d172a8cdf6de99b309e71b30e3ccf1",
rle="D0AfCcCdI0A8B4A9A2BdI0AaA4A3A6A1BdI0AaB4A6AbA1AdI0AaCcAbA1AdI0AbCcAaA1AdI0AbA9B8AbA1AdI0AbA7B8AaA1AdI0AdA9AeA4A7A2AdI0A1A6B3A6AbA1I0A8A3A4AeA3A6AdI0AeD4A5A8I0A4B3C5A8I0A9AeB6B9AfI0AcA6DcAfI0AcA9DcAfI0A8A6A7A9BcAfI0AaAeA6B7AcAfI0AaB7B9AcAfI0AbB7B9AcAfI0AdA9A7A8CcI0AdB7B8BcI0AdA9A6B9BeI0A2A8AeB4A6A8E0"
},
{
idx=20,
c="bottle",
id="bottle-glorp-goob",
title="GoobFellaSchizoCollage",
artist="Goob",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-glorp-goob",
tint=46680,
pal="ef3c02479d13f77de71b84510aeaad75438d22aa2125840a5268d6b9c617",
rle="D0AfA3B8C5I0A8B7A9A1B5I0AfA7A2A9A1B5I0AfAaB9A5A1A5I0AeA3A8AfAeA1A5I0AeB3A8AeA1A5I0A5A3A8A3AeA1A5I0A5A3B8AfA1A5I0A5A6B9A3A4A5I0A5A9B2AaAeA1I0A3A2B7A2A9A5I0AaD7A2A8I0E2AbA3I0AdAbBaAdAbA3I0A9EbA6I0A6AbBdBcA3I0A6AdCcAdA3I0A6AdDcA3I0A8AbBdAcAdAcI0AfCbAdAbAdI0AeBdAbBdA3I0AeAdA6A3A8AfA8I0A5A9AdB6B9I0A1A8AaB7A9A8E0"
},
{
idx=21,
c="bottle",
id="bottle-ponderman",
title="Pondering Juice",
artist="Ponderman",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-ponderman",
tint=57055,
pal="ef5cef7d7b349556e71b51b272547d16bdf95a708b96ce7a7c51ad5684b4",
rle="D0AeAaB3A1B5I0AeA6A7AbA1B5I0AcB7AbA1B5I0AcA7A3AbA5A1A5I0AcAdB4AcA1A5I0AcAfAeA4AcA1A5I0A5AfA4AeAcA1A5I0A5AfA8A4A9A1A5I0A5AbB3AeA1A5I0A5AbB7A3A5A1I0AeD7AbA5I0A3D7A6A9I0A7E6AeI0AdAaA3BfA8A9I0A4AdA8B4A8A9I0A4AdAfB4A8A9I0AeAdAfA4BdA4I0A9AaAdA8BdA4I0A9BaA3B8A4I0AcCaAfA4AeI0A5CaAfBeI0A5AaA6AaAfA4AfI0A1A3A6AaA3AbA3I0A1A9A3B7AbA9E0"
},
{
idx=22,
c="bottle",
id="bottle-agniis-eg",
title="Mom I'm Bottle",
artist="evErgrace",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-agniis-eg",
tint=44404,
pal="0000e73bef5c31a618e3946f4a68deda29450861a513bdf67bacce586308",
rle="D0AcCbC2I0AbAaA1A7A3B2I0AcB1A4A3B2I0AcBaA9A8B2I0AeA4A9AdA8B2I0AeA7A4AfAeA3A2I0A8B7AdAcA3A2I0A8AfBdAcA3A2I0A2A7A5AaA6A3A2I0A2A4B1A9A8A3I0A6B1AaA1A4A8I0A5E1AbI0AaE1AbI0A7D4A9AbI0AdA5A4C7AbI0A6A4A5A4A7AfAbI0AbBfA4AfAdAbI0AbA7BfAdB6I0AcDfAdAbI0AeCfBdA6I0A8B7CdAbI0A8B7AdA7B6I0A2A7A9B7B9I0A3AbA5A1AaA4AbE0"
},
{
idx=23,
c="bottle",
id="bottle-itsbubblezzz",
title="Bottle by Bubblezzz",
artist="BubbleZzz",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-itsbubblezzz",
tint=52757,
pal="0020e73bef5cbdb69491a5135aca9c6ddedace5883459c067bce31649c29",
rle="D0AaB4A6C2I0A6B1A7A3B2I0A4B1AeA3B2I0A4B1AeA9B2I0AaAbBcAaA3A2I0AaAbAfA8AaA3A2I0A9AdB5AaA3A2I0A9A5B6A4B2I0A2A7BeAdA3A2I0A2AeB1AeA9A3I0A5D1AeA9I0AeE1A6I0F1A6I0AdC7AdA5AaI0A5AdA5B6A5A4I0A6AdA5AdA5A8A6I0A4BdA7A8AcA6I0A4BdAbBfA8I0A4A7BbAcAfA8I0AaAbA8AfAcB8I0A9BbAcA8BfI0A9BbCcAfI0A2A7AeBbBeI0A3A6AeB1AeA6E0"
},
{
idx=24,
c="bottle",
id="bottle-degenghosty",
title="Ghosty's Margaweeda",
artist="Degen Ghosty",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-degenghosty",
tint=48666,
pal="e73bf77c4411deda394b598d5d557db6be58ff7d18a8ad3594514acb922e",
rle="D0AdB5AeC1I0AcB3A8C1I0A4B7A8C1I0A9C3A4B1I0A9B5A6A9A2A1I0A9B6A5AcA2A1I0A4B5AeAcA2A1I0A4A5AbAeAdA2A1I0A1C3A8A2A1I0A1A8C7A4A1I0A9D7A8A1I0E7A3A9I0A3A5BbAeAbAcI0A5CbA5AbAdI0A6AbA5A6A5A6AcI0AdAbA5B6AfAcI0AdBeA5AfAdAcI0AcAeAdA5AfAdAcI0A9BeA6AfAdAcI0A9B5BfAdAcI0A4B5A6BfA6I0A4AeA5A6AfB6I0A1A3A5CeA7I0A1A9C7A8A9E0"
},
{
idx=25,
c="bottle",
id="bottle-nooffswitch",
title="Elemental",
artist="NoOffSwitch",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-nooffswitch",
tint=46453,
pal="20e3e73b3186ef7c5a8a0862deba9b8d4a289cd2734cb554294541c7c638",
rle="D0AcC8C2I0AaA6A1AbA4B2I0AfBdA5C2I0AfAdA3A5A7B2I0AfA5BbAfA4A2I0A7CbAfA4A2I0A7CbAcA4A2I0A7C5AaA4A2I0A2A5A1AdAaA4A2I0A2A5A1AeA5A7A4I0AcA3AeA5AeAbA2I0A5AdA3B9AdAcI0AdA1BdA3A1AaI0A9A6A1BdA1AaI0AbAdD3AaI0AbA1C3AdA8I0AaA1AdBeA5AaI0AaAeAbB8AaAcI0AcA1A5A8CaI0AfB3AeA9AbA8I0A7AeA5AbA5AdAbI0A7A3AdBeA6A9I0A2AeA6A1AdA6A3I0A4AcAdA1AdA5AcE0"
},
{
idx=26,
c="bottle",
id="bottle-plumpfun",
title="Plumpa Oil",
artist="Plumpa",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-plumpfun",
tint=48533,
pal="0000ef5cef7d31856b6d8c2fce588b6a52aa18a2e71b630ba4f2b5b55a47",
rle="D0A7CeCbI0AdAaA1A9A3BbI0AeB1A4A2BbI0AeBaA4AbA2AbI0A7A9B5A7A2AbI0A7AcB8A7A3AbI0AbC6A7A2AbI0AbAcAfAcA7A2AbI0AbAfBaA6A3AbI0A2A4B1A4AbA2I0A6D1A4AbI0AaE1AdI0AaE1AdI0AfAaB4A9AcAeI0A5AaA4AcA5AcAdI0A6A4AcA6AcA9AdI0A6A5B6A5AcAdI0AdA9A5A6B8AdI0AeA9A5A6B8A6I0A7A9A5A6B8A6I0A7AcB5B8A6I0AbA8AcC8A6I0A2AfA4BfB4I0A3AdAaA1AaA4AdE0"
},
{
idx=27,
c="bottle",
id="bottle-piskim0-a",
title="Love Lane",
artist="Piskimo",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-piskim0-a",
tint=65503,
pal="9cf3bdd6ce59ad75ef5c8430ef7d73aedefa630cc618d6ba9492e73b52aa",
rle="D0AbA4AbA4CeI0AbAdA4AbCeI0AcA4A2A3CeI0AcA1A2AbCeI0AcA1B4AcA5AeI0AcA8AdA1A3A5AeI0A9AaB6AbA5AeI0A9A6AdA1A3A5AeI0AeB4A2AcA5AeI0AeA2A4AbA3BeI0AcA2CbA3AeI0C2CbA9I0A1A4C2A4A3I0A6A8BdB1A3I0A1A6A1C4AbI0A4A6A1B4A1A2I0A2A6AdA1BdA2I0AbB6B8AaA4I0AbA8A1A8BfA1I0AcB8A1BaA1I0A9B8A6AdB1I0A9A6B8CdI0A5AdA8A6BdA4I0A5A3B1A4AbAcE0"
},
{
idx=28,
c="bottle",
id="bottle-grybnn",
title="SKYWALKIN'",
artist="GREY",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-grybnn",
tint=56890,
pal="e73bef7cb4cf3008dedaa4d383cf59ad9c6f408a9452b555ce3772ed9c0c",
rle="D0AcAfB3C1I0AcBaAeA2B1I0AdAaA4A8A2B1I0AdBaA8A5B1I0AdA7A9A6A5B1I0A5AfA9A3AdB1I0A5AfA9A3AdA2A1I0A5B9A6AdA2A1I0A1AeA8AaAbA2A1I0A1A8A4AaA8A5A2I0A6A4BaA4A8A1I0A8DaA4AcI0AaE4AcI0AeA8BeB7AdI0AbAeA7CbAdI0A6AeA7B9A3AcI0A6AeB9A3A9AcI0AcAeA7A9A3A9A6I0AdBfA9A3AbA6I0AdAeBfA9AbA6I0A5AeBfA9AbA6I0A5A9AfB3AbA7I0A1BeAfAeB8I0A2AcA8BaA8AcE0"
},
{
idx=29,
c="bottle",
id="bottle-lampwrecked-b",
title="saltwater",
artist="lampwrecked",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-lampwrecked-b",
tint=63389,
pal="bdd7ce58ef3cad75ef5c945073aea514e71b73f0845152aa94926b2bd6ba",
rle="D0A2C1C9I0A2AdA4A1A3B9I0AfA4A1A2A3B9I0AfA8B4A9A3A9I0A2AaAbAaA2A5A9I0AfA7AaAbA2A5A9I0AfAaAbAdA2A5A9I0AfAeB7A4A5A9I0A9B6A8A2A3A9I0A3B1B2A9A3I0AfB1C2A9I0A4C1A2A1AfI0B8D1AfI0AdAbCdAbA1I0AdAaBdAbAaA4I0A8A7DbA4I0A4AeBaB7A8I0A4AcCaAcAbI0A1BcAaAbAaAbI0A2BcA7AaA7AdI0AfAeA7B6B7I0A9AeAcAeA6A7A6I0A3AdAeA7A6AdA1I0A3A2B8A4A2AfE0"
},
{
idx=30,
c="bottle",
id="bottle-siriuscrocodile",
title="Rumble Bottle",
artist="Croc Junior",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-siriuscrocodile",
tint=40477,
pal="e71b0235f77c09ae3251d6ba4b128cd485d76c16ff7d086343b31a92add8",
rle="D0AfCaC1I0AfB5AaA3B1I0A6B5A7C1I0AfA5AeAdC1I0AfB2AdA6B1I0A6A2BeAfA3A1I0A6B4AeA9A3A1I0A6AdA5A4A9A3A1I0A1AaB5A8A3A1I0A1A7B5A7A6A3I0AfB5A7A5A7A1I0A7D5A4AfI0A5A4DcA8I0A4EcA8I0AdC4AdA9AfI0AaA2BeAdA9AfI0AaA2A4A2AdB9I0A9A4B2AdB9I0AfC2AdB9I0AfC2AdB9I0A6C2AeB9I0A1AeB4AeB9I0A1A7B4AeAdA7I0A3AfA7A5B7AfE0"
},
{
idx=31,
c="bottle",
id="bottle-createdby-imrie",
title="Mana Juice",
artist="Created by Imrie",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-createdby-imrie",
tint=44311,
pal="e71bef7c004a08acdeba52050026424e7a8b618a2923a4f57b71296bc5f8",
rle="D0AcA8BdC1I0AcB3A8A2B1I0AfA4A3A8A2B1I0AfB4A8A5B1I0AfAaB9A5A2A1I0A5C9AfA2A1I0A5AaA9AaAfA2A1I0A5CaAcA2A1I0A1A8B3AdA2A1I0A1A8A3A4AeA5A2I0AcA3B4A3A8A1I0AeA3C4A3AcI0A4E7AcI0A8CeAaA6AcI0A9CbB9AcI0AcB8A9AaA9AcI0AcA8C9AaAdI0AcBaBdA9AdI0AfA6BaA9A6A9I0AfE6A9I0A5A6BbA6AaA9I0A5A6AbC6A9I0A1A8A7AbA6A7AeI0A2AcAeB4A8AcE0"
},
{
idx=32,
c="bottle",
id="bottle-barokahdimlmhr",
title="Pure Water from the Mushroom Mountains",
artist="Barokah",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-barokahdimlmhr",
tint=44244,
pal="0000ef5cf77de71b10432b843866c5b82986c4789cd3d69a6a518b32618b",
rle="D0A8CaC4I0AbA5A1AfA3B4I0A8B1A9A2B4I0A8B5A9A4A2A4I0A8CdAcA2A4I0AcCdA8A2A4I0AcAdBeA8A2A4I0A4CfAbA3A4I0A4A9B1AeA3A4I0A2A9B1A9AcA2I0AbD1A9A4I0A5E1AbI0A5E1AbI0A9A5D7AbI0AfA5D7AeI0AeA7A5B9A7AeI0AeC7AfAdAaI0AbBfAdBeAbI0A8A7AfBdB6I0A8BfD6I0AcAfA9D6I0A4BfD6I0A4AfA7AfA6B9I0A3AbA5A1A5A9AbE0"
},
{
idx=33,
c="bottle",
id="bottle-boin-art",
title="50c Beers",
artist="Boin",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-boin-art",
tint=40210,
pal="e71bef5c22624a88c61720e418a331a90021632c0a00008031454a6d94d2",
rle="D0AfCaC1I0AfBbAaA2B1I0A5BbA4A2B1I0A5B3A4A1A2A1I0A5BdA4A5A2A1I0A5AdA4AaA5A2A1I0A1B4AdAfA2A1I0A1A4A6AdAfA2A1I0A1AaB3AfA2A1I0A2A4BbA3A1A2I0AfBbA3AbA4A1I0A3BbB3AbAfI0AbEcAfI0A4A7A6BdA7AfI0AaA7B6AdA7AaI0AaA9B7AdA7AaI0AfA9A7A6AdA6AaI0AfA9A8AeBdAaI0AfA9A8AeBdA4I0A5A9A8AeA8A6A4I0A1A6A8BeAdA8I0A1C8CdI0A2A4A6BdB3I0A2AfC3A4A5E0"
},
{
idx=34,
c="bottle",
id="bottle-whimsiverse",
title="Rooty Tooty Whimsiverse",
artist="Whimsiverse",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-whimsiverse",
tint=56861,
pal="e73b9b7aef7c9c13a41adedbce3a6a6b52309339b57782f7394b7310ac0d",
rle="D0AbAcA5A2C1I0AbAcAaA5C1I0A6A2AaA5C1I0A7CcA6B1I0A7AdA9AeA7A3A1I0A7A9AdA9AbA3A1I0A6B9AdAbA3A1I0A6BdA9AbA3A1I0A1AeA9AcAbA3A1I0A1A5C2A6A1I0AbAcAaA2AaA5A1I0B2CaAcA7I0AcB9CdAbI0AeA8DdAbI0AfA8B9AeA9AbI0AfAdA9CeA4I0A4BdA9AfAeA4I0AbAdA8CfA4I0AbBdCfA4I0A7B8CfAeI0A6AfA8AeCfI0A6AfA8A9CfI0A1A4AeA9AeA4AaI0A1A7A2AaA2A5A7E0"
},
{
idx=35,
c="bottle",
id="bottle-wwfkilla",
title="Neighborino",
artist="wwfkilla",
tier="common",
url="https://mosa.center/at/find/bottle/bottle-wwfkilla",
tint=61175,
pal="e73bef5ddc73a469de58c451d4d4be15846d4b856b895a04a552a44ededa",
rle="D0AdBaAbC1I0A8AeA6A7C1I0AfB3A7C1I0A5CeAfB1I0A8CaA8A2A1I0A5CaA8A2A1I0AfCaA8A2A1I0AfCaAdA2A1I0A1AeA9AeA8A2A1I0A1A7B3A7AfA1I0A5B6A7A6A7A1I0B3D6A5I0AbAcAbCcAdI0BaBbB9AdI0A9AaA9AdBeA8I0A9AaAbCcAdI0AdAbAcAbB4AdI0AdAbBcBbAdI0A8AbBcAbAcAdI0A8BbB4AcAdI0A5AaA9B4AbAeI0AfBaA4C9I0A1AeAbA9BeA6I0A1A5A7A6A3A7A5E0"
},
{
idx=36,
c="bottle",
id="eloy-bottle",
title="Dragonmaid Juice",
artist="eloy",
tier="mythical",
url="https://mosa.center/at/find/bottle/eloy-bottle",
tint=54904,
pal="e71bef5c83cd62ea6b2b5a68736ca51341e67b092944bdb58c2f9cb1ce58",
rle="B0B1AfA8AeBdAfA2C1D0A1A2AeA9A4B5AcA2C1D0A1A2AcA6A7A3AdAcA2C1D0A1A2A8A4C5A3D1D0A1A2AeBbC6D1D0A1A2A8A9A6BaA6AfA2B1D0A1A2AcAbC6AaAfA2B1D0A1A2AfA9B6B9AcA2B1D0A1A2AfA6BaA6A5AcC1D0B1AcAdAeB8DcA2D0AfAeF8AeAdAeA1D0AdA7C3EdA3AfD0AdB6A4B5C7B3AfD0AcC6A4A5A7B3AdA3AfD0AfB4A5B7C3B5AcD0AfA4A6A4B7B3C5AcD0A1A6AbA9A5A6A7A4A5B4AcD0A2A4BbB9A4A6A7A5A4A8D0A2A3BbB9A4A6B7A6A8D0A2AeA6A9AbB9AbA4A5A4A8D0A2AeA6A4A6B9A6B3AdAeD0A2AeA6A5A7A4B6BdA3AeD0B1AdA6A4D7A4AdA1D0C1AcA7A6A9A6A7A8B1B0"
},
{
idx=37,
c="bottle",
id="skull-bottle",
title="SKULL POTION",
artist="Skull Shaman",
tier="rare",
url="https://mosa.center/at/find/bottle/skull-bottle",
tint=65368,
pal="e73bef5cbccbbbadc4cfbc2bcd90e6fabd0ad5f59bc7ac69cbf1de78ab4a",
rle="D0AaCdC1I0AaAbAcA7A2B1I0AeB4A7C1I0AeAfA4AdA8B1I0AeAfA6A3AeA2A1I0AeAfA4A6AeA2A1I0A8AfB4AaA2A1I0A8B4A9AaA2A1I0A1A4AcA9AaA2A1I0A1A5A9B7A8A1I0AaA9A5C7A1I0A5BdAaA7A4AeI0BfA9C3AaI0A4AcA9A4A6A9AaI0A5AbA3A4B3AaI0A5AfA3A6B3A7I0A7AbB6A3A6A7I0AaAbA6B4A3A7I0AeAbAcA9A3A6A5I0AeAbAcC4A5I0A8AcAfA4A6A9A5I0A8AcAfB6A3A5I0A1A3AbA4A6A4A5I0A2AaBcA6A5AeE0"
},
{
idx=38,
c="bottle",
id="bottle-simulations",
title="Simulation's Mixed Matter",
artist="Simulations",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-simulations",
tint=57117,
pal="e71bce3ddedbef5c31e8b5d6d65ece794aea9cd4b5ba4a6d8c516b2c738f",
rle="D0A8A6A8A6C1I0A3AbB2C1I0A1C7C1I0A3AbA6AaA3B1I0A8A5B9A6A4A1I0A8BcA9A6A4A1I0A3BcAeA6A4A1I0A3AcA5AeA6A4A1I0A1C6A8B1I0A1C7A2B1I0A3B2A7B2A1I0A2A7C2AbA3I0AaAfAeA5AfAcA6I0AcA5AeAcAfAeA6I0AfA5AcC9AaI0AdA5A9A5B9AaI0A6AeAdBfBaI0A6AfAdAfBaAdI0A6A9AeAfAaBdI0A8AfAdAeA9A5AeI0A8C5A9A5A9I0A3E5A9I0A1AdC5AeAbI0A1A4A7A2B7A1E0"
},
{
idx=39,
c="bottle",
id="bottle-tornado-ilus",
title="Fresh and sticky",
artist="Tornado Rodriguez",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-tornado-ilus",
tint=46806,
pal="ef3cf75c0aa6e71b028333cb84ef9db30201be56ce986c685c4d4b6c22e8",
rle="D0AaA7A8A7C4I0A8B3AdA1B4I0AbB3A6A1B4I0AaA3AfA6A4A1A4I0AbAcBdAbA1A4I0AbC6AaA2A4I0A4AcA6AdAaA2A4I0A4BeAdA8A2A4I0A4AeB3A7A2A4I0A1A6B3AfA4A1I0A8B3AfA3A6A4I0AfD3A9A8I0C5C9A8I0AcAfDcAaI0A7CcB7A8I0A7AfA6AeA6AdA8I0A8AfA6A7AdAeA7I0A8AfA6B7AfA7I0AaAfA6A7A8AdA7I0AbAfA6AcA7B8I0A4AcA6AcC7I0A4BcC7AdI0A1AeAfBeBfI0A2A8AfA3AfA6AaE0"
},
{
idx=40,
c="bottle",
id="mosanade",
title="MOSAnade",
artist="Sirius Crocodile",
tier="rare",
url="https://mosa.center/at/find/bottle/mosanade",
tint=57151,
pal="ef5c8c53a515cf9e73706310a6197db89bd3e71b6c3383925b58c67a4a2d",
rle="C0AaA7A2A6BdAeA1BaF0A1A2BfBdA7A1BaF0A1A2AfA6BdA7A1BaF0A1A3AfA6AeA4DaF0A1A7AfA5C4CaF0AaA3A6A2D4BaF0AeAbA6AbBeA7A8AeA1F0A7C8E7AaF0B8A7F8AaF0FbC2AaF0A2C5AcC9A2AaF0A3B5DcA9A2AeF0A3A6A5EcA5A3F0A7AfA5C2B9AcAeF0A7AfA5AcA6AcA2B9AeF0AeA6A5A2AfA5A3A2A5A3F0AeA6A5A2A5A2B3AcA3F0AaB6A2BcB3A2A3F0AaA5AfA6CcA3B2F0AaA2B5CcA3B2F0A1A2A5C2B3A2A3F0A1A3A6EbA8A7F0A1AeD8A7B8AeF0AaA1AaB8AeAaBeAaC0"
}
}
}
end
package.preload["build_info"] = function(...)
return { version = "0.1.0", mosa = "f1d804c59a35", data = "38243503a8b7a901", repo = "" }
end
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
for name in pairs(package.preload) do package.preload[name] = nil end
local DATA_SCHEMA = 1
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
local codes, developing = {}, {}
local function code_for(url)
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
local Title, Lanyard, Game, Pause, Card, Plaque, Code, Record, Map, About
local function menu(items, x, y, sel, step)
step = step or 18
for i, item in ipairs(items) do
local label = type(item[1]) == "function" and item[1]() or item[1]
local yy = y + (i - 1) * step
if i == sel then
g.fill_rect(x - 10, yy, 4, 8, ui.ACCENT)
ui.tracked(label, x, yy, ui.INK, 1, 2)
else
ui.tracked(label, x, yy, ui.MUTED, 1, 2)
end
end
end
local function menu_button(self, key)
if key == "up" then self.sel = (self.sel - 2) % #self.items + 1
elseif key == "down" then self.sel = self.sel % #self.items + 1
elseif key == "a" then self.items[self.sel][2]() end
end
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
ui.tracked("MUSEUM OF SIRIUS ART", 18, 18, ui.MUTED, 1, 2)
g.text("M.O.S.A.", 16, 36, ui.INK, 4)
ui.tracked("NIGHT SHIFT", 18, 76, ui.INK, 2, 3)
menu(self.items, 28, 120, self.sel)
local p = DATA.pieces[self.art]
g.fill_rect(214, 18, 92, 156, g.color(20, 20, 21))
ui.thumb(p, 228, 32, 4)
ui.tracked_center(ui.TIER[p.tier] or "", 260, 134, ui.MUTED, 1, 1)
g.text_center(ui.fit(p.title, 90), 260, 148, ui.INK)
g.text_center(ui.fit(p.artist, 90), 260, 160, ui.MUTED)
g.text("v" .. BUILD.version, 18, 226, ui.DIM)
local found = record.found_count()
if found > 0 then g.text_right(found .. " / " .. #DATA.pieces .. " IN YOUR RECORD", 306, 206, ui.MUTED) end
local near = net.nearby()
if near > 0 then g.text_right(near .. " JANITOR" .. (near > 1 and "S" or "") .. " NEARBY", 306, 226, ui.ACCENT) end
end
Title.button = menu_button
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
g.text("M.O.S.A.", x, 30, ui.PAPER_INK, 2)
ui.tracked("SCAN TO ENTER", x, 54, ui.PAPER_INK, 1, 1)
g.text("The Museum of", x, 70, ui.MUTED)
g.text("Sirius Art", x, 80, ui.MUTED)
local p = DATA.pieces[self.art]
g.fill_rect(x, 98, 100, 92, g.color(24, 24, 24))
ui.thumb(p, x + 26, 104, 3)
g.text(ui.fit(p.title, 100), x, 196, ui.PAPER_INK)
g.text(ui.fit(p.artist, 100), x, 206, ui.MUTED)
ui.tracked(short_url(DATA.site):upper(), 14, 222, ui.PAPER_INK, 1, 2)
end
function Lanyard:button() pop() end
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
for _, l in ipairs(ui.wrap(self.heading, w, 1)) do g.text(l, x, y, ui.MUTED); y = y + 10 end
y = y + 6
for i, l in ipairs(ui.wrap(self.title or "", w, 1)) do
if i <= 4 then g.text(l, x, y, ui.PAPER_INK); y = y + 10 end
end
y = y + 4
ui.paragraph(self.body or "", x, y, w, ui.MUTED, 1, 10)
local spaced = short_url(self.url):gsub("/", "/ "):gsub("%?", " ?")
local lines = ui.wrap(spaced, w, 1)
local yy = 214 - #lines * 10
for _, l in ipairs(lines) do g.text((l:gsub("/ ", "/")), x, yy, ui.PAPER_INK); yy = yy + 10 end
g.text(badge.input.label("b") .. " back", x, 228, ui.MUTED)
end
function Code:button(key) if key == "b" or key == "a" then pop() end end
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
local door = room:door_under(self.px, self.py)
if not door then self.armed = true
elseif self.armed then
self:travel(door.to, room.data.id)
return
end
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
Card = { name = "card" }
Card.__index = Card
Card.under = true
Card.static = true
function Card.new(piece, new) return setmetatable({ piece = piece, new = new }, Card) end
function Card:draw()
local p = self.piece
g.fill_rect(18, 22, 284, 196, ui.PAPER)
g.fill_rect(30, 34, 66, 96, g.color(24, 24, 24))
ui.thumb(p, 39, 46, 3)
local x, w = 108, 184
ui.tracked(ui.TIER[p.tier] or "", x, 36, ui.MUTED, 1, 2)
local y = 52
local size = (#p.title * 12 <= w) and 2 or 1
for i, l in ipairs(ui.wrap(p.title, w, size)) do
if i <= 3 then g.text(l, x, y, ui.PAPER_INK, size); y = y + 9 * size + 2 end
end
y = y + 4
g.text(ui.fit("by " .. p.artist, w), x, y, ui.PAPER_INK)
local c = collections[p.c]
if c then g.text(ui.fit(c.name, w), x, y + 12, ui.MUTED) end
ui.tracked(self.new and "NEW TO YOUR RECORD" or "ALREADY IN YOUR RECORD", x, 120, self.new and ui.PAPER_INK or ui.MUTED, 1, 1)
ui.paragraph("It stands somewhere in the museum, in full resolution. Find it there to collect it on Solana.", 30, 146, 260, ui.MUTED, 1, 11)
ui.hints({ "a", "museum link", "b", "back to work" }, 200, ui.MUTED)
end
function Card:button(key)
if key == "a" then
pop()
push(Code.new(self.piece.url, "FIND IT IN THE MUSEUM", self.piece.title, "by " .. self.piece.artist))
elseif key == "b" then pop() end
end
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
g.fill_rect(40, 54, 240, 132, ui.PAPER)
ui.tracked(info[1], 54, 66, ui.PAPER_INK, 1, 2)
g.text(ui.fit(self.mark.label or self.room.name, 212), 54, 80, ui.MUTED)
ui.paragraph(info[2], 54, 98, 214, ui.PAPER_INK, 1, 11)
ui.hints({ "a", "museum link", "b", "back" }, 170, ui.MUTED)
end
function Plaque:button(key)
if key == "a" then
local info = PLAQUES[self.mark.kind] or { self.mark.kind:upper() }
pop()
push(Code.new(self:url(), "IN THE MUSEUM", info[1], self.room.name))
elseif key == "b" then pop() end
end
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
g.fill_rect(24, 20, 272, 200, ui.BG)
g.rect(24, 20, 272, 200, ui.DIM)
ui.tracked("ON SHIFT", 40, 34, ui.MUTED, 1, 3)
g.text(ui.fit(self.game.room.data.name, 240, 2), 40, 48, ui.INK, 2)
local found = record.found_count()
g.text(found .. " of " .. #DATA.pieces .. " bottles in your record", 40, 74, ui.MUTED)
local left = self.game.room:balloons_left()
g.text(left == 0 and "No balloons left in this room" or (left .. " balloon" .. (left > 1 and "s" or "") .. " left in this room"), 40, 86, ui.MUTED)
local near = net.nearby()
g.text(near == 0 and "No other janitors in range" or (near .. " other janitor" .. (near > 1 and "s" or "") .. " on shift nearby"),
40, 98, near > 0 and ui.ACCENT or ui.MUTED)
menu(self.items, 52, 120, self.sel, 15)
end
function Pause:update(dt)
self.t = (self.t or 0) + dt
if self.t > 1 then self.t = 0; invalidate() end
end
function Pause:button(key)
if key == "b" then pop() else menu_button(self, key) end
end
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
if self.sel > n then g.fill_rect(GX, ry + 4, 4, 4, ui.ACCENT) end
g.text("SHIFT REPORT", GX + 8, ry + 2, self.sel > n and ui.INK or ui.DIM)
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
ui.tracked("SHIFT RECORD", 10, 12, ui.INK, 1, 3)
g.text_right(record.found_count() .. " / " .. n, 310, 12, ui.MUTED)
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
Map = { name = "map", static = true }
Map.__index = Map
function Map.new() return setmetatable({ sel = 1 }, Map) end
function Map:draw()
g.clear(ui.BG)
ui.tracked("VISITOR MAP", 10, 12, ui.INK, 1, 3)
local visited = util.count(record.state.rooms)
g.text_right(visited .. " / " .. #DATA.rooms .. " ROOMS", 310, 12, ui.MUTED)
local first = math.max(1, math.min(self.sel - 4, #DATA.rooms - 9))
for i = first, math.min(#DATA.rooms, first + 9) do
local r = DATA.rooms[i]
local y = 32 + (i - first) * 13
local seen = record.state.rooms[r.idx]
if seen then g.fill_rect(12, y, 7, 7, ui.ACCENT) else g.rect(12, y, 7, 7, ui.DIM) end
g.text(seen and r.name or "????????", 26, y, i == self.sel and ui.INK or (seen and ui.MUTED or ui.DIM))
local got, total = 0, #(r.goals or {})
for _, goal in ipairs(r.goals or {}) do if record.state.goals[r.id .. "/" .. goal.id] then got = got + 1 end end
if total > 0 then g.text_right(got .. "/" .. total, 310, y, got == total and ui.ACCENT or ui.DIM) end
end
local r = DATA.rooms[self.sel]
g.line(10, 166, 310, 166, ui.DIM)
local y = 174
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
ui.tracked("ABOUT", 10, 12, ui.INK, 1, 3)
local y = 34
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
push(Title)
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
local s = top()
if toast and (getmetatable(s) == Game or s == Title) then
local h = toast.sub and 30 or 18
local y = 188 - h
g.fill_rect(0, y, 320, h, ui.PAPER)
ui.tracked_center(toast.text, 160, y + 5, ui.PAPER_INK, 1, 2)
if toast.sub then g.text_center(ui.fit(toast.sub, 310), 160, y + 18, ui.MUTED) end
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
