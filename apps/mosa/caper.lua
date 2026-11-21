-- Capers: who the thieves are, what kind of night it is, and the calling
-- cards they leave. Pure logic (no drawing), like night.lua, so it costs
-- main.lua nothing but the calls.
--
-- Four kinds of thief. Each is one rule in world.lua's update_thief:
--   creep     dazzled by the light, makes for a door
--   statue    freezes in the light and poses; only a fresh look counts
--   dodger    weaves out of the beam; back them into a wall
--   swindler  drops a dummy the first time, and bolts with the real work
--
-- The night's weather is the day's: every janitor gets the same one, and the
-- title's desk board says it before you clock in.
--
-- A calling card is written from the synced data only: the rooms' doors and
-- names, the works' sets, artists, titles and colours. Nothing is authored.
local util = require("util")

local caper = {}

caper.NAME = { creep = "THE CREEP", statue = "THE STATUE", dodger = "THE DODGER", swindler = "THE SWINDLER" }

-- What the janitor hears, walking into a room with one of them in it.
caper.TELL = {
  creep = "Sweep the dark with your light.",
  statue = "Something in here is standing very still.",
  dodger = "Quick feet. Back them into a wall.",
  swindler = "Careful. This one has tricks.",
}

--- The kind of thief for the i-th break-in of wave `wave`. The night's first
--- thief is always a creep: a new janitor learns the light on them.
function caper.kind(rand, wave, i)
  if wave <= 1 and i == 1 then return "creep" end
  local pick = rand:weighted({
    { weight = 3, k = "creep" }, { weight = 2, k = "statue" },
    { weight = 2, k = "dodger" }, { weight = wave > 1 and 2 or 1, k = "swindler" },
  })
  return pick and pick.k or "creep"
end

-- ── the night's weather ─────────────────────────────────────────────────────
--   pace   added to how fast thieves move
--   hear   how far footsteps carry (1 is normal)
--   eyes   false: no glint of eyes in the dark
--   storm  lightning shows everyone in the room for a blink
--   extra  thieves in the first break-in, over the usual three
caper.NIGHTS = {
  { id = "clear", weight = 4, name = "A CLEAR NIGHT", line = "Find them in the dark. Hold your light on them." },
  { id = "storm", weight = 2, name = "A STORM", line = "Lightning shows who is hiding, for a blink.", storm = true },
  { id = "moon", weight = 2, name = "A FULL MOON", line = "They feel bold: quicker, and slow to hear you.", pace = 0.12, hear = 0.6 },
  { id = "dark", weight = 2, name = "NO MOON", line = "No eyes glint in the dark. Trust your badge's lights.", eyes = false },
  { id = "gala", weight = 1, name = "A GALA", line = "The party ran late. One more of them got in.", extra = 1 },
}

--- The weather on day `day` (nil when the badge has no clock: a clear night).
function caper.night(day)
  if not day then return caper.NIGHTS[1] end
  local r = util.rng((day * 7919 + 4111) & 0x7FFFFFFF)
  r:next(); r:next()
  return r:weighted(caper.NIGHTS) or caper.NIGHTS[1]
end

-- ── calling cards ───────────────────────────────────────────────────────────

-- Game minutes of calm after a cleared wave when a card names the next: enough
-- to read it, work out the room, and get there (a trip on the map is 20).
caper.CALM = 40

--- A colour word for a work's tint (0xRRGGBB).
function caper.colour(tint)
  local r, g, b = (tint >> 16) & 255, (tint >> 8) & 255, tint & 255
  local hi, lo = math.max(r, g, b), math.min(r, g, b)
  if hi < 64 then return "dark" end
  if hi - lo < 40 then return hi > 180 and "pale" or "grey" end
  if r == hi then
    if g > b + 50 and g * 10 > r * 6 then return "yellow" end
    if b > g + 40 then return "pink" end
    return "red"
  end
  if g == hi then return "green" end
  if r > g + 40 then return "purple" end
  return "blue"
end

local function initials(name)
  local out = {}
  for word in name:gmatch("[%w]+") do out[#out + 1] = word:sub(1, 1):upper() .. "." end
  return table.concat(out, "", 1, math.min(3, #out))
end

-- How they put it, by kind: the card reads like the one who wrote it.
local OPENERS = {
  creep = "Dear janitor. Tonight I'll take",
  statue = "I'll stand very still tonight, beside",
  dodger = "Catch me if you can. Next I'm after",
  swindler = "With compliments. I have my eye on",
}

--- Does room `a` have a door to room `b` (either way round)?
local function next_door(a, b)
  for _, d in ipairs(a.doors or {}) do if d.to == b.id then return true end end
  for _, d in ipairs(b.doors or {}) do if d.to == a.id then return true end end
  return false
end

--- Write the card for a thief of kind `kind` who will take `work` from `room`.
--- `rooms` is DATA.rooms; returns { body, sign, room }. The clues narrow the
--- rooms that hang art down to one where the data allows it: a neighbour, then
--- the first letter of its name or how many works hang there.
function caper.card(work, room, rooms, rand, kind)
  local by_id = {}
  for _, r in ipairs(rooms) do by_id[r.id] = r end
  local art_rooms = {}
  for _, r in ipairs(rooms) do if #(r.art or {}) > 0 and not r.hidden then art_rooms[#art_rooms + 1] = r end end

  -- What they're after, from the work itself.
  local what = {}
  if work.set then what[#what + 1] = "one of the " .. work.set end
  what[#what + 1] = "something mostly " .. caper.colour(work.tint)
  if work.artist and work.artist ~= "" then what[#what + 1] = "something signed " .. initials(work.artist) end
  local first = (work.title or ""):match("%w")
  if first then what[#what + 1] = "something whose title starts with " .. first:upper() end
  local thing = what[rand:int(#what)]

  -- Where, from the room: a neighbour you can find on the map.
  local hood = {}
  for _, d in ipairs(room.doors or {}) do
    local r = by_id[d.to]
    if r and not r.hidden then hood[#hood + 1] = r end
  end
  local lines = {}
  local left = art_rooms
  if #hood > 0 then
    local n = hood[rand:int(#hood)]
    lines[#lines + 1] = "from a room one door from the " .. n.name .. "."
    left = {}
    for _, r in ipairs(art_rooms) do if next_door(r, n) then left[#left + 1] = r end end
  else
    lines[#lines + 1] = "from a room you can find."
  end
  if #left > 1 then
    -- Narrow it: the first letter, or how many works hang there.
    local letter = room.name:sub(1, 1):upper()
    local same, count = 0, 0
    for _, r in ipairs(left) do
      if r.name:sub(1, 1):upper() == letter then same = same + 1 end
      if #r.art == #room.art then count = count + 1 end
    end
    if same <= count then lines[#lines + 1] = "Its name starts with " .. letter .. "."
    else lines[#lines + 1] = #room.art .. (#room.art == 1 and " work hangs" or " works hang") .. " there." end
  end
  local body = (OPENERS[kind] or OPENERS.creep) .. " " .. thing .. ", " .. table.concat(lines, " ")
  return { body = body, sign = caper.NAME[kind] or caper.NAME.creep, room = room.id, kind = kind }
end

return caper
