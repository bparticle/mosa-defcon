-- Drawing on Solana OS.
--
-- The badge's own UI is a tree of LVGL objects (labels, lists, rects), but
-- Night Shift paints like a framebuffer: rooms in torchlight, block letters,
-- paper cards. So the whole app area is ONE canvas (320 x 218, 2 bytes a pixel
-- of the app's heap, about 140 KB) that keeps what is painted on it between
-- callbacks, and everything is drawn onto it, text included, in the 6x8 font
-- of font.lua. The one other object is the QR code: Solana OS draws those
-- itself (ui.qr), on top of the canvas, black on white.
--
-- Colours are 0xRRGGBB numbers; the canvas stores them as RGB565.
local OS = ui -- the Solana OS module; main.lua's own `ui` is kit.lua
local GLYPHS = require("font")

local g = {}
g.W, g.H = OS.W, OS.H

local canvas = OS.canvas(0, 0, g.W, g.H, { scale = 1 })
local floor = math.floor

function g.color(r, gg, b) return (r << 16) | (gg << 8) | b end

function g.rgb(c) return (c >> 16) & 255, (c >> 8) & 255, c & 255 end

--- MOSA's synced thumbnails and tints are RGB565; the canvas takes 0xRRGGBB.
function g.from565(c)
  local r, gg, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
  return g.color((r << 3) | (r >> 2), (gg << 2) | (gg >> 4), (b << 3) | (b >> 2))
end

--- h in degrees, s and v in 0..1.
function g.hsv(h, s, v)
  local c = v * s
  local hp = (h % 360) / 60
  local x = c * (1 - math.abs(hp % 2 - 1))
  local r, gg, b = 0, 0, 0
  if hp < 1 then r, gg = c, x elseif hp < 2 then r, gg = x, c elseif hp < 3 then gg, b = c, x
  elseif hp < 4 then gg, b = x, c elseif hp < 5 then r, b = x, c else r, b = c, x end
  local m = v - c
  return g.color(floor((r + m) * 255), floor((gg + m) * 255), floor((b + m) * 255))
end

function g.clear(c) canvas:rect(0, 0, g.W, g.H, c) end

function g.fill_rect(x, y, w, h, c)
  if w > 0 and h > 0 then canvas:rect(floor(x), floor(y), floor(w), floor(h), c) end
end

--- An outline, one pixel wide.
function g.rect(x, y, w, h, c)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  canvas:rect(x, y, w, 1, c)
  canvas:rect(x, y + h - 1, w, 1, c)
  canvas:rect(x, y, 1, h, c)
  canvas:rect(x + w - 1, y, 1, h, c)
end

function g.line(x1, y1, x2, y2, c) canvas:line(floor(x1), floor(y1), floor(x2), floor(y2), c) end

function g.pixel(x, y, c) canvas:pixel(floor(x), floor(y), c) end

function g.fill_circle(cx, cy, r, c)
  cx, cy = floor(cx), floor(cy)
  for dy = -r, r do
    local half = floor(math.sqrt(r * r - dy * dy) + 0.5)
    canvas:rect(cx - half, cy + dy, half * 2 + 1, 1, c)
  end
end

-- ── text ─────────────────────────────────────────────────────────────────────
-- Each glyph, once used, is kept as its vertical runs (column, first row,
-- length), so a character is a handful of rects.
local runs = {}
local function glyph(code)
  local r = runs[code]
  if r then return r end
  r = {}
  local i = code - 32
  if i < 0 or i > 94 then i = 31 end -- "?"
  for col = 0, 4 do
    local bits = tonumber(GLYPHS:sub(i * 10 + col * 2 + 1, i * 10 + col * 2 + 2), 16)
    local row = 0
    while row < 8 do
      if (bits >> row) & 1 == 1 then
        local first = row
        while row < 8 and (bits >> row) & 1 == 1 do row = row + 1 end
        r[#r + 1] = col; r[#r + 1] = first; r[#r + 1] = row - first
      else
        row = row + 1
      end
    end
  end
  runs[code] = r
  return r
end

function g.text_width(s, size) return #s * 6 * (size or 1) end

--- Text with its top-left at (x, y); `size` scales the 6x8 cell.
function g.text(s, x, y, col, size)
  size = size or 1
  x, y = floor(x), floor(y)
  for k = 1, #s do
    local r = glyph(s:byte(k))
    for j = 1, #r, 3 do
      canvas:rect(x + r[j] * size, y + r[j + 1] * size, size, r[j + 2] * size, col)
    end
    x = x + 6 * size
  end
end

function g.text_right(s, x, y, col, size) g.text(s, x - g.text_width(s, size), y, col, size) end

function g.text_center(s, cx, y, col, size) g.text(s, cx - g.text_width(s, size) // 2, y, col, size) end

-- ── the QR code ──────────────────────────────────────────────────────────────
-- One at a time (Solana OS draws at most one). `spec` is { text, x, y, size },
-- or nil to take it away. Returns false when the code cannot be shown.
local qr, shown = nil, nil
function g.show_qr(spec)
  if not spec then
    if qr then qr:remove(); qr, shown = nil, nil end
    return true
  end
  local key = spec[1] .. "@" .. spec[2] .. "," .. spec[3] .. "," .. spec[4]
  if key == shown then return true end
  if qr then qr:remove(); qr = nil end
  if not OS.qr then return false end
  local ok, obj = pcall(OS.qr, spec[2], spec[3], spec[4], spec[1])
  if not ok then shown = nil; return false end
  qr, shown = obj, key
  return true
end

return g
