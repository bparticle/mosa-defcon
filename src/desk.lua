-- The security desk's paperwork: the dawn report that ends a shift, and the
-- how-to-play pages. main.lua hands them what they need through
-- `desk.scenes(ctx)`, so they don't count against main.lua's 64 KB.
local g = require("gfx")
local ui = require("kit")
local sprites = require("sprites")
local night = require("night")
local record = require("record")

local desk = {}

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

function desk.scenes(ctx)
  local Dawn, HowTo = { name = "dawn" }, { name = "howto", static = true }
  local DATA = ctx.DATA

  -- ── dawn: the shift report ─────────────────────────────────────────────────
  -- The lights come up on what the night came to: the works back on their
  -- walls, any that left with the light, the streak, and what is still out
  -- there to find. `out` is true when the janitor clocked out early.
  Dawn.__index = Dawn
  function Dawn.new(game, out)
    local s = setmetatable({ game = game, out = out, t = 0, n = game.night }, Dawn)
    local st = record.state
    local works, bottles, rooms = 0, 0, 0
    for _, w in ipairs(DATA.works) do if not st.seen[w.idx] then works = works + 1 end end
    for _, p in ipairs(DATA.pieces) do if not st.found[p.idx] then bottles = bottles + 1 end end
    for _, r in ipairs(DATA.rooms) do if not st.rooms[r.idx] then rooms = rooms + 1 end end
    s.left = { works = works, bottles = bottles, rooms = rooms }
    s.streak = record.streak_now(game.day)
    return s
  end
  function Dawn:update(dt) self.t = self.t + dt end
  function Dawn:draw()
    local T, n, game = self.t, self.n, self.game
    g.clear(ui.BG)
    local up = math.min(1, T / 0.8)
    ui.concrete(0, 0, ui.W, math.floor(84 * (1 - (1 - up) ^ 3)))
    g.fill_rect(0, 84, ui.W, 2, ui.INK)
    if T > 0.4 then
      ui.tracked(self.out and ("CLOCKED OUT AT " .. night.clock(n.min)) or "06:00  THE LIGHTS COME UP", 16, 12, ui.MUTED, 1, 2)
      if self.out then
        ui.tracked("SHIFT", 16, 34, ui.INK, 3, 4)
        ui.tracked("OVER", 16, 58, ui.INK, 2, 4)
      else
        ui.block("DAWN", 16, 30, 5, ui.INK, ui.SHADOW)
      end
    end
    local rows = {}
    rows[#rows + 1] = { plural(n.recovered, "work") .. " back on " .. (n.recovered == 1 and "its wall" or "their walls"), ui.INK }
    if n.lost > 0 then rows[#rows + 1] = { plural(n.lost, "thie" .. (n.lost == 1 and "f" or "ve")) .. " left with the light", ui.MUTED }
    elseif n.recovered > 0 then rows[#rows + 1] = { "Nothing lost tonight", ui.ACCENT } end
    rows[#rows + 1] = { plural(game.tonight.seen, "new work") .. " seen, " .. plural(game.tonight.bottles, "bottle") .. " picked up", ui.MUTED }
    local st = record.state
    if self.streak > 1 then rows[#rows + 1] = { "Night " .. st.nights .. ", " .. self.streak .. " in a row. Best: " .. st.best, ui.MUTED }
    elseif st.nights > 0 then rows[#rows + 1] = { "Night " .. st.nights .. ". Best: " .. plural(st.best, "work"), ui.MUTED } end
    if n.lamps > 0 then rows[#rows + 1] = { "+" .. n.lamps .. " !LAMPs earned", ui.INK }
    elseif ctx.needs_x() then rows[#rows + 1] = { "Link X on the badge site to earn !LAMPs", ui.DIM } end
    for i, r in ipairs(rows) do
      if T > 0.9 + i * 0.2 then g.text(r[1], 16, 84 + i * 13, r[2]) end
    end
    -- Tonight's recoveries, back where they belong.
    local x = 304
    for i = #game.plan, 1, -1 do
      local h = game.plan[i]
      local w = h.back and ctx.works_by_idx[h.work]
      if w and x > 214 and T > 0.6 + i * 0.1 then
        x = x - 30
        ui.mat(w, x, 92, 26, 26)
      end
    end
    if T > 2.2 then
      local l = self.left
      local still = "Still out there: " .. plural(l.bottles, "bottle") .. ", " .. plural(l.works, "work") .. ", " .. plural(l.rooms, "room") .. "."
      if l.bottles + l.works + l.rooms == 0 then still = "You have found everything. The thieves haven't stopped." end
      ui.paragraph(still .. " A new night comes every day.", 16, 170, 288, ui.MUTED, 1, 10)
    end
    if T > 2.6 then ui.hints({ "a", "shift report", "b", "clock out" }) end
  end
  function Dawn:button(key)
    if self.t < 1 then return end
    if key == "a" then ctx.push(ctx.report_code())
    elseif key == "b" then ctx.pop(); ctx.pop() end
  end

  -- ── how to play ────────────────────────────────────────────────────────────
  -- Four pages, a picture and a paragraph each. LEFT and RIGHT turn them.
  HowTo.__index = HowTo
  local PAGES = {
    { "THE NIGHT", "Thieves break in after closing. Your shift runs from 23:41 to dawn: recover every work you can before 06:00, when the ones still inside leave with the light. The clipboard (CANCEL) stops the clock." },
    { "THE LIGHT", "An empty frame shows what was taken. Find the thief in the dark and hold your flashlight on them until they drop the work. Too slow, or too loud, and they run for a door." },
    { "THE DESK", "Clear a break-in and the desk radios the next. It reads how you're doing: a quick janitor gets more thieves, a struggling one a breather and a sighting." },
    { "TRAVEL", "The map takes you to any room you've walked before, in a blink. Each trip costs twenty minutes of the night. Doors are free." },
    { "EVERY NIGHT", "A new night every day: keep a streak, find every bottle and every work, and earn !LAMPs for what you recover (link X on the badge site)." },
  }
  function HowTo.new() return setmetatable({ page = 1 }, HowTo) end
  local function picture(page)
    local cx, cy = 160, 76
    if page == 1 then
      g.text("23:41", 60, cy - 12, ui.MUTED, 3)
      g.text(">", 152, cy - 12, ui.DIM, 3)
      g.text("06:00", 180, cy - 12, ui.INK, 3)
      g.fill_rect(60, cy + 16, 200, 2, ui.DIM)
      g.fill_rect(60, cy + 16, 70, 2, ui.INK)
    elseif page == 2 then
      sprites.draw("janitor", "right", 0, 96, cy + 22, 2)
      for i = 0, 70 do
        local half = math.floor(i * 0.45)
        g.fill_rect(112 + i, cy - half, 1, half * 2 + 1, g.color(96, 93, 88))
      end
      sprites.draw("thief", "left", 0, 190, cy + 22, 2)
      g.fill_rect(178, cy - 22, 24, 4, ui.DIM)
      g.fill_rect(178, cy - 22, 15, 4, ui.INK)
      g.rect(236, cy - 18, 26, 32, ui.CAST)
      g.rect(240, cy - 14, 18, 24, ui.DIM)
    elseif page == 3 then
      g.fill_rect(70, cy - 26, 180, 52, ui.PAPER)
      ui.tracked("CAM 07  BREAK-IN", 80, cy - 18, ui.PAPER_INK, 1, 2)
      g.text("Someone at a wall in", 80, cy - 2, ui.MUTED)
      g.text("the Red Room.", 80, cy + 9, ui.MUTED)
      g.fill_rect(70, cy - 26, 3, 52, ui.PAPER_INK)
    elseif page == 4 then
      local m = DATA.map
      local k = math.min(220 / m.w, 80 / m.h)
      local ox, oy = cx - math.floor(m.w * k / 2), cy - math.floor(m.h * k / 2)
      for i, r in ipairs(DATA.rooms) do
        if not r.hidden then
          local p = r.plan[1]
          local on = i == 1 or i == 3
          g.rect(ox + math.floor(p[1] * k), oy + math.floor(p[2] * k), math.max(2, math.floor(p[3] * k)), math.max(2, math.floor(p[4] * k)), on and ui.INK or ui.DIM)
        end
      end
      ui.tracked("20 MIN", cx - 20, cy + 34, ui.ACCENT, 1, 2)
    else
      local x = 70
      for i = 1, math.min(8, #DATA.pieces) do
        local p = DATA.pieces[i]
        local have = record.state.found[p.idx]
        ui.thumb(p, x, cy - 20, 1, not have and ui.DIM or nil)
        x = x + 23
      end
      ui.tracked("!LAMPS", cx - 22, cy + 20, ui.INK, 1, 2)
    end
  end
  function HowTo:draw()
    g.clear(ui.BG)
    ui.header("HOW TO PLAY", self.page .. " / " .. #PAGES)
    picture(self.page)
    local p = PAGES[self.page]
    ui.tracked(p[1], 16, 122, ui.INK, 1, 3)
    ui.paragraph(p[2], 16, 138, 288, ui.MUTED, 1, 11)
    ui.hints({ "d-pad", "turn the page", "b", "back" })
  end
  function HowTo:button(key)
    if key == "b" then ctx.pop(); return end
    local n = #PAGES
    if key == "right" or key == "down" or key == "a" then self.page = self.page % n + 1
    elseif key == "left" or key == "up" then self.page = (self.page - 2) % n + 1 end
    ctx.invalidate()
  end

  return Dawn, HowTo
end

return desk
