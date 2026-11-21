-- The night: a clock from closing to dawn, and the security desk that sends
-- the break-ins. Pure logic (no drawing), so the tests can run a whole night.
--
-- The clock is in minutes after the evening's midnight - 1, so 23:41 is
-- 1421 and dawn, 06:00 the next morning, is 1800. It runs only while the
-- janitor is out walking (a card or the clipboard holds it), at SPEED game
-- minutes a real second: a night is about eight minutes of play.
--
-- The desk is a small director. The first wave is the footage's three
-- thieves. When a wave is cleared, a calm, then the next: its size and how
-- fast its thieves move follow how quickly the last one was cleared, so a
-- quick janitor meets more and a struggling one gets a breather. A thief who
-- stays at large too long is reported again ("last seen in ...").
local night = {}

night.START = 23 * 60 + 41
night.DAWN = 30 * 60
night.SPEED = (night.DAWN - night.START) / 480
night.TRAVEL = 20   -- minutes a trip on the map costs
night.CALM = 25     -- minutes between a cleared wave and the next break-in
night.SIGHTING = 50 -- real seconds a thief can go unseen before the desk reports them

function night.new()
  return { min = night.START, wave = 0, size = 0, cleared_in = nil, wave_t = 0, calm = nil,
    since_seen = 0, recovered = 0, prevented = 0, lost = 0, waves = 0, lamps = 0 }
end

--- "02:14": the clock as the badge shows it.
function night.clock(min)
  local m = math.floor(min) % (24 * 60)
  return string.format("%02d:%02d", m // 60, m % 60)
end

--- "3H 46M" to dawn (or "DAWN").
function night.to_dawn(min)
  local left = math.max(0, math.ceil(night.DAWN - min))
  if left == 0 then return "DAWN" end
  local h, m = left // 60, left % 60
  return h > 0 and string.format("%dH %02dM", h, m) or string.format("%dM", m)
end

--- How many thieves the next wave brings, and how fast they move (1 is the
--- old pace). `n` is the wave about to start.
function night.next_wave(n, s)
  if s.wave == 0 then return 3, 1 end
  -- Seconds a thief the last wave took to clear: under 30 is quick, over 75 slow.
  local per = (s.cleared_in or 60) / math.max(1, s.size)
  local size = 2
  if per < 30 then size = 3 elseif per > 75 then size = 1 end
  local pace = 1 + 0.08 * (s.wave)
  if per > 75 then pace = pace - 0.12 end
  return size, math.max(0.9, math.min(1.35, pace))
end

--- Advance by dt real seconds of walking. Returns what happened, at most one
--- thing a call: "hour" (the clock struck one; `min` says which), "warning"
--- (an hour to dawn), "dawn", "break-in" (the calm is over: start a wave),
--- or "sighting" (a thief has gone unseen too long).
function night.advance(s, dt, at_large)
  local before = s.min
  s.min = s.min + dt * night.SPEED
  s.wave_t = s.wave_t + dt
  if s.min >= night.DAWN then s.min = night.DAWN; return "dawn" end
  if s.calm and s.min >= s.calm then
    s.calm = nil
    -- Too close to dawn (a trip on the map can jump the clock past the calm).
    if s.min < night.DAWN - 15 then return "break-in" end
  end
  if at_large > 0 then
    s.since_seen = s.since_seen + dt
    if s.since_seen >= night.SIGHTING then s.since_seen = 0; return "sighting" end
  end
  local h0, h1 = math.floor(before / 60), math.floor(s.min / 60)
  if h1 > h0 then return h1 == 29 and "warning" or "hour" end
  return nil
end

--- A wave begins: remember its size, start its stopwatch.
function night.begin_wave(s, size)
  s.wave = s.wave + 1
  s.size = size
  s.wave_t = 0
  s.since_seen = 0
end

--- The last thief of a wave was caught: the calm before the next.
function night.wave_cleared(s)
  s.cleared_in = s.wave_t
  s.waves = s.waves + 1
  if s.min + night.CALM < night.DAWN - 15 then s.calm = s.min + night.CALM end
end

--- "Five hours to dawn": what an hour's chime says.
local WORDS = { "One hour", "Two hours", "Three hours", "Four hours", "Five hours", "Six hours" }
function night.chime(min)
  local left = (night.DAWN - math.floor(min / 60) * 60) // 60
  return (WORDS[left] or (left .. " hours")) .. " to dawn."
end

--- The day a night belongs to (server time, UTC), or nil when the badge has
--- never synced its clock.
function night.day(now)
  if not now then return nil end
  return now // 86400
end

return night
