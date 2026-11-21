# Versioning and releases

One version number, in `package.json`, following SemVer. It's stamped into
`apps/mosa/app.json` (what the badge and the App Store show),
`apps/mosa/build_info.lua`, and the About screen.

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
  app's storage. Changing it needs a migration in `record.load()`.
- **Shift format** (first 4 bits of the code, `record.report_code`,
  `tools/lib/shift.mjs`): what the museum decodes. A new layout is a new format
  number; the decoder keeps reading the old ones.
- **Presence messages** (`src/net.lua`): the mesh only delivers them to
  badges running the same app id. Change the fields only in ways old badges
  ignore cleanly (`net.receive` drops anything it doesn't recognise).

## Cutting a release

```bash
pnpm install
pnpm sync                            # needs ../mosa (or --mosa <path>) at the commit you mean to ship
pnpm build
pnpm test
pnpm preview                         # refresh docs/screens/
# run it on the real firmware (docs/BADGE.md)
# edit CHANGELOG.md: move "Unreleased" under the new version
npm version minor                    # or patch / major: bumps package.json, rebuilds, commits, tags vX.Y.Z
git push --follow-tags
```

`npm version` runs the `version` script, which rebuilds so the committed
`apps/mosa/` carries the new number in the same
commit as the tag. CI (`pnpm check`) fails any commit whose built files don't
match `src/`.

## !LAMPs

The App Store holds back an app whose manifest asks for the `lamps`
permission until the organisers approve it. So !LAMPs are one switch,
`const LAMPS` at the top of `tools/bundle.mjs`, off for now: the manifest
leaves the permission out, `build_info.lua` carries `lamps = false`, and the
game neither awards !LAMPs nor mentions them. The !LAMPs code stays on `main`
and its test runs with the switch on, so nothing drifts. Once the permission
is approved: set `LAMPS = true`, `pnpm build && pnpm test`, add a changelog
line, cut a minor release and submit it.

## Installing a specific version

From the App Store, a badge gets the version last submitted. To put an exact
release on a badge, check out its tag, `pnpm build`, and use **Run on badge**
(see [BADGE.md](BADGE.md)). At a booth, do that rather than building from
`main`, so a mid-event push can't change what visitors get.

## Keeping the record compatible

Storage belongs to the app id, so keep `mosa-night-shift` and a badge
keeps its record across updates. The append-only registry in `mosa.lock.json` means piece and room
indices never move, so an old record still means the same bottles. If the
registry ever has to be rebuilt, that's a major release with a record migration.
