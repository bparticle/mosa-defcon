-- The janitor's record: what this badge has found, which rooms it has stamped.
-- Kept in the app's Solana OS storage (data.json on the microSD card, 16 KB),
-- so it survives relaunches and app updates; uninstalling the app clears it.
--
-- Indices are the APPEND-ONLY registry in mosa.lock.json (piece.idx, room.idx),
-- so a record written by an older release still means the same pieces after a
-- data sync adds new ones. The bitsets are stored as hex strings.
local util = require("util")

local record = {}
local KEY = "record"
local SCHEMA = 1

local state = {
  found = {},   -- piece idx → true
  rooms = {},   -- room idx → true (visited)
  goals = {},   -- "roomId/goalId" → true
  pickups = 0,
  pops = 0,
  shifts = 0,
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
    rooms = hex(state.rooms),
    goals = table.concat(goals, ";"),
    pickups = state.pickups,
    pops = state.pops,
    shifts = state.shifts,
  })
end

function record.load()
  local saved = storage.get(KEY)
  -- Nothing saved yet (or a future schema we do not know): start clean.
  if type(saved) ~= "table" or saved.v ~= SCHEMA then saved = {} end
  state.found = util.bits_from_hex(saved.found or "")
  state.rooms = util.bits_from_hex(saved.rooms or "")
  state.goals = {}
  for k in tostring(saved.goals or ""):gmatch("[^;]+") do state.goals[k] = true end
  state.pickups = tonumber(saved.pickups) or 0
  state.pops = tonumber(saved.pops) or 0
  state.shifts = tonumber(saved.shifts) or 0
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

function record.pop()
  state.pops = state.pops + 1
  -- Written lazily: a balloon is cheap, a write to the card is not.
  if state.pops % 5 == 0 then save() end
end

function record.clock_in()
  state.shifts = state.shifts + 1
  save()
end

function record.flush()
  save()
end

function record.found_count()
  return util.count(state.found)
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
