# Architecture

```
mosa (MOSA repo, local checkout) ─┐
api.mosa.center (public API) ─────┼─ tools/sync-mosa.mjs ─► src/data/mosa_data.lua + mosa.lock.json
                                  │
src/*.lua ────────────────────────┴─ tools/bundle.mjs ────► scripts/mosa.lua   (App Store: one file)
                                                            apps/mosa/          (USB/Wi-Fi push)
vendor/solana-badge (submodule) ───── tools/lib/emulator.mjs ► test/, tools/preview.mjs
```

## Lua modules (`src/`)

| Module | Job |
| --- | --- |
| `main.lua` | Entry point and scenes (title, lanyard, game, card, plaque, QR, pause, record, map, about), LEDs, lifecycle callbacks |
| `world.lua` | A room: grid laid out from synced rects, doors, landmarks, bottles, balloons, the flashlight renderer |
| `qr.lua` | QR encoder: byte mode, ECC M, versions 1–10, incremental mask search |
| `ui.lua` | MOSA's 2D language on a 6×8 font: tracked labels, wrapping, key blocks and hints, QR and sprite drawing, and the brutalist kit (board-marked concrete, slabs, block letters, catalogue numbers) |
| `record.lua` | Persistence in the per-app key/value store; the shift-report code |
| `net.lua` | ESP-NOW presence and waves |
| `util.lua` | 32-bit-safe RNG, base32, hex bitsets |
| `data/mosa_data.lua` | **Generated.** Never edit; run `pnpm sync` |

`require` works both ways: on a badge, the `apps/mosa/` directory install finds
modules next to `main.lua`; the store's single file has every module in
`package.preload`, which `main.lua` clears once loaded so the large data loader
can be collected.

## Budgets the badge enforces

| Limit | Value | How we stay inside |
| --- | --- | --- |
| Store script size | 96 KB | `pnpm build` fails above it. Currently ~83 KB; most of it is data (bottle sprites ~10 KB RLE) |
| Lua heap | 1 MB | Only the current room is laid out (`Room:suspend/resume`); QR modules are strings, not tables; thumbnails draw from RLE with no cache. A test fails above 640 KB in the emulator, whose 64-bit Lua costs about twice the badge's 32-bit build per table slot |
| Per-callback time | 250 ms | Room layout runs as a coroutine, a band of rows per frame behind a "threshold" screen. QR masks are tried one per frame. The record grid paints 12 thumbnails per frame |
| `on_start` | 5 s | Loads data and the record, starts ESP-NOW. Nothing else |
| kv keys | 8 chars | `found`, `rooms`, `goals`, `pickups`, `pops`, `shifts`, `mic`, `v` |
| ESP-NOW payload | 240 B | Presence lines are ~20 B |

### Static scenes don't repaint

The framebuffer persists between frames. Scenes marked `static` (cards,
plaques, QR, pause, record, map, about, lanyard) draw once and then only when
something changes (`dirty`: a button, a push or pop, a toast, a scene calling
`invalidate()`). A badge in Lanyard mode spends almost no CPU, which saves
battery when it's worn all day.

## 32-bit Lua

The badge's Lua is built with `LUA_32BITS`: integers are int32 and floats are
single precision. The emulator's Lua (wasmoon) is 64-bit. Rules that keep both
identical:

- The RNG masks with `& 0xFFFFFFFF`, which is a no-op on int32 and correct on
  int64. Shifts are logical in both.
- Bit-level work (QR, base32, bitsets, colours) stays on small integers.
- No integer constant over 2^31; no float precision assumptions beyond ~7 digits.
- No `string.pack` 64-bit formats, no `math.maxinteger` arithmetic.

## The headless badge

`tools/lib/emulator.mjs` runs `BadgeCore` from the official virtual badge
(`vendor/solana-badge/app/src/lib/emulator/worker/worker.ts`) under plain Node,
using a resolve hook (`tools/lib/resolve-hook.mjs`) so the submodule stays
untouched. It's the same Lua runtime, SDK shim, sandbox and limits as
[solanadefcon.com/badge](https://solanadefcon.com/badge/), with a fake clock and
deterministic randomness. Screenshots are the framebuffer, pixel for pixel.

Bumping the submodule (`git -C vendor/solana-badge pull`, commit the new
pointer) and running `pnpm test` is how we find out what an SDK change broke.

`pnpm play` (`tools/play/`) runs the same headless badge in real time behind a
small HTTP server: frames go to the page over server-sent events, buttons come
back as POSTs (held at least 70 ms, since the badge debounces for 25 ms).

`mosa_debug` (end of `main.lua`) is a small global test seam: scene state,
teleporting to a bottle, travelling synchronously. Harmless on hardware.
