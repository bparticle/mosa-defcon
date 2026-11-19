# M.O.S.A. on the Solana badge: Night Shift

A way into [M.O.S.A., the Museum of Sirius Art](https://mosa.center), for the
[Solana DEF CON badge](https://solanadefcon.com/) (ESP32-S3, 320×240, six
buttons, two RGB LEDs, mics, ESP-NOW, a Solana key in a secure element).

**Night Shift** is MOSA after hours, top-down. You're the janitor. The rooms
are MOSA's real floorplans, the bottles in the dark are real pieces from the
live **MOSA Bottles** collection by real artists, and every one you find shows
a QR that takes you to where it stands in the HD museum, to collect it on
Solana. Leave the badge alone and it becomes a walking billboard for the
museum.

| | | |
| --- | --- | --- |
| ![Title](docs/screens/01-title.png) | ![Lobby](docs/screens/04-lobby-walk.png) | ![Found](docs/screens/07-found-card.png) |
| ![Museum link](docs/screens/08-museum-link-qr.png) | ![Lanyard](docs/screens/02-lanyard.png) | ![Shift record](docs/screens/14-shift-record.png) |

*Screenshots are the real Solana OS emulator's framebuffer (`pnpm preview`).*

## Put it on a badge

**From the App Store** (no cable): open
[solanadefcon.com/store](https://solanadefcon.com/store/), point it at this
repo (or `…/tree/v0.1.0` for a pinned release), pick `mosa.lua`, enter the
badge ID from the badge's *Settings → Identity*, send. The badge asks its
wearer; SELECT installs.

**Over USB/Wi-Fi:** push the `apps/mosa/` directory with Solana OS's
`badge-push.py` (see [docs/RELEASING.md](docs/RELEASING.md)).

**Try it without hardware:** the official [virtual badge](https://solanadefcon.com/badge/)
registers with the store like a real one: send it the app the same way.

## Controls

| | |
| --- | --- |
| D-pad | Walk; move through menus |
| SELECT | Pop a balloon in reach; read a plaque; choose |
| CANCEL | Clipboard (pause): visitor map, shift record, wave, clock out |
| Blow into the badge | Pop every balloon in front of you |
| Hold CANCEL 1.5 s | Quit (handled by Solana OS) |

Walk into a bottle to pick it up. The two LEDs blink in the colour of the
nearest bottle, faster as you get closer.

## Develop

Needs Node ≥ 22.18 (24 recommended), pnpm, and a checkout of the MOSA repo for
syncing (default `../mosa`).

```bash
git clone --recurse-submodules <this repo>
pnpm install
pnpm sync       # MOSA → src/data/mosa_data.lua + mosa.lock.json
pnpm build      # src/ → scripts/mosa.lua (store) + apps/mosa/ (push)
pnpm test       # plays the built app on the real Solana OS emulator
pnpm preview    # screenshots of every screen → docs/screens/
```

```
src/              the Lua app (modules; data/mosa_data.lua is generated)
scripts/mosa.lua  BUILT: the single file the App Store installs
apps/mosa/        BUILT: the same app as a directory, for badge-push.py
tools/            sync-mosa.mjs, bundle.mjs, preview.mjs, lib/ (emulator, shift decoder)
test/             QR round-trips through jsQR; app playthroughs on the emulator
vendor/solana-badge  git submodule, pinned: the badge firmware + its emulator
mosa.lock.json    what the data was generated from; the append-only index registry
```

## Docs

- [CONCEPTS.md](docs/CONCEPTS.md): the options considered and why Night Shift first
- [FLOW.md](docs/FLOW.md): from a badge at DEF CON to the HD museum
- [SOLANA.md](docs/SOLANA.md): trust tiers: links, shift claims, booth beacons, badge signatures
- [MOSA-INTEGRATION.md](docs/MOSA-INTEGRATION.md): how the sync keeps us in lockstep, and the museum-side changes
- [ARCHITECTURE.md](docs/ARCHITECTURE.md): modules, the badge's budgets, 32-bit Lua, the headless badge
- [RELEASING.md](docs/RELEASING.md): versioning and cutting a release
- [CHANGELOG.md](CHANGELOG.md)
