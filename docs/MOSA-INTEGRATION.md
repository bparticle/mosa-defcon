# Integration with the MOSA repo

Two directions: **MOSA → badge** (keeping the badge in sync, automated here)
and **badge → MOSA** (small museum changes that close the loop, to be made in
`bparticle/mosa`).

## MOSA → badge: staying in sync

The badge never hand-copies museum content. `pnpm sync` derives everything:

| Badge data | Derived from (MOSA) | Contract |
| --- | --- | --- |
| Room floorplans | `apps/frontend/src/lib/rooms.generated.ts` → each room's `claims` (footprints), rasterised per room | Same source the museum's travel uses; a new room in `MOSA-ROOMS.blend` → `build:world` → `pnpm sync` → on the badge. No badge code change |
| Doors | `portals` (both rooms' listings, deduped) and `warps` | A doorway is carried by both rooms (MOSA's `check:world` guarantees it) |
| Landmarks | `vitrines`, `flapboards`, `postcardwalls`, `dispensers`, `vendors`, `entrances` | New furniture kinds need a plaque text in `src/main.lua` (`PLAQUES`); unknown kinds still show, with a generic plaque |
| Room stamps | `apps/frontend/public/rooms/<id>.programme.json` goals | The badge awards `visit` and `discover-room` (a room behind one stays off the museum map until found). Other goal types are logged by the sync and skipped, never approximated |
| Museum map | The room claim volumes, which share one world space | Scaled to the map screen and cropped; each room's rects and centre |
| Works | `apps/frontend/src/lib/communityArt.ts` `HUNG_WORKS`, `sirialPins.generated.ts` `SIRIAL_PINS`, titles from `sirials.provenance.generated.ts` | Title, artist, link; images pixelized to at most 24×24 in 7 flat colours (4 for ink drawings). A work's own https link is its QR, else its room's. `registry.works` is append-only like the others |
| Where works hang | Each room's GLB: `<room>_placement_<slot>` and `sirial_placement_N` empties (`tools/lib/glb.mjs`) | Snapped to the nearest wall within 3 tiles, facing out; otherwise a free-standing panel |
| Bottle spots | The room GLBs' `find_placement__bottle.NNN` empties | Bottles lie there first, then anywhere on the floor |
| Bottles, tiers, artists | `GET /finds/catalog` (live API) | Rarity weights and hunt rooms come from the catalogue, so a re-tuned hunt re-tunes the badge on the next sync |
| Sprites | `GET /finds/media/<c>/<p>/cover`, or hand art in `art/pixel/` | Pixelized to 16×24, 7 colours, unless a hand-made sprite exists ([PIXEL-ART.md](PIXEL-ART.md)); run-length encoded |
| Partner and room links | `GET /links` | Only enabled, unscheduled links |
| Every QR URL | `apps/frontend/src/lib/linkPaths.ts` `parseLinkPath` | The sync **fails** if MOSA's own parser rejects a URL |

### Pinning and drift

- `mosa.lock.json` records the MOSA commit, hashes of the room table, catalogue
  and links, and a hash of the generated data. Every bundled script carries the
  MOSA commit in its header and logs it on start.
- **The registry is append-only.** `registry.rooms` and `registry.pieces` give
  every room and piece a permanent index. Shift-report bitmasks index into it,
  so a code printed by v0.1 still decodes correctly after v0.5 adds pieces.
  Never reorder or delete entries; a removed piece keeps its slot.
- `pnpm sync --check` regenerates in memory and fails if the committed data is
  stale. `.github/workflows/drift.yml` runs it weekly against MOSA `main` and
  the live API (needs a `MOSA_READ_TOKEN` secret, since `bparticle/mosa` is
  private). A stale result means: run `pnpm sync`, review the diff, cut a patch
  release.
- `DATA_SCHEMA` (in `tools/sync-mosa.mjs`, checked in `src/main.lua`) is bumped
  when the shape of `mosa_data.lua` changes. An app refuses data it doesn't
  understand instead of misreading it.

### What's public

This repo has to be public for the App Store to read it. The generated data
contains only what `mosa.center` already ships to every browser: room
geometry from the public frontend bundle, and catalogue data and art from the
public API. No secrets, no wallet data. The MOSA repo itself stays private;
the sync reads a local checkout.

## Badge → MOSA: changes to make in `bparticle/mosa`

In order of value per effort. None are required for the badge app to work.

### 1. A `/at/defcon` link (console, no code)

Console → Links → New. Slug `defcon`; target: room `room12` (the Janitor
Room, fitting the Night Shift story) or the Lobby; host Sirius Crocodile;
welcome along the lines of *"Off the night shift? Welcome to M.O.S.A."*. Until
it exists the badge's Lanyard QR still works: an unknown `/at/` slug opens the
museum as usual (`docs/LINKS.md`).

### 2. Read `?shift=` on arrival — done

Built in `bparticle/mosa` (migration 078, `apps/frontend/docs/BADGE-SHIFT.md`):

- **Museum**: `?shift=` is kept at boot and taken out of the address. Once the
  visitor is in, a Night Shift sheet (the visitor label's paper) shows the rooms
  swept and the bottles found, each opening its specimen sheet, plus the
  commemorative when one is offered.
- **API**: `GET /badge/shift?code=` (public, no database) and `POST /badge/shift`
  (signed in), which keeps one row per wallet in `badge_shifts` and gives
  `BADGE_SHIFT_GIFT=<collection>/<piece>` once through Gifts. Only a free piece
  can be given, since a code is only a claim (tier 1, [SOLANA.md](SOLANA.md)).
- **The decoder** is `lib/badgeShift.ts`, mirrored in both MOSA apps, with a
  copy of this repo's registry. **When `pnpm sync` appends rooms or pieces to
  `mosa.lock.json`, paste the new registry into both copies there.** A longer
  code from a newer badge still reads; the extra bottles are ignored until then.
- Analytics: a row in `badge_shifts` = arrived from a badge.

### 3. Canonical `/at/room/<roomId>` (both apps, mirrored grammar)

`room` is already a reserved word in `linkPaths.ts`. Adding the family (mirrored
byte for byte in `apps/api` and `apps/frontend`, both pinned by their tests)
lets every badge plaque land in its own room instead of the generic link. The
sync would then emit `/at/room/<id>` for rooms without a curated link, still
validated by `parseLinkPath`.

### 4. A small-thumbnail endpoint

`GET /finds/media/<c>/<p>/cover?w=96` (PNG, ≤ 30 KB) for the badge's online
mode (pocket gallery, sharper label art when on Wi-Fi). Not built; it was
sized for the earlier DEF CON badge platform, so recheck it against what
Solana OS apps can fetch and decode before building it.

### 5. Booth beacon verification (with tier 2)

`BADGE_BEACON_SECRET` in the API env and an HMAC check on `&b=` in
`POST /badge/shift`. See [SOLANA.md](SOLANA.md) §2.
