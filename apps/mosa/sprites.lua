-- The people of the night shift, as pixel art: the janitor and the thieves.
--
-- 10x16 sprites seen from above at a slant, the way the rooms are drawn. Each
-- is rows of palette letters ("." is clear), compiled once into horizontal
-- runs so a sprite costs a handful of rects. Facing: "down", "up", or "side"
-- (drawn facing right; mirrored for left). Feet are separate rows so a walk
-- cycle swaps two lines instead of a whole sprite.
local g = require("gfx")

local sprites = {}
sprites.W, sprites.H = 10, 16

local C = g.color
local PAL = {
  k = C(22, 20, 20),    -- outline
  c = C(70, 76, 86),    -- cap
  b = C(44, 48, 56),    -- cap brim
  h = C(62, 46, 36),    -- hair
  s = C(226, 182, 142), -- skin
  S = C(184, 138, 104), -- skin, shade
  e = C(22, 20, 20),    -- eye
  w = C(216, 212, 202), -- shirt, stripes, eyes
  o = C(98, 112, 130),  -- overalls
  O = C(70, 80, 96),    -- overalls, shade
  t = C(40, 34, 30),    -- boots
  d = C(38, 38, 42),    -- the thief's black
  m = C(12, 12, 14),    -- the thief's mask
  p = C(30, 30, 34),    -- the thief's trousers
}

local JANITOR = {
  down = {
    "...kkkk...",
    "..kcccck..",
    ".kcccccck.",
    ".kbbbbbbk.",
    ".kssssssk.",
    ".kseSSesk.",
    ".kssssssk.",
    "..kwwwwk..",
    ".kowoowok.",
    "kwoooooowk",
    "ksoooooosk",
    ".kooooook.",
    ".kooOOook.",
    ".koOkkOok.",
  },
  up = {
    "...kkkk...",
    "..kcccck..",
    ".kcccccck.",
    ".kcccccck.",
    ".khhhhhhk.",
    ".khhhhhhk.",
    ".kSSSSSSk.",
    "..kwwwwk..",
    ".kowoowok.",
    "kwoooooowk",
    "ksoooooosk",
    ".kooooook.",
    ".kooOOook.",
    ".koOkkOok.",
  },
  side = {
    "..kkkk....",
    ".kcccck...",
    ".kccccck..",
    ".kcbbbbbbk",
    ".khsssssk.",
    ".khssseSk.",
    ".khsssssk.",
    "..kwwwwk..",
    "..kowwok..",
    "..kooowk..",
    "..kooosk..",
    "..kooook..",
    "..kooOok..",
    "..koOOok..",
  },
}

local THIEF = {
  down = {
    "...kkkk...",
    "..kddddk..",
    ".kddddddk.",
    ".kddddddk.",
    ".kmwmmwmk.",
    ".kssssssk.",
    "..kSSSSk..",
    ".kwwwwwwk.",
    "kddddddddk",
    "kwwwwwwwwk",
    "ksddddddsk",
    ".kwwwwwwk.",
    ".kppppppk.",
    ".kppkkppk.",
  },
  up = {
    "...kkkk...",
    "..kddddk..",
    ".kddddddk.",
    ".kddddddk.",
    ".kddddddk.",
    ".kmmmmmmk.",
    "..kSSSSk..",
    ".kwwwwwwk.",
    "kddddddddk",
    "kwwwwwwwwk",
    "ksddddddsk",
    ".kwwwwwwk.",
    ".kppppppk.",
    ".kppkkppk.",
  },
  side = {
    "..kkkk....",
    ".kddddk...",
    ".kdddddk..",
    ".kdddddk..",
    ".kdmmwmk..",
    ".kdssssk..",
    "..kSSSk...",
    "..kwwwwk..",
    "..kddddk..",
    "..kwwwwk..",
    "..kdddsk..",
    "..kwwwwk..",
    "..kppppk..",
    "..kpppk...",
  },
}

-- Feet: a still pose and two strides. The front and back views share them.
local FEET = {
  front = {
    { ".kXk..kXk.", ".ttk..ktt." },
    { ".kXk..ttk.", ".ttk......" },
    { ".ktt..kXk.", "......ktt." },
  },
  side = {
    { "...kXXk...", "...tttk..." },
    { "..kXk.kXk.", ".ttk...ktt" },
    { "...kXXk...", "...tttk..." },
  },
}

local cache = {}

