# mosa-badge

M.O.S.A. Night Shift for the Solana DEF CON badge: a Lua app for Solana OS that
walks MOSA's real floorplans and hands visitors into the HD museum by QR.
Read `README.md`, then `docs/ARCHITECTURE.md` before changing `src/`.

## Rules

- **Never edit generated files.** `src/data/mosa_data.lua` comes from `pnpm sync`;
  `scripts/mosa.lua` and `apps/mosa/*` come from `pnpm build`. CI fails if the
  built files don't match `src/`.
- **Derived, not hand-authored** (MOSA's own rule). Rooms, doors, landmarks,
  goals, pieces and links come from the MOSA repo and API through the sync.
  No room IDs, piece IDs or URLs hard-coded in `src/`. If something can't be
  derived, extend the sync.
- **The registry in `mosa.lock.json` is append-only.** Never reorder or delete.
- **Badge budgets:** 96 KB script, 1 MB heap, 250 ms per callback, 8-char kv
  keys. Heavy work goes in coroutines across frames. Static screens set
  `static = true` and call `invalidate()` when they change. Keep `pnpm build`
  under the size guard and `pnpm test` green (the heap test is the budget).
- **32-bit Lua on the badge:** int32 integers, single-precision floats. Mask with
  `& 0xFFFFFFFF`, keep bit work on small ints. No long strings/comments
  (`[[ ]]`) in `src/`; the bundler strips comments by line.
- **MOSA's design language:** no colour in the UI chrome (only the art, and the
  crosshair green `#7ee8a8`), tracked uppercase labels, paper-and-ink cards, no
  permanent HUD counters. Print button names with `badge.input.label()`
  (SELECT/CANCEL), never "A/B".
- Versioning: SemVer per `docs/RELEASING.md`; update `CHANGELOG.md` under
  Unreleased with every user-visible change.

## Commands

```bash
pnpm sync      # needs ../mosa or --mosa <path>
pnpm build && pnpm test && pnpm preview
pnpm play      # the built app in a browser, on the emulator
pnpm pixel check
```

Hand-made bottle sprites live in `art/pixel/` (rules in `docs/PIXEL-ART.md`);
they are source art, not generated, and the sync validates them.

The tests run the real Solana OS emulator from `vendor/solana-badge` (git
submodule) through `tools/lib/emulator.mjs`; `node --import ./tools/lib/register.mjs`
is required for anything that imports it (the pnpm scripts do this).
