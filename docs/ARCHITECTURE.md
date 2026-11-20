# Architecture

```
mosa (MOSA repo, local checkout) ─┐
api.mosa.center (public API) ─────┼─ tools/sync-mosa.mjs ─► src/data/mosa_data.lua + mosa.lock.json
                                  │
src/*.lua ────────────────────────┴─ tools/bundle.mjs ────► apps/mosa/   (the Solana OS app package)
                                                                 │
tools/lib/host.mjs (headless Solana OS) ◄────────────────────────┴─► test/, tools/preview.mjs, tools/play/
```

## The app package (`apps/mosa/`)

Solana OS installs an app as a folder: `main.lua` (at most 64 KB), an
`app.json` manifest, and the modules `main.lua` loads with `require("a.b")`
(the file `a/b.lua`). A package holds at most 64 files, each at most 256 KB
and 1 MB in total, with paths in `[a-z0-9_-./]`. `tools/bundle.mjs` copies
`src/**/*.lua` verbatim, so line numbers in a badge error match `src/`. It adds
`build_info.lua` and `app.json`, checks every limit, and removes any stale
files. `pnpm check` fails when the committed package doesn't match `src/`.

The manifest asks for two permissions: `led` and `mesh`.

## Lua modules (`src/`)

| Module | Job |
| --- | --- |
| `main.lua` | Entry point and scenes (splash, title, intro, briefing, game, art card, bottle card, plaque, QR, pause, art and bottle grids, museum map, finale, lanyard, about), tonight's heist, LEDs, the Solana OS callbacks |
| `world.lua` | A room: grid laid out from synced rects, doors, landmarks, works on their walls or panels, bottles, the thief, and the flashlight renderer (lit runs per tile row, a faint memory pass) |
| `light.lua` | The flashlight's shape: a cone and a pool as integer spans per scanline, and a point test |
| `sprites.lua` | The janitor and the thieves, 10×16 in four directions with a walk cycle, drawn as runs |
| `gfx.lua` | The one full-screen `ui.canvas`, colours, rectangles, lines, text from the font, and the firmware's QR object |
| `font.lua` | The 6×8 GLCD font (ASCII 32–126) as hex |
| `kit.lua` | MOSA's 2D language: tracked labels, wrapping, key blocks and hints, sprite drawing, and the brutalist kit (board-marked concrete, slabs, block letters, catalogue numbers). `main.lua` calls it `ui` |
| `record.lua` | Persistence in the app's storage; the shift-report code |
| `net.lua` | Presence and waves over the Solana OS mesh |
| `util.lua` | 32-bit-safe RNG, base32, hex bitsets |
| `data/mosa_data.lua` | **Generated.** Never edit; run `pnpm sync` |

The firmware draws QR codes itself (`ui.qr`, one at a time). A scene that shows
one has a `:qr()` method returning `{ text, x, y, size }`, and `draw()` keeps
the single QR object in step with the top scene.

## Budgets the badge enforces

| Limit | Value | How we stay inside |
| --- | --- | --- |
| `main.lua` | 64 KB | `pnpm build` fails above it. Currently ~55 KB; the data module (~76 KB: floorplans, the map, 75 works and 41 bottles as RLE) is a separate file |
| Lua heap | 6 MB | Only the current room is laid out (`Room:suspend/resume`); thumbnails draw from RLE with no cache. The real emulator reports a peak of ~0.6 MB. A test fails above 640 KB on the host |
| Instructions per callback | 200 000 | Room layout runs as a coroutine, up to four slices a tick behind a "threshold" screen (peak ~36 000). The flashlight draws runs of tile colour per scanline inside the cone, skips what it can't reach and draws identical scanline pairs once (peak ~52 000, in the lit Lobby). The title is static and repaints only when its art changes. The grids paint 12 thumbnails a tick. Canvas pixels cost 1 instruction per 16 |
| Storage | 16 KB | One key, `record`, ~250 bytes (bottles, rooms, stamps, works looked at, thieves caught) |
| Mesh | 4 messages/s, 200 B as JSON | A presence every 2.5 s, ~30 B |
| UI objects | 128 | One canvas and at most one QR |

`on_tick(ms)` runs every 30 ms. Movement uses the elapsed time, never the tick
count.

### Static scenes don't repaint

The canvas keeps its pixels between ticks. Scenes marked `static` (title, cards,
plaques, QR, pause, grids, map, finale, about, lanyard) draw once and then only when
something changes (`dirty`: a button, a push or pop, a toast, a scene calling
`invalidate()`). A badge in Lanyard mode spends almost no CPU, which saves
battery when it's worn all day.

## Lua 5.5, 32-bit

The badge runs Lua 5.5 built with 32-bit numbers: integers are int32
(`math.maxinteger` is 2147483647) and floats are single precision. The host
(wasmoon) is Lua 5.4, 64-bit. Rules that keep both identical:

- The RNG masks with `& 0xFFFFFFFF`, which is a no-op on int32 and correct on
  int64. Shifts are logical in both.
- Bit-level work (base32, bitsets, colours) stays on small integers.
- No integer constant over 2^31; no float precision assumptions beyond ~7 digits.
- No `string.pack` 64-bit formats, no `math.maxinteger` arithmetic.
- A `for` loop's variables are read-only in Lua 5.5: copy one into a `local`
  before changing it. A test checks `src/` for this, because the host can't.
- Canvas coordinates must be integers (`gfx.lua` floors them).

The sandbox has no `io`, `os`, `debug`, `package` or `load`.

## The headless badge

`tools/lib/host.mjs` is a small Solana OS in Node: wasmoon runs the built
package with the same callbacks, the subset of the API Night Shift uses
(`ui.canvas`, `ui.qr`, `led`, `storage`, `mesh`, `sys`, `badge`, `json`), the
same sandbox, and the same limits: the instruction budget per callback, storage
size, mesh rate and size, QR size and text length. It has a fake clock and
deterministic randomness. Screenshots are its canvas, pixel for pixel; QR codes
draw as placeholders.

It is not the firmware. It can't see Lua 5.5 changes, the real fonts or the
real QR renderer, so a build should also run on the real emulator before a
release (see [BADGE.md](BADGE.md)).

`pnpm play` (`tools/play/`) runs the same host in real time behind a small HTTP
server. Frames go to the page as RGB565 over server-sent events, and buttons
come back as POSTs. The server also lists and serves the package at `/app/`
with CORS headers, for loading it into the real emulator.

`mosa_debug` (end of `main.lua`) is a small global test seam: scene state,
teleporting to a bottle, travelling synchronously. Harmless on hardware.
