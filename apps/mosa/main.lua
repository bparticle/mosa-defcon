-- M.O.S.A. Night Shift: walk the museum after hours, find the bottles, scan into the HD museum.
-- v0.1.0 · MOSA f1d804c · data e237434a22832eaa · https://github.com/bparticle/mosa-defcon
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
function ui.key(name, x, y, paper)
local label = badge.input.label(name)
local w = #label * 6 + 6
g.fill_rect(x, y - 2, w, 12, paper and ui.PAPER_INK or ui.INK)
g.text(label, x + 3, y, paper and ui.PAPER or ui.BG)
return w
end
function ui.hints(list, y, col, paper)
y = y or 228
local width = 0
for i = 1, #list, 2 do width = width + (#badge.input.label(list[i]) + #list[i + 1]) * 6 + 25 end
local x = (ui.W - width + 14) // 2
for i = 1, #list, 2 do
x = x + ui.key(list[i], x, y, paper) + 5
local word = list[i + 1]:upper()
g.text(word, x, y, col or ui.MUTED)
x = x + #word * 6 + 14
end
end
ui.SHADOW = g.color(0, 0, 0)
ui.CONC = g.color(32, 32, 32)
local BOARD, TIE = g.color(24, 24, 24), g.color(16, 16, 16)
function ui.concrete(x, y, w, h, base, line)
g.fill_rect(x, y, w, h, base or ui.CONC)
line = line or BOARD
local k = 0
for yy = y + 6, y + h - 1, 7 do
k = k + 1
g.line(x, yy, x + w - 1, yy, line)
for xx = x + (k * 37) % 71, x + w - 1, 71 do g.line(xx, yy + 1, xx, math.min(yy + 6, y + h - 1), line) end
end
for yy = y + 17, y + h - 6, 42 do
for xx = x + 19, x + w - 4, 40 do g.fill_rect(xx, yy, 2, 2, TIE) end
end
end
function ui.slab(x, y, w, h, col, d)
d = d or 4
g.fill_rect(x + d, y + d, w, h, ui.SHADOW)
g.fill_rect(x, y, w, h, col or ui.PAPER)
end
function ui.header(title, right)
ui.concrete(0, 0, ui.W, 26)
ui.tracked(title, 10, 10, ui.INK, 1, 3)
if right then g.text_right(right, 310, 10, ui.MUTED) end
g.fill_rect(0, 26, ui.W, 2, ui.INK)
end
local GLYPH = {
M = "1100011111011111111111101011110001111000111100011",
O = "11111111111101111011110111111111111",
S = "11111111111100011111000111111111111",
A = "11111111111101111111111111101111011",
["."] = "00000000001111",
}
function ui.block_width(s, k)
local w = 0
for i = 1, #s do
local bits = GLYPH[s:sub(i, i)]
w = w + ((bits and #bits // 7 or 3) + 1) * k
end
return w - k
end
function ui.block(s, x, y, k, col, shadow)
if shadow then ui.block(s, x + k, y + k, k, shadow) end
for i = 1, #s do
local bits = GLYPH[s:sub(i, i)]
if bits then
local w = #bits // 7
for row = 0, 6 do
local run = -1
for c = 0, w do
local on = c < w and bits:byte(row * w + c + 1) == 49
if on and run < 0 then run = c
elseif not on and run >= 0 then
g.fill_rect(x + run * k, y + row * k, (c - run) * k, k, col)
run = -1
end
end
end
x = x + (w + 1) * k
else
x = x + 4 * k
end
end
end
function ui.no(n) return string.format("NO. %03d", n) end
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
local FACE_C = { [0] = g.color(26, 26, 26), g.color(54, 53, 51), g.color(98, 96, 92), g.color(158, 155, 148) }
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
if l >= 2 then g.line(sx, sy + 4, sx + TILE - 1, sy + 4, FACE_C[l]) end -- board marks
local below = self.cells[i + w]
if below and below ~= WALL then g.fill_rect(sx, sy + TILE - 5, TILE, 5, FACE_C[l]) end
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
tint=25388,
pal="0841ad55b5b694b27bcf4a696b6d",
rle="E0A7B5M0C1M0C1M0C1M0A5C1L0C1A6L0A6B1A4L0A7A1A5A6M0C1M0C1L0E1J0G1I0G1J0E1A3J0E1A3J0A1B2B1A3J0B4A2B1A3J0B4B2A1A3J0A4A1A2A3A1A3J0A4B1A2A1A3J0B4B2B3J0A6A1B2B1K0E1K0E1E0"
},
{
idx=1,
c="bottle",
id="bottle-rare-sirius",
title="Get Sirius Bottle",
artist="Sirius Crocodile",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-rare-sirius",
tint=61179,
pal="ad35bd33b5968410acb19c2e9cb3",
rle="E0A5A2A3M0A6B5M0A6A5A2M0A6A5A2M0A7B1A3L0A4A1B3L0A4B1A3L0A4A1B7M0A6A5A2M0A5B2L0A5D2K0A5E2I0B6B5C2J0A4C1B3J0A4A7B1B3J0A4A7B1B3J0A4A7A1C3J0A4A7A1B3A5J0B4A6A3B5J0B4B6B5J0B4A6A1A5A7J0B4A1A6B5K0A4B6B2K0B6C5E0"
},
{
idx=2,
c="bottle",
id="bottle-vestica",
title="Vestica Bottle",
artist="Vestica",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-vestica",
tint=46453,
pal="0861bdf794b2a5357befac4d82a9",
rle="G0A1O0A1O0A5O0A7A3M0C3A5B4G0A3C2A1A4C2A5F0A5B2E3A2A3F0A1A4C5B6B3A5F0A3B1A5A6D1A4F0A5A3A5A1D7A1A7G0A5D1A4B1H0A5B1B3A4A1A3I0B5C1B3I0A3A5A1A3B4A7J0B5A3A4A7K0A5A1B3A6L0B1B3L0A5A1A7N0B7N0A1A7N0A3A4O0A2M0E2K0D2E0"
},
{
idx=3,
c="bottle",
id="bottle-stefan",
title="Perple Juice",
artist="Stefan Grosse Halbuer",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-stefan",
tint=31569,
pal="1047084159886aae94320004a4d6",
rle="E0C4M0C1M0C1M0C1M0A4A5B7L0B5A7A5L0A4A5A7A5L0B4A1A7M0C1M0C1L0E1J0G1I0B1C6A1A2J0B1A6A7A4A7J0A2B4A7A2A7J0A5D2A7J0B5C7A5J0C2B7A2J0B5A2B7A2J0B5B7B2J0C2A7B5J0B3A2A5A2A4A5J0A1A4C1K0E1E0"
},
{
idx=4,
c="bottle",
id="bottle-jose",
title="Caffeine Bottle",
artist="Jose Narciso",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-jose",
tint=46421,
pal="bdb508c3bb09bd2db574b4f20a55",
rle="H0A6B1M0A6A5A7M0A7A2A7M0B7A2M0A7B2C3C0C3D0B3A2C3A2A0A2A7D3B0A6A3A2A3B2C0C2D3A2B3B2A0A3B0F2C3C2B1B0A2C5A6E2A3D1A0A2A5B1A5B6B2E1B0A2A5D1A5C3C1A5C0B5F1A5A1A5A6F0A5F1A5B6H0B5C1A5A6I0A2A5A2A5B1A7H0B3A7A4B6J0A2A7B4A6A7I0B2A7A4B6A7H0B2B7A4B6B7G0A2C7A4B6B7F0A6C7B4A6A7H0B3B7A4A6K0C7J0"
},
{
idx=5,
c="bottle",
id="sirius-bottle",
title="Sirius Bottle",
artist="Sirius Crocodile",
tier="legendary",
url="https://mosa.center/at/find/bottle/sirius-bottle",
tint=44475,
pal="7c3484756bb273f30026ca670025",
rle="D0A3A1B2L0A3C1A2I0A4C1F2F0A4A1H2F0A4A1H2E0A4A3A1I2D0A4A3A1I2D0B4K2C0A3A4C2C6A2A5A1B2C0B3C2A5A1B2B5B1C0B3A2B1A5C1B5B1C0B3C1B5B1B4B1A6B0B3C1A4G1A6B0B3L1B0B3A4K1B0B3A4K1C0A3A4H1C4C0A3A4E1A5C7A3A4D0C4C7E3A4E0J3F0I3A4G0H3A4H0E3B4I0C4G0"
},
{
idx=6,
c="bottle",
id="bottle-scum",
title="SCUM bottle",
artist="SCUM",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-scum",
tint=65404,
pal="e71bc5d7b512a4704a49bd7493cd",
rle="U0D5M0A5A3M0A6D2I0F6C2B6C0A3A6B3A6A2A3A6A2A6B2B6A0B3C4A3C2D3A2A6A0B7C4A7B6A4A6B3B7C0I7A4A7A1A3C0A4A3A1C7A3C7B1A7C0A4A3B1B7A3B7C1A7A6C0A3C1A4A6A7A4C1A4A3C0A3D1A3A4D1B5B0B5D1B3D1A7A4C0A4C1C5A2D1A4C0A4C1A2A4A6A2A6C1A3C0A4B1B3A4A2C6B1A3C0A4B6C3A2A6B2A6A2A3C0A3A2A6B3A4E6B3A6B0A7A4B3A6B3A2A6B2A3B6B0D7A4A3A2B6C4G0B7A3A2B3A7K0B4A7V0"
},
{
idx=7,
c="bottle",
id="bottle-silo",
title="Silo has Juice",
artist="Silo",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-silo",
tint=38316,
pal="a57309e000e0950a12207c677405",
rle="E0C1M0B5A2M0B5A2M0C5M0A6C4L0B6B4L0A4A6B4L0B6B4M0A2A5A2M0C5L0A2C5A2J0B2C5B2I0E2B3J0B7A6C4J0A7A6D4J0A7B6C4J0A7A6C1A4J0B7A1C4J0B7A1C4J0B7D1J0B7A6C4J0B7A6C4K0A7B6A4A2K0E5E0"
},
{
idx=8,
c="bottle",
id="bottle-amir-hamz",
title="AmeT Bottle",
artist="AmeT",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-amir-hamz",
tint=35658,
pal="a42c0ac989220800022620407881",
rle="E0C1M0C3M0C3M0C3M0A2A5B2L0A3C1L0D1L0A1A5B2M0C3M0C3L0E3J0G3I0A7F4J0C4C2J0B5C2A6J0B5A3B2A6J0A7B3A2A6A1J0B7A3A2B6J0A5A7A3A2B6J0A5A7A3C2J0A5B7C2J0F1K0A3C1A3K0E3E0"
},
{
idx=9,
c="bottle",
id="bottle-iblolurker",
title="Ribbit Bottle",
artist="IblisX",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-iblolurker",
tint=38029,
pal="09c092a5bbc833b6b3660060ad55",
rle="U0C1M0C1M0C1A4L0D4L0D4L0D4L0D4M0C1L0E1K0E1J0G1I0A1C6B1A6J0B2B5B3J0A2C7A5A3J0A2A7A6B7A3J0A2A7A6B7A3J0A2B7A6A7A3J0B2B5B3J0F2J0B2C5A3J0B2B5C3J0B2B5A1K0E1E0"
},
{
idx=10,
c="bottle",
id="bottle-thehome113-a",
title="DOM Bottle",
artist="DOM",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-thehome113-a",
tint=31695,
pal="0020ad55086194b2843021044208",
rle="E0B3A6M0C3M0A7A3A6M0A6A3A6M0A4A3B2L0A7C3L0B4B3L0A5A4B2M0C3M0B3A6L0A7A6B7A6J0A7B3A6B7A3I0A6F3J0B5D2J0A5A4D2J0B3A1A3B2J0F3J0A5D3A2J0A5A4D2J0A3A4A3C2J0A5A4A3A2B1J0A3A5A4A1B2K0A3A4A2B3K0E3E0"
},
{
idx=11,
c="bottle",
id="bottle-jigsawgeneral",
title="Pieces",
artist="Jigsaw",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-jigsawgeneral",
tint=25356,
pal="0000ad55b5b6528a843094b20861",
rle="E0C7M0B7A1M0C1M0A1A7A1M0A4B7A4L0A4A5A7A4L0C7A4L0B4A7A4M0C7M0A1A7A1L0A7B1A7A1J0A7B1C7A1I0A7E1A7J0A6C7A3A2J0A5A6B7B3J0A5A6B7A2A7J0B5A7A2A3A7J0A6B7A2B3J0A6A7A1A5A4A2J0A5B7A2B7J0A4A7B2B7J0B7B2A3A7K0D7A1K0C7A1A7E0"
},
{
idx=12,
c="bottle",
id="bottle-aleciatv1-a",
title="COSMIC drink",
artist="Cosmic",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-aleciatv1-a",
tint=50258,
pal="93064415c2a9ad103a5499e50841",
rle="E0C2M0B6A3M0A6B3M0A6B3M0A2A5B2L0A4A7B4L0A4A7B4L0B5B2M0A6B3M0C3L0E3J0G3I0B6E3J0B6A1A3B5J0B6B1B5J0B6A1B5A2J0B6A1B5A2J0A1A6A1B5A2J0A1A6A1B5A2J0A1A6A1C5J0A1A6A1B5A4J0A1A6A1B5A4K0B6A1A5A3K0B6C3E0"
},
{
idx=13,
c="bottle",
id="bottle-scubasteveart",
title="Scuba's Goblin Juice",
artist="Scuba",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-scubasteveart",
tint=33741,
pal="00009450acf0ad3183cb08415a65",
rle="E0A7A5A7M0B6A1M0A6B1M0A6A1A6M0A2A3B4L0A5A2A3A4L0A5A2A3A5L0A5B6A4M0A1B6M0A1B6L0A6B1A6A1J0A6C1A6A1A6I0A6F1J0A1A6C3A4J0A7B6C3J0D6B3J0A6A5B6A5A3J0A5A7B4A6A3J0B7A3A4A7A3J0A7B6B5A4J0A5A7B5A3A4J0A5A7A5A2A3A4K0A6A2B3A6K0B6A1B6E0"
},
{
idx=14,
c="bottle",
id="bottle-pixelsushirobot",
title="100% Sushi",
artist="PixelSushiRobot",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-pixelsushirobot",
tint=50744,
pal="b5b6ad54648f002010829cd20841",
rle="E0A2B180A6A2B1L0A6A2B1L0A6A2B1L0A6A2B1M0A2B1+0B7J0F7A5I0A5A7A4D5J0A2A7B3B5J0A6A2B5B1J0A6B2C1J0B6A2C1J0B6A2C1J0B6B2B1A2I0B6A3C1A2I0B6C2B1K0A2B1F0"
},
{
idx=15,
c="bottle",
id="bottle-basketbskt",
title="Absolutely not weird refreshing drink",
artist="Bskt",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-basketbskt",
tint=40049,
pal="18e24ae6ac915a2b72ee8b908a88",
rle="E0C3M0C2M0C2M0C2M0A4C5L0A4A5B6L0B5B6L0B4A5A6M0C2M0C2L0E2J0G2I0A2F1J0E1A5J0B4D5J0C7A6B3J0C7A6A3A6J0B5A3A6B3J0B5A3B6A3J0C7B6A3J0A5A7A5A6B3J0C4A6B5K0D1A2K0E2E0"
},
{
idx=16,
c="bottle",
id="bottle-papabearded",
title="Papa Bearded Bottle",
artist="Papa Bearded",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-papabearded",
tint=38353,
pal="33ef3b259c28953609e3b5b284ae",
rle="E0A3A6A3M0A5A2A3M0A2A7A2M0A2A6A2A3L0A2A6B7L0B2A7A2L0A6B2A5M0A3A2A5M0A3B2M0A5A1A7L0A3A2A6A1A6K0A2B6A7A2A3J0A2A1A5C2J0C3A5A7A5J0A5A3B2A3A7J0A7A3A6A3B7J0A5B3A2A7A4J0B5A7A5B4J0A1A3A5A3A7A4J0A2A3A5A2A3A4J0A7A6A5C1K0B7C1A6J0B5B6A1K0A7A5A6B1E0"
},
{
idx=17,
c="bottle",
id="bottle-officialfadd",
title="DRAGON SPIT",
artist="FADD",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-officialfadd",
tint=35949,
pal="0861cded19836986c5ac6b8f1060",
rle="E0C1M0A5A2A5M0A5B2M0A5B2A5L0C1A6L0B1B6L0B1B6M0A4B6M0A2B5M0A5B2L0A5C2A5K0A5C2B5J0A5E7J0E1A3J0A4C1B3J0A4C1B3J0A6B1C3J0A6A4B1B3J0A6C1A3A1J0A6B1A3B1J0B6A1A3B1A3J0A6B1B6A3J0C6B5K0E5E0"
},
{
idx=18,
c="bottle",
id="bottle-the-ao8-a",
title="Cell-A-Beer",
artist="AlphaOmega8",
tier="common",
url="https://mosa.center/at/find/bottle/bottle-the-ao8-a",
tint=38033,
pal="3c05104095149a89744f20a2",
rle="E0C3M0C2M0B2A6M0B2A6M0A4A5B3L0B4B3L0A4A1A4A3L0C5A3M0A2B6M0A2B6L0E6J0G6I0A6B2D6J0C2B3A4J0A4A3A5B3A5J0A1B5C3J0A4B5C3J0B5A3A5B3J0B5A3A1B3J0A1A5A3A1A5A3J0B5D3J0A4B5A4A3A5K0A2B4B6K0E2E0"
},
{
idx=19,
c="bottle",
id="bottle-duckzzyog",
title="Die Muschimeister",
artist="Duckzzy",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-duckzzyog",
tint=43916,
pal="10202000a1e5ba87ad1108009c6e",
rle="E0A3A4A5M0C2M0C2M0C2M0B3A5A4L0A7A3B4L0A3C5L0A3C5M0C2M0C2L0E2J0G2I0D1C6J0A1A2B1B4J0B3D4J0A3A7D4J0B7A5C4J0A7A1B5A4A5J0B7A5A1A5A4J0B7A5A1A4A7J0B7B5A4A7J0B7B5B4K0A1A2A5A2A1K0E2E0"
},
{
idx=20,
c="bottle",
id="bottle-glorp-goob",
title="GoobFellaSchizoCollage",
artist="Goob",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-glorp-goob",
tint=31953,
pal="0a889cd308829cea0aea2966b596",
rle="E0B2A7M0C5M0A1B5M0A1B5M0A2C7L0B2B7L0B2A7A2L0B2A7A2M0A1A5A1M0A1A5A1L0D5A1K0A1D5A6I0E1B3J0A3A6A1C6J0B3D6J0B3B6B4J0A6E4J0A3E4J0A3A4A5B4A3J0A6E3J0A6A2C3A7J0A6D2A7K0A2A4A2A7A1K0E1E0"
},
{
idx=21,
c="bottle",
id="bottle-ponderman",
title="Pondering Juice",
artist="Ponderman",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-ponderman",
tint=44381,
pal="72748537623241af6c749be9ad96",
rle="E0B4A5M0C1M0C1M0C1M0B5B2L0A5B7A2L0B5B7L0B5A7A2M0C1M0C1L0A3C1A3J0A3E1A3I0A3B1A3A4A1A4J0A5A3D2J0C5C2J0C5A7B2J0B5A7A2A6A2J0C5A2A6A2J0A4B3C2J0A4A3B1B2J0A4B3A1B7J0A3B4A1B7K0B4C1K0E1E0"
},
{
idx=22,
c="bottle",
id="bottle-agniis-eg",
title="Mom I'm Bottle",
artist="evErgrace",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-agniis-eg",
tint=27467,
pal="0840ad557b8a5aca39e79ccd2924",
rle="E0C2M0C1M0C1M0C1M0A4A1A7A6L0C5A3L0A1A5A4A6L0A4A3A7A6M0C1M0C1L0E1J0G1I0G1J0A4D1A4J0C1A4A7A3J0A4B1A6A1A3J0A3A6B1B6J0A3A7A6A7B6J0B3A7A4A3A2J0B3B4A2A5J0A4A5A3A2A6A2J0B4A2A4A3A6K0A1A4A6B1K0E1E0"
},
{
idx=23,
c="bottle",
id="bottle-itsbubblezzz",
title="Bottle by Bubblezzz",
artist="BubbleZzz",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-itsbubblezzz",
tint=40046,
pal="00209cf383449c07ad75949183ee",
rle="E0C5M0C1M0C1M0C1M0A3C4L0A4A3B2L0A7A6B2L0A7A6B2M0C1M0C1L0E1J0G1I0G1J0B7B6B2J0B7A6B2A6J0B7A6B2A4J0B7B6B4J0B7A2A4A5A3J0A4A3C4A5J0B3A2B4A5J0B3B4A5A3J0D3B4K0B3B4A1K0E1E0"
},
{
idx=24,
c="bottle",
id="bottle-degenghosty",
title="Ghosty's Margaweeda",
artist="Degen Ghosty",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-degenghosty",
tint=33909,
pal="553430eba3b210674cf4626b",
rle="E0C4M0C1M0C1M0A1A5A1M0A6C2L0B6B2L0B6A2A6L0B4B2M0C1M0C1L0A5C1A5J0A5E1A5I0A5A1E4J0A4E2J0A4E2J0D2A6A3J0B6A2C3J0B6A2A6B3J0B6A2A6B3J0A6B2B6A3J0A6A4A2B3A2J0A6B2B3A2K0A5B2B1K0E1E0"
},
{
idx=25,
c="bottle",
id="bottle-nooffswitch",
title="Elemental",
artist="NoOffSwitch",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-nooffswitch",
tint=29517,
pal="10a220e431a6294552287b2ca4b1",
rle="E0A5A6A7M0B1A2M0A2A4A3M0A3A2A3M0A5C6L0A5C6L0D6L0D5M0A2A4A3M0A2B3L0B3B5A3J0A5A3A4B5B3I0A4B2A4A3B4J0B2D4J0B2B4B3J0B2B4B3J0A6A2A4B3A7J0B5D7J0A4A1D7J0B2A4A3A5A7J0A2C6A2A5J0B1B5B1K0B1A2A4A2K0B1C2E0"
},
{
idx=26,
c="bottle",
id="bottle-plumpfun",
title="Plumpa Oil",
artist="Plumpa",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-plumpfun",
tint=33709,
pal="0020632c8b287bef5227938bad76",
rle="E0C7M0C1M0C1M0C1M0A5A2B4L0A2A3B6L0B4B7L0C5A7M0C1M0C1L0E1J0G1I0G1J0A5A1A5C2J0A5A1D2J0A5A4A7C2J0A5A4A6C2J0A5A2A6A7B6J0A5A2B4A3A6J0A5A2B4A3A4J0A5B2A6A3A6J0A5A2C3B6J0A1B3A6A1K0E1E0"
},
{
idx=27,
c="bottle",
id="bottle-piskim0-a",
title="Love Lane",
artist="Piskimo",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-piskim0-a",
tint=59196,
pal="ad55b5b69cd38c51738ec61810a2",
rle="E0B1A6M0B3A1M0A1A2A6M0A3A1B2L0A3A1B2L0A5A3B1L0A5A3B1M0A1B2M0A3B2M0B2A6L0B2C6K0B2D6J0A3A1D2J0A3B1A2B1J0A4A3D1J0A4A3D1J0B4C3A1J0D4B5J0A4A5A3B5A4J0A4A5A3A1A7A3J0B5A4B1A3K0A4A5B1A3A4J0B4A1B2K0B3C1E0"
},
{
idx=28,
c="bottle",
id="bottle-grybnn",
title="SKYWALKIN'",
artist="GREY",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-grybnn",
tint=46228,
pal="28063849388a945293ebaccf736f",
rle="E0B5A6M0C2M0C3M0C3M0B7B6L0A5C6L0A5C6L0B5B6M0A2B3M0C3L0D3A2J0A2E3A2I0C2C1A2J0A7A1A7C4J0C7B4A6J0B7D6J0B7C6A4J0A7B5B6A4J0B5C6A4J0C5A6A4A7J0A7B5A6B4J0A7B5A6B4K0B5A6A3A2K0A2D3E0"
},
{
idx=29,
c="bottle",
id="bottle-lampwrecked-b",
title="saltwater",
artist="lampwrecked",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-lampwrecked-b",
tint=52857,
pal="bdd75a897badad556baf9cd38451",
rle="E0A4B1M0A6B4M0A4B1M0A6B1M0A5B7A5L0D5L0A7A4A5A1L0B2B3M0A6B1M0C1L0E1K0F1I0B6E1J0A5E7J0A5D7A5J0B5A7A5A7A5J0F5J0A2A7D5J0B2C5A2J0A3B2A5B3J0B2A3A7B3J0C2C3K0B2B3A1K0A6B4B1E0"
},
{
idx=30,
c="bottle",
id="bottle-siriuscrocodile",
title="Rumble Bottle",
artist="Croc Junior",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-siriuscrocodile",
tint=21627,
pal="32510214004263f612f8029685d6",
rle="E0C4M0C1M0C1M0D1L0A2A6A5A7L0A2A6B5L0B2B5M0A4B5M0C1M0C1L0E1K0F1J0A1E3J0F3J0B2A3A5B7J0B2A6A5B7J0B2A6A5B7J0B2A6A5B7J0B2A6A5B7J0B2A6A5B7J0B2A6A5C7J0A2B6C7J0A1A2A5B1K0E1E0"
},
{
idx=31,
c="bottle",
id="bottle-createdby-imrie",
title="Mana Juice",
artist="Created by Imrie",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-createdby-imrie",
tint=29425,
pal="5966006a08418b119365008b79cd",
rle="E0B7A4M0A6B2M0C6M0C6M0A7C4L0A7C4L0B7A4A7L0D7M0C6M0C6L0A2C6A2J0A2E6A2I0D2C3J0A7A4A3B4A1J0C3A5B4J0C4A5B4J0B4A7B5A4J0C1A4A5A4J0B1A7A4A1A5J0A5A4A5A3A5A3J0A1C3A4A5J0C3A5A3A5K0A2A3A5A6A2K0E6E0"
},
{
idx=32,
c="bottle",
id="bottle-barokahdimlmhr",
title="Pure Water from the Mushroom Mountains",
artist="Barokah",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-barokahdimlmhr",
tint=27244,
pal="002182524866bbd80b026486710d",
rle="E0C4M0C1M0C1M0C1M0C2A4L0B2B4L0B2B4L0A7A1A2A3M0C1M0C1L0E1K0F1I0G1J0C1A3A7A3J0C1B3A7J0B3A1A5B7J0A7A1B3A2A7J0B7C2A4J0A7A3B2B5J0A3A7A2B5A6J0B7D5J0A7A3C5B6J0E1K0E1E0"
},
{
idx=33,
c="bottle",
id="bottle-boin-art",
title="50c Beers",
artist="Boin",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-boin-art",
tint=19145,
pal="12201083004018c4314620e552ac",
rle="E0A5B7M0C1M0C1M0D1L0A4A2A6A7L0B5B7L0A7B5A6M0A4A6A5M0C1M0C1L0E1K0F1J0A1E3J0A6A3A4B6A4J0A6B4B6A4J0A6B4B6A4J0A6B4A6B5J0B2A7C5J0B2A7C5J0B2B7B5J0A5A4C7A4A2J0A4A7A5A6B4J0A1A7A2B1K0E1E0"
},
{
idx=34,
c="bottle",
id="bottle-whimsiverse",
title="Rooty Tooty Whimsiverse",
artist="Whimsiverse",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-whimsiverse",
tint=46201,
pal="82d793395a307b94abeb28eb",
rle="E0A2B1M0C2M0C2M0A1B2M0B6B4L0A4B6A4L0B4B6L0C6A4M0C2M0C2L0A1C2A1J0A1E2A1I0A1A2C3A6A1J0B5D6J0A5D4A5J0B6B4B6J0A5B6A4A5A6J0A3E5J0B3D5J0B3D5J0A5A3D5J0B5A3A4B5K0A5B6B2K0E2E0"
},
{
idx=35,
c="bottle",
id="bottle-wwfkilla",
title="Neighborino",
artist="wwfkilla",
tier="common",
url="https://mosa.center/at/find/bottle/bottle-wwfkilla",
tint=50641,
pal="b4c9cc31ad75cc7241413b846c69",
rle="E0C6M0C2M0C4M0A4B2M0D6L0D6L0C6A7L0D6M0A2B4M0C4L0A2C4A2K0C4C2I0A2A5A2D5J0B6A7A3B7J0A6A7C3A7J0A6A3D5J0A6B5B1A3J0A6A3C5A3J0A6A3C1A3J0A6A3B1A5A3J0B6A3B1A3J0A6A7C1B7J0A6C7A2K0D4A2E0"
},
{
idx=36,
c="bottle",
id="eloy-bottle",
title="Dragonmaid Juice",
artist="eloy",
tier="mythical",
url="https://mosa.center/at/find/bottle/eloy-bottle",
tint=44306,
pal="7b8d83ee5a686b0a8c4fb5952923",
rle="E0A4C1K0B3B4A1L0A3B1B5J0B4A1A4A2A1J0B3A7C4K0A4B3A4A7K0A7B3B4K0A7C3A4K0A7B1A3B5I0I6F0F6D5E0C4B1D5A2A1E0E3C4B1A2F0C3A4B1D2F0A4A3A4C1D2F0D4B1C2A1F0A7A3A4C1B2A4A2F0A4D7A4D1F0A4A3C7A1A3A2B1A2E0A4B3B7A3A7A2A1B2E0A4A3D4D2A5E0E4A1B2B5A2F0A3A4B1A2D1I0E7E0"
},
{
idx=37,
c="bottle",
id="skull-bottle",
title="SKULL POTION",
artist="Skull Shaman",
tier="rare",
url="https://mosa.center/at/find/bottle/skull-bottle",
tint=65106,
pal="bcebc351a408c56daca99c07b28f",
rle="E0C2M0B6A5M0A7A2A4M0A3A5B2L0A3A7A1A2L0A3A7A1A2L0A3A5A2A1M0A7B1M0A7B1M0B1A4L0E4K0E2A4J0A7A5D1J0A6A5D1J0A6A5D1J0A3A5D1J0A3A7D1J0B3A1B2A1J0B3A5C1J0B3A5A7A2A1J0B3A7C1K0A6A5D1J0A6B7A1A2K0A6A3A5A2A5E0"
},
{
idx=38,
c="bottle",
id="bottle-simulations",
title="Simulation's Mixed Matter",
artist="Simulations",
tier="rare",
url="https://mosa.center/at/find/bottle/bottle-simulations",
tint=48634,
pal="ce3dc5fcb5b608a27ad094f12a0b",
rle="E0C3M0B2A1M0A2B1M0A1A2A1M0A5B6A7L0A5C7L0B5A7A6L0B7A5A6M0C2M0A2B1L0B2B1A2K0A2C1B2I0C2B4A1A7J0A7B6A7A6A7J0C5B4A5J0B7A6A4A6A5J0C6C3J0C6B3A7J0C6C3J0C6B4A7J0A7A4D7J0B4D7K0D4A2K0B2B1F0"
},
{
idx=39,
c="bottle",
id="bottle-tornado-ilus",
title="Fresh and sticky",
artist="Tornado Rodriguez",
tier="legendary",
url="https://mosa.center/at/find/bottle/bottle-tornado-ilus",
tint=28048,
pal="0aca01e133ee02807c890a868d10",
rle="E0C5M0C6M0C6M0D6L0B5B3L0A1C3L0B5B3M0C3M0C6M0C6L0E6K0F6J0A4A6A4C2J0F5J0C5B7A5J0A1B3A1A7A3J0B1A3B7A1J0B1A3A7A6A1J0A5A1A5C7J0A5A1A5C7J0A5A1A5D7J0B5C7A5J0A6C5A6K0E6E0"
},
{
idx=40,
c="bottle",
id="mosanade",
title="MOSAnade",
artist="Sirius Crocodile",
tier="rare",
url="https://mosa.center/at/find/bottle/mosanade",
tint=52958,
pal="318b73b3a5567db8cfdfa3d49493",
rle="E0A7C2K0A2A7C2K0A1A7D2K0A1A2B5L0A7A2C5J0A1B3D5I0A4A1B4A3B4H0I4G0I4G0E4C7A2G0B7A2D6A3A7G0C7A6A7A1B6A2G0D7B6A7B2H0A2B7B3C6H0A1C7A3A7B6H0B2B7B3A7A2A3G0A2D7B3A6A3G0B2C7D3G0A7B2A7A3A1C3G0A7A2B7B2B3A4G0A7A2B7D3A7G0B2A4A1A2A7C4H0G4J0B4H0"
}
}
}
end
package.preload["build_info"] = function(...)
return { version = "0.1.0", mosa = "f1d804c59a35", data = "e237434a22832eaa", repo = "git+https://github.com/bparticle/mosa-defcon.git" }
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
local Splash, Title, Lanyard, Game, Pause, Card, Plaque, Code, Record, Map, About
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
Splash = { name = "splash", t = 0 }
local LOGO = "M.O.S.A."
function Splash:update(dt)
local before = self.t
self.t = self.t + dt
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
local s = top()
if toast and (getmetatable(s) == Game or s == Title) then
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
