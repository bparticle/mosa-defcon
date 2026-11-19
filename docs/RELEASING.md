# Versioning and releases

One version number, in `package.json`, following SemVer. It's stamped into the
bundled script's header, `apps/mosa/app.ini` (what the badge launcher shows),
and the About screen.

## What bumps what

| Change | Bump | Example |
| --- | --- | --- |
| Data-only resync (new bottles, re-tuned hunt, a new room with no new mechanics) | **patch** | 0.1.0 → 0.1.1 |
| New gameplay, screens, settings; new optional fields in the data | **minor** | 0.1.1 → 0.2.0 |
| Anything that invalidates a player's saved record, changes the shift-report format, or bumps `DATA_SCHEMA` incompatibly | **major** | 0.x → 1.0, 1.x → 2.0 |

Independent version lines that must never silently change:

- **`DATA_SCHEMA`** (`tools/sync-mosa.mjs`, checked by `src/main.lua`): the
  shape of `mosa_data.lua`.
- **Record schema** (`SCHEMA` in `src/record.lua`): what's stored in the
  badge's key/value store. Changing it needs a migration in `record.load()`.
- **Shift format** (first 4 bits of the code, `record.report_code`,
  `tools/lib/shift.mjs`): what the museum decodes. A new layout is a new format
  number; the decoder keeps reading the old ones.
- **Presence protocol** (`MOSA1` prefix in `src/net.lua`): bump the prefix
  if the wire format changes, so old and new badges ignore each other cleanly.

## Cutting a release

```bash
git submodule update --init          # the emulator the tests run on
pnpm install
pnpm sync                            # needs ../mosa (or --mosa <path>) at the commit you mean to ship
pnpm build
pnpm test
pnpm preview                         # refresh docs/screens/
# edit CHANGELOG.md: move "Unreleased" under the new version
npm version minor                    # or patch / major: bumps package.json, rebuilds, commits, tags vX.Y.Z
git push --follow-tags
```

`npm version` runs the `version` script, which rebuilds so the committed
`scripts/mosa.lua` and `apps/mosa/app.ini` carry the new number in the same
commit as the tag. CI (`pnpm check`) fails any commit whose built files don't
match `src/`.

## Installing a specific version

The App Store reads a repo at any ref:

- `github.com/<owner>/mosa-badge`: the default branch, the latest.
- `github.com/<owner>/mosa-badge/tree/v0.1.0`: exactly that release. Use this
  at a booth, so a mid-event push to `main` can't change what visitors get.

Over USB or Wi-Fi with the badge's push tool:

```bash
python vendor/solana-badge/firmware/solana-os/tools/badge-push.py --host <badge-ip> --token <pairing code> push apps/mosa --run
```

## Keeping the record compatible

A badge keeps its record across app updates (the key/value store survives
reinstalls). The append-only registry in `mosa.lock.json` means piece and room
indices never move, so an old record still means the same bottles. If the
registry ever has to be rebuilt, that's a major release with a record migration.