--- One sprite pose, compiled to runs: { x, y, len, colour, ... }.
local function compile(rows, feet, leg)
  local runs = {}
  local function row(line, y)
    local x = 0
    while x < #line do
      local ch = line:sub(x + 1, x + 1)
      if ch == "X" then ch = leg end
      if ch == "." then x = x + 1
      else
        local n = 1
        while x + n < #line do
          local nx = line:sub(x + n + 1, x + n + 1)
          if nx == "X" then nx = leg end
          if nx ~= ch then break end
          n = n + 1
        end
        runs[#runs + 1] = x; runs[#runs + 1] = y; runs[#runs + 1] = n; runs[#runs + 1] = PAL[ch]
        x = x + n
      end
    end
  end
  for y, line in ipairs(rows) do row(line, y - 1) end
  row(feet[1], #rows); row(feet[2], #rows + 1)
  return runs
end

local SETS = { janitor = { JANITOR, "o" }, thief = { THIEF, "p" } }

--- Draw a figure with its feet at (x, y). `face` is down/up/left/right; `step`
--- 0 stands, 1 and 2 are strides. `scale` enlarges it (the intro).
function sprites.draw(who, face, step, x, y, scale)
  scale = scale or 1
  local side = face == "left" or face == "right"
  local key = who .. (side and "side" or face) .. step
  local runs = cache[key]
  if not runs then
    local set = SETS[who]
    local feet = side and FEET.side or FEET.front
    runs = compile(set[1][side and "side" or face], feet[step + 1], set[2])
    cache[key] = runs
  end
  local flip = face == "left"
  local ox, oy = math.floor(x) - 5 * scale, math.floor(y) - 16 * scale
  local hline = g.hline
  for i = 1, #runs, 4 do
    local rx = runs[i]
    if flip then rx = 10 - rx - runs[i + 2] end
    hline(ox + rx * scale, oy + runs[i + 1] * scale, runs[i + 2] * scale, runs[i + 3], scale)
  end
end

-- Poses with the arms off the body, so nothing is painted over a sprite that
-- still has its arms at its sides. 12 wide (an arm and its outline either side
-- of the head) and two rows taller (the hands, just over the head). Sleeves
-- are the jersey's black with a stripe at the elbow and the cuff, so a raised
-- arm reads as an arm and not a ladder. The front feet, standing.
--   hands   caught: both hands up, facing you
--   reach   from behind, both arms up at a frame on the wall
--   statue  posing as a sculpture: one arm raised, a hand on the hip
local POSES = {
  hands = {
    ".k........k.",
    "ksk......ksk",
    "kSk.kkkk.kSk",
    "kwkkddddkkwk",
    "kdkddddddkdk",
    "kdkddddddkdk",
    "kdkmwmmwmkdk",
    "kwksssssskwk",
    "kdkkSSSSkkdk",
    "kdkwwwwwwkdk",
    "kddddddddddk",
    ".kwwwwwwwwk.",
    ".kddddddddk.",
    "..kwwwwwwk..",
    "..kppppppk..",
    "..kppkkppk..",
  },
  reach = {
    ".k........k.",
    "ksk......ksk",
    "kSk.kkkk.kSk",
    "kwkkddddkkwk",
    "kdkddddddkdk",
    "kdkddddddkdk",
    "kdkddddddkdk",
    "kwkmmmmmmkwk",
    "kdkkSSSSkkdk",
    "kdkwwwwwwkdk",
    "kddddddddddk",
    ".kwwwwwwwwk.",
    ".kddddddddk.",
    "..kwwwwwwk..",
    "..kppppppk..",
    "..kppkkppk..",
  },
  statue = {
    ".k..........",
    "ksk.........",
    "kSk.kkkk....",
    "kwkkddddk...",
    "kdkddddddk..",
    "kdkddddddk..",
    "kdkmwmmwmk..",
    "kwkssssssk..",
    "kdkkSSSSk...",
    "kdkwwwwwwk..",
    "kddddddddddk",
    ".kwwwwwwwwdk",
    ".kddddddddsk",
    "..kwwwwwwk..",
    "..kppppppk..",
    "..kppkkppk..",
  },
}

--- Draw a thief's pose (see POSES) with the feet at (x, y). `flip` mirrors it.
function sprites.pose(name, x, y, scale, flip)
  scale = scale or 1
  local rows = POSES[name]
  local runs = cache[name]
  if not runs then
    local f = FEET.front[1]
    runs = compile(rows, { "." .. f[1] .. ".", "." .. f[2] .. "." }, "p")
    cache[name] = runs
  end
  local ox, oy = math.floor(x) - 6 * scale, math.floor(y) - (#rows + 2) * scale
  for i = 1, #runs, 4 do
    local rx = runs[i]
    if flip then rx = 12 - rx - runs[i + 2] end
    g.hline(ox + rx * scale, oy + runs[i + 1] * scale, runs[i + 2] * scale, runs[i + 3], scale)
  end
end

--- Which way a direction vector faces.
function sprites.facing(fx, fy)
  if math.abs(fx) > math.abs(fy) then return fx < 0 and "left" or "right" end
  return fy < 0 and "up" or "down"
end

--- Where the hand that holds the flashlight is, from the feet (scale 1).
local HAND = { down = { 4, -6 }, up = { -4, -7 }, right = { 3, -6 }, left = { -3, -6 } }
function sprites.hand(face)
  local h = HAND[face]
  return h[1], h[2]
end

--- The flashlight in the hand, pointing along (fx, fy): a short barrel and a lit lens.
sprites.TORCH = C(150, 146, 140)
sprites.LENS = C(255, 246, 214)
function sprites.torch(x, y, fx, fy)
  for i = 0, 3 do g.pixel(x + math.floor(fx * i + 0.5), y + math.floor(fy * i + 0.5), sprites.TORCH) end
  g.fill_rect(x + math.floor(fx * 4 + 0.5), y + math.floor(fy * 4 + 0.5), 1, 1, sprites.LENS)
end

return sprites
