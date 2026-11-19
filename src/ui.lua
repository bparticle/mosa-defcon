-- MOSA's 2D language, translated to a 320x240 screen and a 6x8 bitmap font.
--
-- The museum's rules (apps/frontend/CLAUDE.md, "Design language") hold here:
-- near-black or off-white surfaces, typography-led, wide-tracked uppercase
-- labels, and NO colour in the chrome. All chromatic energy comes from the
-- archive itself (the bottle thumbnails, the balloons). The single non-neutral
-- accent is the museum's crosshair green, #7ee8a8.
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

--- Wide-tracked text: the museum's uppercase labels.
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

--- Greedy word wrap to a pixel width. Returns a list of lines.
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

--- Truncate to fit a pixel width with an ellipsis.
function ui.fit(s, width, size)
  local per = width // (6 * (size or 1))
  if #s <= per then return s end
  return s:sub(1, math.max(1, per - 1)) .. "~"
end

--- A button as MOSA prints it on a plaque: an inverted block.
function ui.key(name, x, y, paper)
  local label = badge.input.label(name)
  local w = #label * 6 + 6
  g.fill_rect(x, y - 2, w, 12, paper and ui.PAPER_INK or ui.INK)
  g.text(label, x + 3, y, paper and ui.PAPER or ui.BG)
  return w
end

--- The bottom hint line: [SELECT] MUSEUM LINK   [CANCEL] BACK.
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

-- ── brutalism ────────────────────────────────────────────────────────────────
-- MOSA's rooms are poured concrete. On a 320x240 screen that is: board marks
-- (the plank lines a timber form leaves), form-tie holes on a grid, slabs with
-- hard black shadows, and block letters cast from the same grid.
ui.SHADOW = g.color(0, 0, 0)
ui.CONC = g.color(32, 32, 32)
local BOARD, TIE = g.color(24, 24, 24), g.color(16, 16, 16)

--- Board-marked concrete.
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

--- A slab: a block with a hard shadow, cast down and to the right.
function ui.slab(x, y, w, h, col, d)
  d = d or 4
  g.fill_rect(x + d, y + d, w, h, ui.SHADOW)
  g.fill_rect(x, y, w, h, col or ui.PAPER)
end

--- A header band: concrete, a tracked title and a rule.
function ui.header(title, right)
  ui.concrete(0, 0, ui.W, 26)
  ui.tracked(title, 10, 10, ui.INK, 1, 3)
  if right then g.text_right(right, 310, 10, ui.MUTED) end
  g.fill_rect(0, 26, ui.W, 2, ui.INK)
end

-- Block letters, 7 rows each, cast from a grid (1 = concrete).
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

--- Draw block letters at cell size k; `shadow` casts them first.
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

--- A catalogue number: NO. 007.
function ui.no(n) return string.format("NO. %03d", n) end

--- A QR code with its quiet zone, dark on light. Returns the drawn size.
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

--- Biggest integer module scale that fits a box.
function ui.qr_scale(code, box)
  return math.max(1, box // (code.size + 6))
end

-- Thumbnails: 16x24 palette art from the sync. piece.rle is run-length pairs
-- (count in the base64 alphabet, palette index in hex, 0 = transparent), so a
-- draw is one rect per run and nothing is cached but the 15-colour palette.
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

--- Draw a piece's thumbnail. `cast` (a colour) draws its silhouette instead:
--- MOSA shows an unfound legendary as a plaster cast of its own shape.
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
