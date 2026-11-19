# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions: [SemVer](https://semver.org/), as defined for this app in [docs/RELEASING.md](docs/RELEASING.md).

## [Unreleased]

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

[Unreleased]: ../../compare/v0.1.0...HEAD
[0.1.0]: ../../releases/tag/v0.1.0
