-- Small pieces with no badge dependencies: a 32-bit-safe RNG, base32, bitsets.
local util = {}

-- xorshift32. Masks keep it identical on the badge's int32 Lua and the
-- emulator's int64 Lua (on int32, & 0xFFFFFFFF is & -1, a no-op).
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

--- Float in [0, 1).
function Rng:float()
  return ((self:next() >> 8) & 0xFFFFFF) / 16777216
end

--- Integer in [1, n].
function Rng:int(n)
  return ((self:next() >> 1) & 0x7FFFFFFF) % n + 1
end

--- Pick from a list of { weight = w, ... } (weights may be fractional).
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

-- Crockford base32, lowercase: no i, l, o, u, so it reads aloud and survives
-- being typed off a 320x240 screen.
local B32 = "0123456789abcdefghjkmnpqrstvwxyz"

--- bits: array of 0/1, most significant first. Padded with zeros to 5.
function util.base32(bits)
  local out = {}
  for i = 1, #bits, 5 do
    local v = 0
    for j = 0, 4 do v = (v << 1) | (bits[i + j] or 0) end
    out[#out + 1] = B32:sub(v + 1, v + 1)
  end
  return table.concat(out)
end

--- A bitset over 0-based indices, stored as a hex string (4 bits per char,
--- least significant first) so it fits an NVS string value.
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
