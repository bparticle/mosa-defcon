-- The janitor's record: what this badge has found, which rooms it has stamped,
-- and its settings. Lives in the badge's per-app key/value store, so it
-- survives reboots and filesystem reflashes.
--
-- Indices are the APPEND-ONLY registry in mosa.lock.json (piece.idx, room.idx),
-- so a record written by an older release still means the same pieces after a
-- data sync adds new ones. Keys are at most 8 characters (NVS limit).
local util = require("util")

local record = {}
local kv = badge.storage.kv
local SCHEMA = "1"

local state = {
  found = {},   -- piece idx → true
  rooms = {},   -- room idx → true (visited)
  goals = {},   -- "roomId/goalId" → true
  pickups = 0,
  pops = 0,
  shifts = 0,
  mic = true,
}
record.state = state

local function getn(key)
  return tonumber(kv.get(key, "0")) or 0
end

function record.load()
  if kv.get("v", "") ~= SCHEMA then
    -- First run (or a future schema we do not know): start clean, keep nothing
    -- we cannot read.
    kv.set("v", SCHEMA)
  end
  state.found = util.bits_from_hex(kv.get("found", ""))
  state.rooms = util.bits_from_hex(kv.get("rooms", ""))
  state.goals = {}
  for g in (kv.get("goals", "")):gmatch("[^;]+") do state.goals[g] = true end
  state.pickups = getn("pickups")
  state.pops = getn("pops")
  state.shifts = getn("shifts")
  state.mic = kv.get("mic", "1") == "1"
end

local function save_bits(key, set)
  local max = -1
  for i in pairs(set) do if i > max then max = i end end
  kv.set(key, util.bits_to_hex(set, max + 1))
end

--- Returns true when the piece is new to this badge.
function record.find(piece)
  state.pickups = state.pickups + 1
  kv.set("pickups", tostring(state.pickups))
  if state.found[piece.idx] then return false end
  state.found[piece.idx] = true
  save_bits("found", state.found)
  return true
end

function record.visit(room)
  if state.rooms[room.idx] then return false end
  state.rooms[room.idx] = true
  save_bits("rooms", state.rooms)
  return true
end

--- Returns true when the goal is newly stamped.
function record.stamp(room_id, goal_id)
  local key = room_id .. "/" .. goal_id
  if state.goals[key] then return false end
  state.goals[key] = true
  local list = {}
  for k in pairs(state.goals) do list[#list + 1] = k end
  table.sort(list)
  kv.set("goals", table.concat(list, ";"))
  return true
end

function record.pop()
  state.pops = state.pops + 1
  -- Written lazily: a balloon is cheap, NVS writes are not.
  if state.pops % 5 == 0 then kv.set("pops", tostring(state.pops)) end
end

function record.clock_in()
  state.shifts = state.shifts + 1
  kv.set("shifts", tostring(state.shifts))
end

function record.set_mic(on)
  state.mic = on
  kv.set("mic", on and "1" or "0")
end

function record.flush()
  kv.set("pops", tostring(state.pops))
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
