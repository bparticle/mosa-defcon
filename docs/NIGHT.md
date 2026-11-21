# The night

Night Shift used to end when the third thief was caught. Now a shift is a
night, with a clock, a desk that keeps sending work, and a dawn that closes
it. This page says how it works and where to tune it. The logic is in
`src/night.lua` (pure, no drawing); `src/main.lua` acts on what it returns,
and `src/desk.lua` draws the dawn report and the how-to-play pages.

## The clock

The shift runs from **23:41** to **06:00**. The clock moves only while the
janitor is out walking: a card or the clipboard holds it. At `SPEED` game
minutes a real second, a full night is about **eight minutes** of play.
Every hour chimes ("Four hours to dawn."), and 05:00 warns that the thieves
leave with the light.

The clipboard shows the time and how long to dawn. There's no permanent clock
on screen (MOSA's rule: no HUD counters).

## Travel costs time

Teleporting made the game too easy; without it, it was too hard. The balance:

- The map travels only to rooms **you've walked before** (a room you haven't
  says WALK THERE FIRST).
- Each trip costs **20 minutes** of the night (`TRAVEL`). Doors are free.

So travel is something you spend: a long walk back across the museum is
worth a trip, but hopping room to room burns the night.

## The desk: waves

The first wave is tonight's footage: three thieves, the first one door from
the start. On the day's first shift it is seeded by the date, so every
janitor meets the same break-in that day; later shifts are fresh.

When the last thief of a wave is caught: **ALL CLEAR, FOR NOW**, then a calm
of `CALM` (25) minutes, then the desk radios the next break-in ("CAM 07
BREAK-IN, someone at a wall in the Red Room"). The rooms it names blink on
the map. No break-in starts within 15 minutes of dawn.

The desk is a small director (`night.next_wave`). It reads how many real
seconds each thief of the last wave took:

| Seconds a thief | Next wave | Pace |
| --- | --- | --- |
| under 30 (quick) | 3 thieves | rises 0.08 a wave |
| 30 to 75 | 2 | rises 0.08 a wave |
| over 75 (slow) | 1 | 0.12 slower |

Pace scales how fast a thief creeps, clamped to 0.9–1.35. A janitor on a
roll meets more and quicker thieves; one who's struggling gets a breather.
A thief who goes `SIGHTING` (50) real seconds without being lit is reported
again ("last seen in ..."), so nobody wanders lost for long.

## The thieves

Each thief is one of four kinds (`caper.kind`), one rule each in
`Room:update_thief` (`world.lua`). The night's first thief is always a creep,
so a new janitor learns the light on them; later waves bring more swindlers.

| Kind | In the light | The way to catch them |
| --- | --- | --- |
| Creep | Dazzled, makes for a door | Hold the beam on them |
| Statue | Freezes after `POSE` (0.45 s) and poses on a plinth; never runs | Only a fresh look heats them: look away, then back |
| Dodger | Weaves across the beam at `DODGE`, switching side every `ZIG` | Back them into a wall |
| Swindler | The first time the bar fills, drops a dummy and bolts for `BOLT` | Keep the light on them; the second time is real |

Walking into a room with a thief, the toast says what kind ("Something in
here is standing very still."). A thief who gets away with the bar over 60%
full gets SO CLOSE.

## The weather

Every day has a night of its own (`caper.night(day)`), the same for every
janitor: the title's desk board ("TONIGHT: A STORM") and the briefing say it.

| Night | What it does |
| --- | --- |
| A clear night | Nothing |
| A storm | Every 7 to 16 s, lightning: for a blink every thief in the room shows |
| A full moon | Thieves 0.12 quicker, and footsteps carry 60% as far |
| No moon | No eyes glint in the dark; the LEDs still sweep near a thief |
| A gala | One more thief in the first break-in |

## Calling cards and the holding cell

When a wave is cleared, the next one is planned straight away
(`Game:cleared`), so one of the caught can leave a card for it. The holding
cell plays first: CAM 00, this wave's thieves walking into the cell with
everyone caught earlier, the bars coming down, and a card flicked at the
camera. The card (`caper.card`) is written from the synced data only: what
they're after (its set, its artist's initials, the first letter of its title
or its colour) and where (a neighbouring room on the map, then the first
letter of the room's name or how many works hang there, whichever narrows the
rooms with art down further).

With a card out, the calm is at least `caper.CALM` (40) minutes, enough for a
trip on the map. The clipboard keeps the card. When the break-in comes, a
janitor standing in a room it targets catches that thief in the act: the work
never leaves its wall, the thief joins the cell, and the dawn report counts
it ("1 theft stopped in the act"). It earns the same !LAMPs as a recovery.

## Dawn

At 06:00, or when the janitor clocks out from the clipboard, the lights come
up. Any thief still inside leaves with their work. The dawn report shows:

- who was held tonight, behind bars;
- works back on their walls, thefts stopped in the act, and any lost (or
  "Nothing lost tonight");
- new works seen and bottles picked up;
- the night count and the streak, with the best night;
- the !LAMPs earned (or how to start earning them);
- the recovered works, as miniatures;
- what's still out there: bottles, works and rooms never found.

SELECT shows the shift report's QR; CANCEL goes back to the title.

## Coming back

- **A new night every day** (server time, UTC). The day's first shift counts
  as a night; more shifts that day are free play.
- **The streak** counts nights on consecutive days, and lapses when a day is
  missed. `record.lua` keeps `nights`, `streak`, `best_streak` and `best`
  (the most works recovered in a night).
- **Still out there.** The dawn report and the title's desk board ("TONIGHT:
  A BREAK-IN", "NIGHT 4, 3 IN A ROW") say what's left.
- **The evening call.** After a first dawn the app asks Solana OS to run
  `service.lua` in the background (the badge asks the owner once). Once a
  day, from 18:00 UTC, if tonight hasn't been worked, it sends one
  notification: "Break-in at the museum. Three works are missing." It looks
  at the clock every five minutes and does nothing else. The app and the
  service share the `desk` storage key: `worked` (the day last clocked in)
  and `called` (the day last called).

## !LAMPs

!LAMPs are the badge's own currency (`lamps.award`, permission `lamps`). They
are a build switch (`LAMPS` in `tools/bundle.mjs`): with it off, the manifest
doesn't ask for the permission, the game never calls `lamps.award`, and how to
play doesn't mention them. With it on, the app awards:

| For | !LAMPs |
| --- | --- |
| Each work recovered, or each theft stopped in the act | 3 |
| A clean night (nothing lost, not clocked out) | 10 |
| The day's first shift on a streak of 3 or more | 5 |

Awards stay within the daily cap the organisers set for the app; until they
set one, awards come back as 0. Only owners who've linked X on the badge
site earn them, and for the rest the dawn report says how. The awards are
small on purpose: the reason to play is the night, not the payout.

## Tuning

Everything is a constant at the top of `src/night.lua` (`START`, `DAWN`,
`SPEED`, `TRAVEL`, `CALM`, `SIGHTING`) plus the table in `next_wave`; the
kinds' constants are at the thief in `src/world.lua` (`POSE`, `DODGE`, `ZIG`,
`BOLT`), and the weather, the kinds' odds and `CALM` for a card are in
`src/caper.lua`. The tests run a whole night on the headless badge
(`test/app.test.mjs`: "the night runs on a clock", "clearing a break-in",
"a cleared break-in leaves a calling card", "the kinds of thief", "nights
count by the day"), and `mosa_debug.clock(min)` jumps the clock in a
playthrough.
