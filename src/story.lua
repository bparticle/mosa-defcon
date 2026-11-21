-- The story scenes: the janitor's cupboard (the intro) and tonight's briefing,
-- played back as security-camera footage of a thief lifting a work off its
-- wall. main.lua hands them what they need through `story.scenes(ctx)`, so they
-- don't count against main.lua's 64 KB.
local g = require("gfx")
local ui = require("kit")
local sprites = require("sprites")
local light = require("light")

local story = {}

function story.scenes(ctx)
  local Intro, Briefing = { name = "intro" }, { name = "briefing" }

  -- ── the intro: the janitor's cupboard ─────────────────────────────────────
  -- The janitor walks in, takes the flashlight off its hook, and clicks it on.
  -- The bulb goes out and the night begins. Any button skips it.
  Intro.__index = Intro
  function Intro.new() return setmetatable({ t = 0 }, Intro) end
  local WALK_IN, TURN, TAKE, CLICK, DONE = 1.5, 1.7, 2.3, 2.9, 6.2
  local HOOK_X, FLOOR_Y = 190, 178
  function Intro:update(dt)
    local before = self.t
    self.t = self.t + dt
    if before < CLICK and self.t >= CLICK then ctx.flash(sprites.LENS, 0.25) end
    if self.t >= DONE then self:button() end
  end
  -- After the click: only what the beam touches, the wall and floor pale in it.
  local BEAM_WALL, BEAM_MARK, BEAM_FLOOR = g.color(168, 164, 156), g.color(140, 137, 130), g.color(104, 100, 94)
  function Intro:dark(T, jx, lx, ly)
    local a = math.sin((T - CLICK) * 1.3) * 0.2
    local L = light.new(lx + 16, ly + 3, math.cos(a), math.sin(a), 240, 0.3, jx, FLOOR_Y - 22, 36)
    for y = math.max(0, L.top), math.min(ui.H - 1, L.bottom) do
      local a1, b1, a2, b2 = light.row(L, y)
      local col = y < FLOOR_Y - 20 and ((y % 7 == 6) and BEAM_MARK or BEAM_WALL) or BEAM_FLOOR
      if a1 then g.fill_rect(a1, y, b1 - a1 + 1, 1, col) end
      if a2 then g.fill_rect(a2, y, b2 - a2 + 1, 1, col) end
    end
    if light.lit(L, 262, 140) then
      g.line(268, 66, 262, 150, ui.PAPER_INK)
      g.fill_rect(250, 140, 26, 18, g.color(58, 56, 52))
    end
    if light.lit(L, 160, 51) then
      g.fill_rect(118, 44, 84, 14, ui.PAPER)
      ui.tracked("STAFF ONLY", 124, 47, ui.PAPER_INK, 1, 2)
    end
  end

  function Intro:draw()
    local T = self.t
    g.clear(ui.BG)
    local x = math.min(1, T / WALK_IN)
    local jx = math.floor(-20 + (HOOK_X - 10 + 20) * x)
    local lx, ly = jx + 12, FLOOR_Y - 18
    if T >= CLICK then
      self:dark(T, jx, lx, ly)
      sprites.draw("janitor", "right", 0, jx, FLOOR_Y, 3)
      g.fill_rect(lx, ly, 14, 6, sprites.TORCH)
      g.fill_rect(lx + 14, ly - 1, 3, 8, sprites.LENS)
      if T > CLICK + 0.8 then ui.tracked("23:58. THE MUSEUM IS CLOSED.", 16, 192, ui.MUTED, 1, 1) end
      if T > CLICK + 1.8 then ui.tracked("BUT IT IS NOT EMPTY.", 16, 204, ui.INK, 1, 1) end
      return
    end
    -- The cupboard: a concrete wall, a lino floor, a bulb, a locker, a mop.
    ui.concrete(0, 0, ui.W, FLOOR_Y - 20)
    g.fill_rect(0, FLOOR_Y - 20, ui.W, ui.H - FLOOR_Y + 20, g.color(26, 25, 24))
    for xx = 0, ui.W, 24 do g.line(xx, FLOOR_Y - 20, xx - 30, ui.H, g.color(34, 33, 31)) end
    g.fill_rect(0, FLOOR_Y - 21, ui.W, 2, ui.SHADOW)
    g.line(160, 0, 160, 18, ui.DIM)
    g.fill_circle(160, 23, 5, T < CLICK and g.color(255, 244, 210) or ui.DIM)
    ui.slab(28, 58, 44, 100, ui.DIM, 3)
    for y = 66, 84, 4 do g.line(36, y, 64, y, ui.CONC) end
    g.fill_rect(64, 104, 3, 10, ui.MUTED)
    g.line(268, 66, 262, 150, ui.MUTED)
    g.fill_rect(250, 140, 26, 18, g.color(74, 72, 68))
    g.fill_rect(252, 136, 22, 4, g.color(96, 94, 88))
    -- A plate on the wall, and the hook with the flashlight on it.
    g.fill_rect(118, 44, 84, 14, ui.PAPER)
    ui.tracked("STAFF ONLY", 124, 47, ui.PAPER_INK, 1, 2)
    g.fill_rect(HOOK_X - 2, 92, 5, 3, ui.MUTED)
    if T < TAKE then
      g.fill_rect(HOOK_X - 3, 95, 7, 20, sprites.TORCH)
      g.fill_rect(HOOK_X - 4, 115, 9, 4, sprites.TORCH)
      g.fill_rect(HOOK_X - 3, 119, 7, 2, sprites.LENS)
    end
    -- The janitor: in, up to the hook, and the flashlight comes down.
    local face, step = "right", 0
    if T < WALK_IN then step = (math.floor(T * 6) % 2 == 0) and 1 or 0
    elseif T < TAKE then face = "up" end
    sprites.draw("janitor", face, step, jx, FLOOR_Y, 3)
    if T >= TAKE then
      g.fill_rect(lx, ly, 14, 6, sprites.TORCH)
      g.fill_rect(lx + 14, ly - 1, 3, 8, ui.MUTED)
    elseif T >= TURN then
      -- Reaching up for it.
      g.fill_rect(jx + 6, FLOOR_Y - 66, 6, 22, g.color(216, 212, 202))
      g.fill_rect(jx + 6, FLOOR_Y - 72, 6, 6, g.color(226, 182, 142))
    end
    if T < 0.6 then ui.tracked_center("NIGHT SHIFT", 160, 200, ui.INK, 1, 3) end
  end
  function Intro:button()
    if ctx.top() ~= self then return end
    ctx.pop()
    ctx.push(Briefing.new(ctx.plan_heist()))
  end

  -- ── the briefing: the footage ─────────────────────────────────────────────
  -- A security camera in the first room on tonight's list. A work hangs in a
  -- pool of light; a thief creeps in, lifts it, glances at the camera, and
  -- runs. Then tonight's list: every stolen work, and the room it was taken
  -- from. A press fast-forwards the tape; the next one starts the shift.
  Briefing.__index = Briefing
  local SX, SY, SW, SH = 8, 6, 304, 96    -- the monitor
  local WALL_B, FEET = 82, 98             -- the wall's foot, the thief's feet
  local FX, FY = 160, 18                  -- the frame's top centre
  local SNEAK_IN, REACH, LIFT, LOOK, RUN, GONE, LIST = 0.5, 2.0, 2.5, 2.7, 3.2, 4.0, 4.2
  local POOL = g.color(54, 53, 50)
  local FLOOR_C, FLOOR_L = g.color(22, 22, 21), g.color(30, 29, 28)
  local SCAN = g.color(0, 0, 0)
  local SKIN, SLEEVE = g.color(226, 182, 142), g.color(40, 40, 46)

  function Briefing.new(plan)
    local s = setmetatable({ plan = plan, t = 0, shown = 0, fresh = true }, Briefing)
    local first = plan[1]
    s.work = first and ctx.works_by_idx[first.work]
    s.room = first and ctx.rooms_by_id[first.room]
    if not s.work then s.t = LIST end
    return s
  end
  function Briefing:enter() self.shown, self.fresh = 0, true end
  Briefing.resume = Briefing.enter

  function Briefing:update(dt) self.t = self.t + dt end

  --- Where the thief stands at time T, which way they face, and their stride.
  local function thief_at(T)
    if T < SNEAK_IN then return nil end
    if T < REACH then
      local k = (T - SNEAK_IN) / (REACH - SNEAK_IN)
      return math.floor(-20 + (FX - 14 + 20) * k), "right", (math.floor(T * 5) % 2 == 0) and 1 or 2
    end
    if T < LOOK then return FX - 14, "up", 0 end
    if T < RUN then return FX - 14, "down", 0 end
    if T < GONE then
      local k = (T - RUN) / (GONE - RUN)
      return math.floor(FX - 14 + (SX + SW + 30 - FX + 14) * k * k), "right", (math.floor(T * 10) % 2 == 0) and 1 or 2
    end
    return nil
  end

  function Briefing:monitor(T)
    local work = self.work
    -- The wall, the pool of light on it, the floor.
    ui.concrete(SX, SY, SW, WALL_B - SY)
    for y = SY + 4, WALL_B - 1, 2 do
      local hw = 24 + (y - SY) * 2 // 5
      g.fill_rect(FX - hw, y, hw * 2, 2, POOL)
    end
    g.fill_rect(SX, WALL_B, SW, SY + SH - WALL_B, FLOOR_C)
    g.fill_rect(SX, WALL_B, SW, 1, ui.SHADOW)
    for x = SX + 10, SX + SW, 26 do g.line(x, WALL_B + 1, x - 12, SY + SH - 1, FLOOR_L) end
    g.fill_rect(FX - 34, WALL_B + 2, 68, 6, POOL)
    -- The work, or the frame it left behind.
    local pw, ph = ui.size(work)
    local k = math.max(1, math.min(48 // pw, 48 // ph))
    local fw, fh = pw * k + 6, ph * k + 6
    local fx, fy = FX - fw // 2, FY
    g.fill_rect(FX - 1, fy - 4, 2, 3, ui.MUTED)
    local x, face, step = thief_at(T)
    if T < LIFT then
      g.fill_rect(fx, fy, fw, fh, ui.PAPER)
      ui.thumb(work, fx + 3, fy + 3, k)
    else
      g.rect(fx, fy, fw, fh, ui.MUTED)
      g.rect(fx + 1, fy + 1, fw - 2, fh - 2, g.color(42, 41, 39))
    end
    g.fill_rect(FX - 10, fy + fh + 4, 20, 5, ui.CAST)
    if x then
      if T >= REACH and T < LIFT then
        -- Reaching up: two sleeves to the frame.
        g.fill_rect(x - 9, FEET - 72, 5, 26, SLEEVE); g.fill_rect(x + 4, FEET - 72, 5, 26, SLEEVE)
        g.fill_rect(x - 9, FEET - 76, 5, 4, SKIN); g.fill_rect(x + 4, FEET - 76, 5, 4, SKIN)
      end
      sprites.draw("thief", face, step, x, FEET, 3)
      if T >= LIFT then
        -- The loot, under an arm, frame and all.
        local lx = x + (face == "right" and 6 or -2)
        local lk = math.max(1, k // 2)
        g.fill_rect(lx, FEET - 40, pw * lk + 4, ph * lk + 4, ui.PAPER)
        ui.thumb(work, lx + 2, FEET - 38, lk)
      end
      if face == "down" then
        -- A glance at the camera.
        g.fill_rect(x - 5, FEET - 37, 3, 3, ui.INK); g.fill_rect(x + 3, FEET - 37, 3, 3, ui.INK)
      end
    end
    -- Nothing outside the picture: a thief walks in from off camera.
    g.fill_rect(0, SY, SX, SH, ui.BG); g.fill_rect(SX + SW, SY, ui.W - SX - SW, SH, ui.BG)
    -- The camera's own marks: scanlines (never across the work: it stays
    -- crisp), corner brackets, a clock, REC.
    local hung = T < LIFT
    for y = SY + 1, SY + SH - 1, 3 do
      if hung and y >= fy and y < fy + fh then
        g.fill_rect(SX, y, fx - SX, 1, SCAN); g.fill_rect(fx + fw, y, SX + SW - fx - fw, 1, SCAN)
      else g.fill_rect(SX, y, SW, 1, SCAN) end
    end
    local c = ui.INK
    for _, p in ipairs({ { SX + 4, SY + 4, 1, 1 }, { SX + SW - 5, SY + 4, -1, 1 }, { SX + 4, SY + SH - 5, 1, -1 }, { SX + SW - 5, SY + SH - 5, -1, -1 } }) do
      g.fill_rect(math.min(p[1], p[1] + p[3] * 9), p[2], 10, 1, c)
      g.fill_rect(p[1], math.min(p[2], p[2] + p[4] * 9), 1, 10, c)
    end
    local cam = "CAM " .. string.format("%02d", (self.room and self.room.idx or 0) + 1)
    g.text(cam .. "  " .. ui.fit((self.room and self.room.name or ""):upper(), 180), SX + 10, SY + 8, c)
    if math.floor(T * 2) % 2 == 0 then g.fill_circle(SX + SW - 34, SY + 11, 3, c) end
    g.text("REC", SX + SW - 28, SY + 8, c)
    g.text_right(string.format("23:41:%02d", math.floor(T * 3) % 60), SX + SW - 10, SY + SH - 14, c)
  end

  --- Tonight's list, under the monitor, one piece at a time.
  function Briefing:list(T)
    local plan, n = self.plan, #self.plan
    local stage = T < LIST and 0 or math.min(n + 2, 1 + math.floor((T - LIST) / 0.22))
    if stage == self.shown then return end
    self.shown = stage
    g.fill_rect(0, SY + SH + 2, ui.W, ui.H - SY - SH - 2, ui.BG)
    if stage == 0 then return end
    if n == 0 then
      ui.tracked_center("A QUIET NIGHT", 160, 130, ui.INK, 2, 3)
      g.text_center("Walk the rooms. Look at the art.", 160, 160, ui.MUTED)
    else
      local word = n == 1 and "ONE WORK STOLEN" or ((n == 2 and "TWO" or (n == 3 and "THREE" or tostring(n))) .. " WORKS STOLEN")
      ui.tracked_center(word, 160, SY + SH + 8, ui.INK, 1, 3)
      local cw = math.min(96, 304 // n)
      local x0 = (ui.W - cw * n) // 2
      for i, h in ipairs(plan) do
        if stage > i then
          local w, r = ctx.works_by_idx[h.work], ctx.rooms_by_id[h.room]
          local x = x0 + (i - 1) * cw
          if w then ui.mat(w, x + (cw - 44) // 2, 120, 44, 44) end
          g.text_center(ui.fit((r and r.name or "?"):upper(), cw - 6), x + cw // 2, 168, ui.MUTED)
        end
      end
      if stage > n then
        -- Tonight's weather, when it isn't a clear night.
        local w = ctx.weather and ctx.weather()
        if w and w.id ~= "clear" then
          ui.tracked_center("TONIGHT, " .. w.name, 160, 180, ui.INK, 1, 2)
          g.text_center(w.line, 160, 192, ui.MUTED)
        else g.text_center("Find them in the dark. Hold your light on them.", 160, 184, ui.INK) end
      end
    end
    if stage > n then ui.hints({ "a", "start the shift", "b", "not tonight" }) end
  end

  function Briefing:draw()
    local T = self.t
    if self.fresh then self.fresh = false; g.clear(ui.BG) end
    if self.work then self:monitor(math.min(T, GONE + 0.01)) else
      g.fill_rect(SX, SY, SW, SH, ui.CONC)
    end
    g.rect(SX - 2, SY - 2, SW + 4, SH + 4, ui.DIM)
    self:list(T)
  end

  function Briefing:button(key)
    if key == "b" then ctx.pop(); return end
    if key ~= "a" then return end
    if self.t < LIST + 0.22 * (#self.plan + 2) then
      -- Fast-forward the tape: straight to the list, all of it.
      self.t = LIST + 0.22 * (#self.plan + 2)
      self.shown = -1
      return
    end
    local plan = self.plan
    ctx.pop()
    ctx.start(plan)
  end

  return Intro, Briefing
end

return story
