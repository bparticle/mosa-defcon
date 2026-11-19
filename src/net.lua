-- Other janitors on shift: badge-to-badge presence over the Solana OS mesh.
--
-- No server and no Wi-Fi: every few seconds a badge running Night Shift
-- broadcasts a small message (mesh.send to "*"), and only badges running the
-- same app hear it (on_mesh). It is how two strangers at the conference find
-- out they are both walking MOSA, and it gates the one thing a janitor cannot
-- find alone (see main.lua, "mythical"). Badges bridged through the server
-- count too: Solana OS delivers their messages the same way.
--
-- Messages (≤ 200 bytes as JSON; the mesh takes 4 a second):
--   { p = "<roomId>", f = <found> }   presence
--   { w = "<name>" }                  a wave
local net = { peers = {}, on = false }

local INTERVAL_MS = 2500
local FRESH_MS = 9000
local last = -INTERVAL_MS

local function now() return sys.millis() end

function net.start()
  net.on = mesh ~= nil and mesh.send ~= nil
  return net.on
end

function net.stop()
  net.on = false
end

local function send(msg)
  if not net.on then return false end
  local ok, res = pcall(mesh.send, "*", msg)
  return ok and res ~= nil and res ~= false
end

--- Who this badge is, as other janitors see it.
function net.name()
  local owner = badge and badge.owner and badge.owner()
  if owner and owner ~= "" then return owner end
  local id = badge and badge.id and badge.id()
  return id and ("badge " .. id) or "a janitor"
end

function net.update(room_id, found)
  if not net.on then return end
  local t = now()
  if t - last >= INTERVAL_MS then
    last = t
    send({ p = room_id, f = found })
  end
end

function net.wave()
  return send({ w = net.name():sub(1, 24) })
end

--- Feed from on_mesh. Returns a wave's sender name when one arrives.
function net.receive(from, msg)
  if type(from) ~= "string" or type(msg) ~= "table" then return nil end
  if type(msg.p) == "string" then
    net.peers[from] = { at = now(), room = msg.p, found = tonumber(msg.f) or 0 }
  elseif type(msg.w) == "string" then
    local p = net.peers[from] or { room = "?", found = 0 }
    p.at = now()
    net.peers[from] = p
    return msg.w:sub(1, 24)
  end
  return nil
end

function net.nearby()
  local n, t = 0, now()
  for id, p in pairs(net.peers) do
    if t - p.at <= FRESH_MS then n = n + 1 else net.peers[id] = nil end
  end
  return n
end

return net
