# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions: [SemVer](https://semver.org/), as defined for this app in [docs/RELEASING.md](docs/RELEASING.md).

## [Unreleased]

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
  24×24, 15 colours). SELECT by one looks at it up close; SEE IT IN HD shows a
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
- Data schema 2: works, find spots and the map in `mosa_data.lua`, and a new
  append-only `works` registry in `mosa.lock.json`.

### Removed
- Balloons. They're a small game inside the HD museum, not what the night
  shift is about. Floor 1's "Full Floor Clearance" stamp goes with them.
- The visitor map's list of rooms and goals (now the museum map).

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

[Unreleased]: ../../compare/v0.2.0...HEAD
[0.2.0]: ../../compare/v0.1.0...v0.2.0
[0.1.0]: ../../releases/tag/v0.1.0
