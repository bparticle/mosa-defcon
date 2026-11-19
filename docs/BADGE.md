# On a badge

Night Shift is a Solana OS app for the Breakpoint 2026 badge (ESP32-C5,
Solana OS 2.4 or later). `pnpm build` writes the package to `apps/mosa/`:

```
apps/mosa/
  main.lua          the entry point
  app.json          id mosa-night-shift, permissions led + mesh
  *.lua, data/      the modules main.lua requires
```

## Run it on your badge

1. `pnpm build`.
2. Open [solana.com/breakpoint/badge/apps/submit](https://solana.com/breakpoint/badge/apps/submit)
   in Chrome or Edge (it needs WebUSB).
3. Drop the `apps/mosa` folder on the page.
4. Plug the badge in over USB and choose **Run on badge**.

The badge compiles a sideloaded app itself. The App Store compiles the apps it
installs. The same page submits a version to the store.

You can also copy the files over the badge's serial console with `lua recv` /
`lua put`, into `/sdcard/hh/apps/mosa-night-shift/`: `main.lua` and `app.json`
at the top, every other file under `files/`.

An app built for the older DEF CON badge platform (ESP32-S3) won't flash on
this badge; the flasher reports "That is an ESP32-C5, not an ESP32-S3".

## Check a build on the real firmware

The headless host in `tools/lib/host.mjs` is fast and scripted, but it is Lua
5.4 and a copy of the API. Before a release, run the build on the firmware
itself, compiled to WebAssembly:

- **Try in emulator** on the submit page, after dropping the folder; or
- the [Solana OS emulator](https://solana.com/breakpoint/badge/emulator).
  Its *Console* section shows the app's `print` output, script errors, and the
  peak heap when the app closes.

`pnpm play` also serves the package at `http://localhost:5317/app/files.json`
and `/app/<path>`, with CORS headers, for tools that load it into the emulator
page.

Walk through at least: splash → title → CLOCK IN → walk a room → CANCEL
(clipboard) → SHIFT RECORD → SHOW SHIFT REPORT (a real QR code), and LANYARD
from the title.

## What the firmware checked

Verified on the emulator (Solana OS 2.4, Lua 5.5) on 2026-11-19: every screen
above draws, keys arrive as `select`/`back` with a boolean repeat flag, the
QR codes are drawn by the firmware, and the peak Lua heap is ~0.6 MB of 6 MB.
Lua 5.5 made `for` loop variables read-only, and the host can't see that, so
`test/app.test.mjs` checks `src/` for it.
