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

--- The bottom hint line: "SELECT  pick up   CANCEL  back".
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
