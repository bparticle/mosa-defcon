-- The janitor's record: the bottles picked up, the works seen, the rooms
-- stamped, the thieves caught.
-- Kept in the app's Solana OS storage (data.json on the microSD card, 16 KB),
-- so it survives relaunches and app updates; uninstalling the app clears it.
--
-- Indices are the APPEND-ONLY registry in mosa.lock.json (piece.idx, room.idx, work.idx),
-- so a record written by an older release still means the same pieces after a
-- data sync adds new ones. The bitsets are stored as hex strings.
local util = require("util")

local record = {}
local KEY = "record"
local SCHEMA = 1

local state = {
  found = {},   -- piece idx → true
  seen = {},    -- work idx → true (looked at on its wall)
  rooms = {},   -- room idx → true (visited)
  goals = {},   -- "roomId/goalId" → true
  pickups = 0,
  caught = 0,
  cleared = 0,  -- nights that ended at dawn with nothing lost
  shifts = 0,
  -- Nights, by the server's day (UTC): the first shift of a day starts its night.
  nights = 0,   -- days worked
  streak = 0,   -- days worked in a row, up to the last one
  best_streak = 0,
  last_day = -1,
  best = 0,     -- most works recovered in one shift
}
record.state = state

local function hex(set)
  local max = -1
  for i in pairs(set) do if i > max then max = i end end
  return util.bits_to_hex(set, max + 1)
end

local function save()
  local goals = {}
  for k in pairs(state.goals) do goals[#goals + 1] = k end
  table.sort(goals)
  storage.set(KEY, {
    v = SCHEMA,
    found = hex(state.found),
    seen = hex(state.seen),
    rooms = hex(state.rooms),
    goals = table.concat(goals, ";"),
    pickups = state.pickups,
    caught = state.caught,
    cleared = state.cleared,
    shifts = state.shifts,
    nights = state.nights,
    streak = state.streak,
    best_streak = state.best_streak,
    last_day = state.last_day,
    best = state.best,
  })
end

function record.load()
  local saved = storage.get(KEY)
  -- Nothing saved yet (or a future schema we do not know): start clean.
  if type(saved) ~= "table" or saved.v ~= SCHEMA then saved = {} end
  state.found = util.bits_from_hex(saved.found or "")
  state.seen = util.bits_from_hex(saved.seen or "")
  state.rooms = util.bits_from_hex(saved.rooms or "")
  state.goals = {}
  for k in tostring(saved.goals or ""):gmatch("[^;]+") do state.goals[k] = true end
  state.pickups = tonumber(saved.pickups) or 0
  state.caught = tonumber(saved.caught) or 0
  state.cleared = tonumber(saved.cleared) or 0
  state.shifts = tonumber(saved.shifts) or 0
  -- Added in 0.6.0: a record from before simply has none of them yet.
  state.nights = tonumber(saved.nights) or 0
  state.streak = tonumber(saved.streak) or 0
  state.best_streak = tonumber(saved.best_streak) or 0
  state.last_day = tonumber(saved.last_day) or -1
  state.best = tonumber(saved.best) or 0
end

--- Returns true when the piece is new to this badge.
function record.find(piece)
  state.pickups = state.pickups + 1
  local new = not state.found[piece.idx]
  state.found[piece.idx] = true
  save()
  return new
end

function record.visit(room)
  if state.rooms[room.idx] then return false end
  state.rooms[room.idx] = true
  save()
  return true
end

--- Returns true when the goal is newly stamped.
function record.stamp(room_id, goal_id)
  local key = room_id .. "/" .. goal_id
  if state.goals[key] then return false end
  state.goals[key] = true
  save()
  return true
end

--- Returns true when the work is new to this badge.
function record.see(work)
  if state.seen[work.idx] then return false end
  state.seen[work.idx] = true
  save()
  return true
end

function record.catch()
  state.caught = state.caught + 1
  save()
end

function record.clear()
  state.cleared = state.cleared + 1
  save()
end

--- A shift begins. `day` is the server's day (nil when the badge has never
--- synced its clock). Returns true when this is the first shift of the day:
--- a new night, which counts toward the streak.
function record.clock_in(day)
  state.shifts = state.shifts + 1
  local first = false
  if day and day ~= state.last_day then
    first = true
    state.nights = state.nights + 1
    state.streak = (state.last_day == day - 1) and state.streak + 1 or 1
    if state.streak > state.best_streak then state.best_streak = state.streak end
    state.last_day = day
  end
  save()
  return first
end

--- Has today's night been worked? (False when the clock is unknown.)
function record.worked(day)
  return day ~= nil and state.last_day == day
end

--- The streak as it stands today: it lapses once a day is missed.
function record.streak_now(day)
  if not day or state.last_day < day - 1 then return 0 end
  return state.streak
end

--- A shift is over: keep the best.
function record.dawn(recovered)
  if recovered > state.best then state.best = recovered end
  save()
end

function record.flush()
  save()
end

function record.found_count()
  return util.count(state.found)
end

function record.seen_count()
  return util.count(state.seen)
end

--- The shift report: a short code the museum can read back (docs/SOLANA.md).
--- Layout, most significant first: 4-bit format (1), 16 bits of rooms by
--- registry index, then one bit per registry piece.
function record.report_code(piece_count)
  local bits = {}
  local function put(v, n) for i = n - 1, 0, -1 do bits[#bits + 1] = (v >> i) & 1 end end
  put(1, 4)
  for i = 0, 15 do bits[#bits + 1] = state.rooms[i] and 1 or 0 end
  for i = 0, piece_count - 1 do bits[#bits + 1] = state.found[i] and 1 or 0 end
  return util.base32(bits)
end

return record
