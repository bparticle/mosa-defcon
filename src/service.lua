-- The security desk, while the app is closed (a Solana OS background
-- service, permission "background"). Once a day, in the evening, if
-- tonight's shift hasn't been worked, it calls: one notice, then quiet until
-- tomorrow. The app tells it a night was worked through storage ("desk").
--
-- It runs in a Lua state of its own with a tick a second; it looks at the
-- clock every five minutes and does nothing else, so it costs next to nothing.
local CALL_AT = 18 * 3600 -- seconds into the (UTC) day: early evening at Breakpoint
local LOOK = 300000       -- ms between looks
local wait = 0

function on_tick(ms)
  wait = wait - ms
  if wait > 0 then return end
  wait = LOOK
  local now = sys.time()
  if not now then return end
  local day, sec = now // 86400, now % 86400
  if sec < CALL_AT then return end
  local desk = storage.get("desk")
  if type(desk) ~= "table" then desk = {} end
  if desk.worked == day or desk.called == day then return end
  if service.notify("Break-in at the museum. Three works are missing.", { led = 0x7EE8A8 }) then
    desk.called = day
    storage.set("desk", desk)
    service.status("Called for tonight")
  end
end
