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
| Room stamps | `apps/frontend/public/rooms/<id>.programme.json` goals | The badge awards `visit`, `pop-all-balloons`, `discover-room`. Other goal types are logged by the sync and skipped, never approximated |
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

In order of value per effort. None are required for v0.1 to work.

### 1. A `/at/defcon` link (console, no code)

Console → Links → New. Slug `defcon`; target: room `room12` (the Janitor
Room, fitting the Night Shift story) or the Lobby; host Sirius Crocodile;
welcome along the lines of *"Off the night shift? Welcome to M.O.S.A."*. Until
it exists the badge's Lanyard QR still works: an unknown `/at/` slug opens the
museum as usual (`docs/LINKS.md`).

### 2. Read `?shift=` on arrival (frontend + API)

- **Frontend**: when the arrival URL carries `shift`, keep it with the
  invitation (`state/placesStore.ts`) and, once the visitor is in, open a
  one-time sheet in the museum's paper-and-ink label style: rooms swept, bottles
  found, as specimen-case thumbnails, plus *"Collect the Night Shift
  commemorative"*.
- **API**: `POST /badge/shift` `{ code, wallet }` → decode with the reference
  decoder (`tools/lib/shift.mjs` here; copy it to `apps/api/src/lib/`, with a
  test pinned to `mosa.lock.json`'s registry), record the shift
  (`badge_shifts`: wallet, code, decoded counts, first seen), and grant the
  commemorative through **Gifts** (any collection, one per wallet), following
  the console rule *"Give something to a wallet in Gifts"*.
- Tier-1 trust only: grant free, one-per-wallet things. See
  [SOLANA.md](SOLANA.md).
- Analytics: `shift` present = arrived from a badge. That's DEF CON
  attribution for free.

### 3. Canonical `/at/room/<roomId>` (both apps, mirrored grammar)

`room` is already a reserved word in `linkPaths.ts`. Adding the family (mirrored
byte for byte in `apps/api` and `apps/frontend`, both pinned by their tests)
lets every badge plaque land in its own room instead of the generic link. The
sync would then emit `/at/room/<id>` for rooms without a curated link, still
validated by `parseLinkPath`.

### 4. A small-thumbnail endpoint

`GET /finds/media/<c>/<p>/cover?w=96` (PNG, ≤ 30 KB) for the badge's online
mode (pocket gallery, sharper label art when on Wi-Fi). The badge decodes PNG/
JPEG up to 256 KB but has only a 1 MB Lua heap and slow links over the BLE
bridge.

### 5. Booth beacon verification (with tier 2)

`BADGE_BEACON_SECRET` in the API env and an HMAC check on `&b=` in
`POST /badge/shift`. See [SOLANA.md](SOLANA.md) §2.
