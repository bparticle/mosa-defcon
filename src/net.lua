-- Other janitors on shift: badge-to-badge presence over ESP-NOW.
--
-- No access point, no server. Every few seconds a badge running Night Shift
-- broadcasts one short line; any other within radio range hears it. It is how
-- two strangers at DEF CON find out they are both walking MOSA, and it gates
-- the one thing a janitor cannot find alone (see main.lua, "mythical").
--
-- Wire format (ASCII, well under the 240-byte payload):
--   MOSA1 P <roomId> <found>     presence
--   MOSA1 W <name>               a wave
local net = { peers = {}, on = false, waves = {} }

local PREFIX = "MOSA1 "
local INTERVAL_MS = 2500
local FRESH_MS = 9000
local last = -INTERVAL_MS

function net.start()
  local ok, res = pcall(badge.espnow.enable, true)
  net.on = ok and res ~= false
  return net.on
end

function net.stop()
  if net.on then pcall(badge.espnow.enable, false) end
  net.on = false
end

local function send(line)
  if not net.on then return false end
  local ok = pcall(badge.espnow.broadcast, PREFIX .. line)
  return ok
end

function net.update(room_id, found)
  if not net.on then return end
  local now = badge.millis()
  if now - last >= INTERVAL_MS then
    last = now
    send("P " .. room_id .. " " .. tostring(found))
  end
end

function net.wave(name)
  return send("W " .. tostring(name):gsub("%s", "_"):sub(1, 23))
end

--- Feed from on_espnow. Returns a wave's sender name when one arrives.
function net.receive(mac, data)
  if type(data) ~= "string" or data:sub(1, #PREFIX) ~= PREFIX then return nil end
  local kind, a, b = data:sub(#PREFIX + 1):match("^(%a) (%S+) ?(%S*)")
  if kind == "P" then
    net.peers[mac] = { at = badge.millis(), room = a, found = tonumber(b) or 0 }
  elseif kind == "W" then
    net.peers[mac] = net.peers[mac] or { at = badge.millis(), room = "?", found = 0 }
    net.peers[mac].at = badge.millis()
    return (a:gsub("_", " "))
  end
  return nil
end

function net.nearby()
  local n, now = 0, badge.millis()
  for mac, p in pairs(net.peers) do
    if now - p.at <= FRESH_MS then n = n + 1 else net.peers[mac] = nil end
  end
  return n
end

return net
