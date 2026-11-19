-- QR codes for the badge: byte mode, error correction M, versions 1-10.
--
-- Everything here is integer arithmetic on small values, so it behaves the
-- same on the badge's 32-bit Lua as in the 64-bit emulator. Encoding is split
-- into steps so a caller can spread the mask search over several frames
-- (qr.encoder(text) returns a coroutine-style stepper); qr.encode(text) does
-- it all at once.
--
-- Follows ISO/IEC 18004 and the structure of Project Nayuki's reference
-- implementation. test/qr.test.mjs decodes the output with jsQR.

local qr = {}

-- Per version (ECC level M): total data codewords, EC codewords per block,
-- and the block layout { {count, data_codewords}, ... }.
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

-- GF(256) with the QR polynomial 0x11D.
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

-- Bits → codewords with padding, then blocks + interleaving.
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

-- The matrix is a flat table indexed y * size + x + 1, values 0/1.
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
  -- Reserve format areas (written for real once the mask is chosen).
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

-- Penalty (N1-N4), done with string scans so it stays cheap in Lua.
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

--- Smallest version (ECC M) that holds `text`, or nil.
function qr.version_for(text)
  for v = 1, #SPEC do
    local header = 4 + (v <= 9 and 8 or 16)
    if header + #text * 8 <= data_capacity(v) * 8 then return v end
  end
  return nil
end

--- A stepper: call it repeatedly; it returns nil while working and the
--- finished code { size=, modules=, version=, mask= } when done. `modules`
--- is a string, row-major, "1" for dark: qr.dark(code, x, y) reads it. Each call does
--- a bounded slice of work (one mask trial), so it fits a frame budget.
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
    -- Kept as a string of "0"/"1": a byte per module instead of a table slot.
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

--- Encode in one go.
function qr.encode(text)
  local step = qr.encoder(text)
  while true do
    local r = step()
    if r then return r end
  end
end

return qr
