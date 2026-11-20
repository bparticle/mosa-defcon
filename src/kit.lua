-- MOSA's 2D language, translated to a 320x218 screen and a 6x8 bitmap font.
-- (Named kit, not ui: `ui` is Solana OS's own module, which gfx.lua uses.)
--
-- The museum's rules (apps/frontend/CLAUDE.md, "Design language") hold here:
-- near-black or off-white surfaces, typography-led, wide-tracked uppercase
-- labels, and NO colour in the chrome. All chromatic energy comes from the
-- archive itself (the works and the bottles). The single non-neutral
-- accent is the museum's crosshair green, #7ee8a8.
local g = require("gfx")
local ui = {}

ui.BG = g.color(11, 11, 12)
ui.INK = g.color(236, 232, 224)
ui.PAPER = g.color(236, 232, 224)
ui.PAPER_INK = g.color(18, 18, 18)
ui.MUTED = g.color(132, 128, 120)
ui.DIM = g.color(58, 56, 54)
ui.CAST = g.color(170, 166, 158) -- plaster
ui.ACCENT = g.color(0x7e, 0xe8, 0xa8)

ui.W, ui.H = g.W, g.H -- 320 x 218, below Solana OS's status bar

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
  for w in tostring(text):gmatch("%S+") do
    local word = w -- loop variables are read-only in Lua 5.5
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

-- The badge's buttons, as Solana OS names them on its own screens.
local LABEL = { a = "SELECT", b = "CANCEL" }
function ui.label(name) return LABEL[name] or name:upper() end

--- A button as MOSA prints it on a plaque: an inverted block.
function ui.key(name, x, y, paper)
  local label = ui.label(name)
  local w = #label * 6 + 6
  g.fill_rect(x, y - 2, w, 12, paper and ui.PAPER_INK or ui.INK)
  g.text(label, x + 3, y, paper and ui.PAPER or ui.BG)
  return w
end

--- The bottom hint line: [SELECT] MUSEUM LINK   [CANCEL] BACK.
ui.HINTS_Y = ui.H - 12
function ui.hints(list, y, col, paper)
  y = y or ui.HINTS_Y
  local width = 0
  for i = 1, #list, 2 do width = width + (#ui.label(list[i]) + #list[i + 1]) * 6 + 25 end
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
  L = "11000110001100011000110001111111111",
  D = "11110111111101111011110111111111110",
  W = "1100011110001111000111101011111111111101111100011",
  N = "110011111011111111111111110111110011110011",
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

-- Thumbnails: palette art from the sync, 16x24 for a bottle and up to 24x24
-- for a hung work (piece.sw x piece.sh). piece.rle is run-length pairs (count
-- in the base64 alphabet, palette index in hex, 0 = clear), so a draw is one
-- rect per run and nothing is cached but the 15-colour palette (RGB565 in the
-- data, turned into the canvas's 0xRRGGBB once).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local COUNT, HEX = {}, {}
for i = 1, 64 do COUNT[B64:byte(i)] = i end
for i = 0, 15 do HEX[(string.format("%x", i)):byte()] = i end
local palettes = {}
local function palette(piece)
  local pal = palettes[piece]
  if not pal then
    pal = {}
    for i = 1, #piece.pal // 4 do pal[i] = g.from565(tonumber(piece.pal:sub(i * 4 - 3, i * 4), 16)) end
    palettes[piece] = pal
  end
  return pal
end
setmetatable(palettes, { __mode = "k" })

function ui.size(piece) return piece.sw or 16, piece.sh or 24 end

--- Draw a piece's thumbnail. `cast` (a colour) draws its silhouette instead:
--- MOSA shows an unfound legendary as a plaster cast of its own shape.
function ui.thumb(piece, x, y, scale, cast)
  local s = piece.rle
  if not s then return end
  scale = scale or 1
  local W = piece.sw or 16
  local pal = palette(piece)
  local pos = 0
  for i = 1, #s - 1, 2 do
    local n, c = COUNT[s:byte(i)], HEX[s:byte(i + 1)]
    if c > 0 then
      local col = cast or pal[c]
      local p, left = pos, n
      while left > 0 do
        local px = p % W
        local len = math.min(left, W - px)
        g.fill_rect(x + px * scale, y + (p // W) * scale, len * scale, scale, col)
        p, left = p + len, left - len
      end
    end
    pos = pos + n
  end
end

--- n x n colours sampled from a piece's sprite (cell centres), for the tiny
--- framed works on the museum's walls. Clear pixels come back as `bg`.
function ui.sample(piece, n, bg)
  local W, H = ui.size(piece)
  local want, out = {}, {}
  for j = 0, n - 1 do
    for i = 0, n - 1 do
      want[((j * H) // n + H // (2 * n)) * W + (i * W) // n + W // (2 * n)] = j * n + i + 1
    end
  end
  local pal, s, pos = palette(piece), piece.rle, 0
  for i = 1, #s - 1, 2 do
    local cnt, c = COUNT[s:byte(i)], HEX[s:byte(i + 1)]
    for p = pos, pos + cnt - 1 do
      local k = want[p]
      if k then out[k] = c > 0 and pal[c] or (bg or ui.BG) end
    end
    pos = pos + cnt
  end
  for k = 1, n * n do out[k] = out[k] or (bg or ui.BG) end
  return out
end

--- A piece on show: a dark mat of size w x h with the piece centred at the
--- largest whole scale that fits (and a pale frame round a work).
function ui.mat(piece, x, y, w, h, cast)
  g.fill_rect(x, y, w, h, g.color(24, 24, 24))
  local pw, ph = ui.size(piece)
  local k = math.max(1, math.min((w - 8) // pw, (h - 8) // ph))
  local ox, oy = x + (w - pw * k) // 2, y + (h - ph * k) // 2
  if piece.sw and not cast then g.rect(ox - 2, oy - 2, pw * k + 4, ph * k + 4, ui.PAPER) end
  ui.thumb(piece, ox, oy, k, cast)
end

ui.TIER = { common = "COMMON", rare = "RARE", legendary = "LEGENDARY", mythical = "MYTHICAL" }

return ui
