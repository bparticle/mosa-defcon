# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions: [SemVer](https://semver.org/), as defined for this app in [docs/RELEASING.md](docs/RELEASING.md).

## [Unreleased]

### Fixed

- No QR leads to `mosa.center/at/defcon` any more, a link the museum never
  had. The Lanyard, About and shift-report QRs open the Janitor Room
  (`/at/bp26`), and a work without a page of its own opens its room's link,
  else the museum.

## [0.6.1] - 2026-11-20

The same game as 0.6.0, resubmitted to the store with a request for a daily
!LAMPs allowance (the store doesn't let a submitted version change).

## [0.6.0] - 2026-11-20

The night: a clock to dawn, a desk that keeps sending work, and a reason to come back tomorrow.

### Added

- The night has a clock: the shift runs from 23:41 to dawn, about eight
  minutes of play, and stops while the clipboard is up. Hours chime; 05:00
  warns that the thieves leave with the light.
- The security desk keeps the night going. Clear a break-in and it's "ALL
  CLEAR, FOR NOW"; after a calm the desk radios the next wave. Its size and
  pace follow how quickly you cleared the last one: quick janitors meet more
  thieves, struggling ones get a breather. A thief gone unseen too long is
  reported again.
- Dawn: at 06:00 (or when you clock out) the lights come up on the night's
  report: works back and lost, new finds, your nights and streak, !LAMPs
  earned, and what's still out there to find.
- A new night every day, the same first break-in for every janitor that
  day, with a streak for consecutive nights. The title's desk board says
  whether tonight is still to work.
- !LAMPs: 3 for each work recovered, 10 for a clean night, 5 for the first
  shift of a streak of three or more (for owners who linked X; within the
  daily cap the organisers set).
- The desk's evening call: after a first dawn, Night Shift asks to run in
  the background and sends one notification an evening when tonight hasn't
  been worked. New permissions: `lamps` and `background`.
- HOW TO PLAY on the title: five pages on the night, the light, the desk,
  travel and coming back.

### Changed

- Travel costs time: the map takes you only to rooms you've walked, and each
  trip costs twenty minutes of the night. Doors are free.
- The "ALL CLEAR" finale is gone: catching the third thief no longer ends
  the shift. The dawn report takes its place.

## [0.5.0] - 2026-11-20

The beam: a flashlight that fades into the dark, and nothing to read in the rooms.

### Changed

- The flashlight's beam dithers into the dark: a hard circle of light round
  the janitor, then a beam that breaks up into a pixel pattern toward its end.
- Nothing to read in the rooms any more: the furniture plaques (specimen case,
  departures board, partner entrances and the rest) and the empty-frame label
  are gone. SELECT is offered only by a work on its wall. The furniture is
  still there to walk around, and an empty frame still shows what was taken.

## [0.4.2] - 2026-11-20

### Fixed

- Teleporting into a wide room no longer stops the app with "script took too
  long". Laying out a room is now paced by the work it does, not by rows, and
  the search for an open spot to land on is lighter.

## [0.4.1] - 2026-11-20

### Fixed

- SELECT and CANCEL work on the badge again. Solana OS passes the key repeat
  as a number, and the app took a fresh press (0) for a held repeat, so
  only the arrows did anything.

## [0.4.0] - 2026-11-20

The footage: a briefing you watch, travel between rooms, and thieves that run.

### Added
- **The footage.** The briefing is now security-camera footage instead of a
  page of text: a work hangs in a pool of light, a thief creeps in, lifts it,
  glances at the camera and runs. Then tonight's list: the stolen works
  themselves, as pixel art, with the room each was taken from. SELECT
  fast-forwards the tape; the next press starts the shift.
- **Travel.** SELECT on any room on the map (MAP AND TRAVEL on the
  clipboard) and the light closes in on the janitor and opens in that room,
  like the HD museum's travel.
- **Thieves run.** Dazzled, or hearing you close by in the dark, a thief
  makes for the nearest door away from you, with a "!" over their head. Reach
  it and they're away into the next room, work and all; the map shows where
  they went. A bar over a thief in the light fills until they give up.
- A beat after a catch: the thief scatters before the work's card comes up.
- A first shift shows the controls along the bottom for its first seconds.

### Changed
- The cupboard intro plays on the first shift only; after that CLOCK IN goes
  straight to the footage.
- Toasts are a slip of paper along the bottom, out of the way of the walk,
  and a room's visit stamp sits beside its name instead of covering the
  screen. The room's name has a dark plate, so it reads over a lit wall.
- Exits are chevrons pointing through the doorway, shown for the doors near
  you, instead of dashes scattered across the dark.
- Holding a thief in the light takes a little longer (1.1 s).

Data: MOSA `2907085`, data schema 2, Solana OS 2.4 (Lua 5.5).

## [0.3.0] - 2026-11-20

The Rounds: a story, the real art, and a flashlight you can feel.

### Added
- **A story.** CLOCK IN opens in the janitor's cupboard: the janitor walks in,
  takes the flashlight off its hook and clicks it on; the bulb goes out. Then
  the curator's note: thieves got in after closing and three works are off
  their walls. Any button skips the intro.
- **Art thieves.** Each shift, three thieves each take a work from a different
  room (the first always one door from the start). They creep about in the
  dark, two eyes now and then; hold the flashlight on one and, dazzled, they
  drop the work and bolt. The LEDs sweep like a scanner as you close in. An
  empty frame on the wall tells you what was taken.
- **The real art, on its real walls.** The 75 works MOSA hangs, Community
  Gallery, the Poet Toads show and every pinned Sirial, are synced from the
  MOSA repo and hung where the HD museum hangs them, as pixel miniatures (up to
  24×24, a few flat colours, crisp like the bottles). SELECT by one looks at it up close; SEE IT IN HD shows a
  QR to the real work (its Mallow or 6529 page, else the museum).
- **All clear.** Catching the last thief brings the lights up: the night's
  tally, the recovered works side by side, and the museum one scan away.
- **A janitor.** A 10×16 pixel janitor with a cap, overalls, a walk cycle in
  four directions and the flashlight in hand; thieves in striped shirts and
  masks carry their loot under one arm.
- **The museum map**: MOSA's real floorplan, laid out by the sync from the
  rooms' world positions. Rooms you've walked are filled in, the one you're in
  carries the crosshair, rooms with a thief blink, and an uncatalogued room
  stays off the map until you find it.
- **THE ART**: every work, looked-at ones in colour and the rest as empty
  frames, each saying which room it hangs in.
- Bottles lie on the HD museum's own find spots.

### Changed
- **The flashlight is one hard-edged cone and a small pool at your feet**;
  everything else is dark, with a faint memory of what you've seen. Exits glow
  so the way out is never lost.
- The title menu is CLOCK IN, THE ART, BOTTLES, LANYARD, ABOUT. The clipboard
  has MUSEUM MAP, THE ART and BOTTLES; the shift record is now BOTTLES. The
  title and lanyard show works and bottles in turn.
- The record keeps the works you've looked at and the thieves you've caught.
  The shift-report code is unchanged.
- The App Store summary: "The Museum of Sirius Art after hours. Catch the
  thieves. See the art in HD."
- Data schema 2: works, find spots and the map in `mosa_data.lua`, and a new
  append-only `works` registry in `mosa.lock.json`.

### Removed
- Balloons. They're a small game inside the HD museum, not what the night
  shift is about. Floor 1's "Full Floor Clearance" stamp goes with them.
- The visitor map's list of rooms and goals (now the museum map).

Data: MOSA `2907085`, data schema 2, Solana OS 2.4 (Lua 5.5).

## [0.2.0] - 2026-11-19

Night Shift on Solana OS, the Breakpoint 2026 badge, and in its App Store.

### Added
- Splash screen at start: the museum is poured in board-marked concrete, then
  cast in block letters. Any button skips it.
- Brutalist look across the app: board-marked concrete bands with form-tie
  holes, slabs with hard black shadows, block-letter logo, catalogue numbers
  (`NO. 007`) on cards and the title, numbered menus with an inverted
  selection, buttons printed as inverted key blocks, stamp-style toasts, and
  walls with a cast south face.
- Per-bottle pixel art: hand-made sprites in `art/pixel/<collection>/<piece>.png`
  replace the automatic ones; `pnpm pixel` (`sheet`, `starter`, `import`,
  `check`) and [docs/PIXEL-ART.md](docs/PIXEL-ART.md).
- The museum now reads the shift-report QR: a Night Shift sheet on arrival and a
  one-per-wallet commemorative (built in `bparticle/mosa`, see
  [docs/MOSA-INTEGRATION.md](docs/MOSA-INTEGRATION.md) §2).
- `pnpm play`: play the built app in a browser on a headless Solana OS, with
  simulated nearby badges, reloading on every build.
- [docs/BADGE.md](docs/BADGE.md): installing on a badge, and checking a build on
  the real firmware.

### Changed
- **Ported to Solana OS 2.4 on the Breakpoint 2026 badge (ESP32-C5, Lua 5.5).**
  The build is now an app package in `apps/mosa/` (`main.lua`, `app.json`,
  modules) instead of `scripts/mosa.lua`. Install it with **Run on badge** at
  solana.com/breakpoint/badge/apps/submit.
- Drawing goes through one `ui.canvas`, with the 6×8 font bundled; QR codes are
  drawn by the firmware.
- Eight LEDs instead of two.
- Other janitors are found over the Solana OS mesh instead of ESP-NOW. Waves
  carry the badge owner's name.
- The shift record is kept in the app's storage (one key). The shift-report
  code is unchanged, so the museum reads it as before.
- CANCEL on the title leaves the app.
- Automatic bottle sprites are pixelized, not shrunk: background removal, a
  mode filter per pixel and a 7-colour palette. Crisper, and the data is 8 KB
  smaller.
- Bottle sprites stand upright. The cover renders lean about 5° like the static
  posters, which turned every edge into a staircase at 16×24; the sync now
  straightens each bottle before snapping it to the grid (38 of 41; round
  shapes with no long axis are left as drawn).

### Removed
- Blowing into the badge to pop balloons: this badge has no microphones.
  SELECT still pops them.
- The Lua QR encoder, `scripts/mosa.lua`, and the `vendor/solana-badge`
  submodule with its emulator.

Data: MOSA `2907085`, data schema 1, Solana OS 2.4 (Lua 5.5).

## [0.1.0] - 2026-11-19

First release: **M.O.S.A. Night Shift**.

### Added
- Night Shift: top-down walk through MOSA's 12 rooms, floorplans derived from
  the room claim volumes, doors from portals, landmarks from vitrines, boards,
  ticket and vending machines and partner entrances.
- Flashlight rendering with remembered tiles; LED "metal detector" toward the
  nearest bottle.
- 41 bottles from the live MOSA Bottles collection, weighted by the catalogue's
  rarity weights and placed where it hunts; label cards with 16×24 thumbnails.
- QR codes (byte mode, ECC M, v1–10) for every find
  (`mosa.center/at/find/<c>/<p>`), partner entrances, the Janitor Room
  (`/at/bp26`), and the museum (`/at/defcon`).
- Balloons: pop with SELECT or by blowing into the mics.
- Room stamps from MOSA's room programmes (visit, pop-all-balloons, discover-room).
- Lanyard mode: an idle badge becomes a scannable billboard.
- Shift record (found pieces in colour, the rest as plaster casts) and the
  shift-report code (format 1).
- ESP-NOW presence (`MOSA1`): janitors nearby, waves, and the mythical bottle
  that only appears when another badge is in range.
- Tooling: `pnpm sync` (pinned to a MOSA commit, links validated by MOSA's own
  parser), `pnpm build` (single-file store bundle, 96 KB guard), headless
  emulator tests and screenshots on the pinned Solana OS submodule.

Data: MOSA `f1d804c`, data schema 1, Solana OS `812b8c7`.

[Unreleased]: ../../compare/v0.6.1...HEAD
[0.6.1]: ../../compare/v0.6.0...v0.6.1
[0.6.0]: ../../compare/v0.5.0...v0.6.0
[0.5.0]: ../../compare/v0.4.2...v0.5.0
[0.4.2]: ../../compare/v0.4.1...v0.4.2
[0.4.1]: ../../compare/v0.4.0...v0.4.1
[0.4.0]: ../../compare/v0.3.0...v0.4.0
[0.3.0]: ../../compare/v0.2.0...v0.3.0
[0.2.0]: ../../compare/v0.1.0...v0.2.0
[0.1.0]: ../../releases/tag/v0.1.0
