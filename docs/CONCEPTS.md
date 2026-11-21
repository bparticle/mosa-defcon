# Concepts: bringing M.O.S.A. to the Solana badge

*Written for the earlier Solana DEF CON badge platform (ESP32-S3, mics,
ESP-NOW). Night Shift now runs on Solana OS on the Breakpoint 2026 badge; see the
[changelog](../CHANGELOG.md) for what changed.*

The question: what can a 320×240 screen, six buttons, two RGB LEDs, two
microphones, ESP-NOW, BLE, Wi-Fi and a secure element holding a Solana key do
for a brutalist 3D museum? It can't render the museum. It can be a **door into
it**: something people carry around DEF CON that sends them, one scan at a time,
to the full-resolution museum on proper hardware.

## What the badge actually gives us

From the Solana OS SDK (`vendor/solana-badge/firmware/solana-os/README.md`, and
[solanadefcon.com/os](https://solanadefcon.com/os/)):

| Capability | What it means for MOSA |
| --- | --- |
| Lua 5.4 apps, 1 MB heap, 250 ms per callback | A real game loop, as long as heavy work is spread across frames |
| **App Store: any public GitHub repo's `scripts/*.lua`, sent to a badge by its ID** | Distribution with no flashing, no cable. One file, ≤ 96 KB. A booth can push the app to a visitor's badge on the spot |
| 320×240 LCD, persistent framebuffer | Floorplans, label cards, and **QR codes big enough to scan from a metre away** |
| Two WS2812B LEDs | Ambient signals people notice across a room: a "metal detector" that blinks faster near a find |
| Stereo PDM mics | A physical verb: **blow into the badge to pop balloons** (MOSA's core mechanic is popping balloons) |
| ESP-NOW (badge to badge, no AP) | Social play without a server: see other MOSA players nearby, wave, unlock things together |
| HTTP over Wi-Fi or the phone's BLE bridge | Live data when online: catalogue, standings, art |
| Ed25519 identity in the SE050 secure element | Every badge **is a Solana address**. Not exposed to Lua yet (see [SOLANA.md](SOLANA.md)) |

The DOOM port proves the hardware can push pixels. It also shows the trap:
reproducing the 3D museum in miniature would be a worse version of the real
thing. The badge should do what only the badge can do.

## Options considered

Scored 1–5 on: **ship speed** for an MVP, **funnel** strength (how directly it
moves people into the HD museum), **MOSA-ness** (does it belong in the
building), and **badge-native** (uses what's special about the hardware).

### A. Night Shift: the museum after hours, top-down ← **MVP, built**

You are the janitor of MOSA (the BP26 Janitor Room lore: *the janitor never
left*). The rooms are the real floorplans, derived from MOSA's own room claim
volumes, portals and furniture. It's dark; you carry a torch. The bottles from
MOSA's live **MOSA Bottles** collection (community artists, real pieces) are
littered where the catalogue hunts them. Balloons drift; pop them (SELECT, or
blow into the mics). Every find opens a museum label with a **QR to that exact
piece in the HD museum** (`mosa.center/at/find/<collection>/<piece>`), where it
can be collected on Solana. Rooms get stamped with MOSA's own quest goals.

- Ship speed 4 · Funnel 5 · MOSA-ness 5 · Badge-native 4
- Why it wins: every mechanic is something MOSA already has (rooms, balloons,
  finds, stamps, canonical links), so the badge is a faithful trailer and every
  find hands off to the museum. It works with **zero changes to the MOSA repo**:
  canonical find links already exist.

### B. Lanyard: the walking billboard ← **built into the MVP**

Leave the badge alone for 30 s and it becomes a poster: a big QR to MOSA and a
slowly rotating bottle, LEDs breathing in the art's colour. Every badge running
the app advertises the museum to everyone the wearer walks past. Costs the
wearer nothing; it's the highest-reach thing here.

- Ship speed 5 · Funnel 4 · MOSA-ness 4 · Badge-native 5

### C. Shift Report: carry your night into the museum ← **MVP side, museum side next**

One QR that encodes everything you found and every room you stamped
(`?shift=<code>`, 13 base32 characters today). The museum can read it back to
welcome the visitor, show their night, and grant a commemorative collectible.
The badge already prints it; the museum side is specified in
[MOSA-INTEGRATION.md](MOSA-INTEGRATION.md).

- Ship speed 4 (badge done) · Funnel 5 · MOSA-ness 4 · Badge-native 3

### D. Other janitors: proximity play over ESP-NOW ← **MVP-lite, built**

Badges running Night Shift announce themselves every 2.5 s. You see how many
other janitors are in range and can wave (both badges' LEDs flash green). The
one **mythical** bottle never appears to a janitor working alone; it can only
turn up when another badge is near. That turns a hallway encounter into a
reason to stand next to a stranger, and a story to tell.

- Ship speed 4 · Funnel 2 · MOSA-ness 3 · Badge-native 5

### E. Booth beacon: proof of presence (next)

A MOSA-run badge at a booth or party broadcasts a rotating token over ESP-NOW.
Badges in range pick it up and fold it into the shift report. The museum
verifies the token server-side, so "was at the MOSA booth at DEF CON" becomes
something a wallet can actually prove, POAP-style, with no secret on visitors'
badges. See [SOLANA.md](SOLANA.md) §2.

- Ship speed 3 · Funnel 4 · MOSA-ness 3 · Badge-native 5

### F. Badge as wallet: sign with the secure element (later, needs upstream)

The badge's Ed25519 key is a Solana address, but Lua can't reach it. A small
upstream PR to Solana OS (`badge.identity.pubkey()` / `badge.identity.sign()`)
would let the app sign its shift report with hardware-held keys, and let MOSA
mint a **badge-bound Night Shift pass straight to the badge's own address**.
"Sign in with your badge" at the museum door.

- Ship speed 2 · Funnel 4 · MOSA-ness 3 · Badge-native 5

### G. Pocket gallery: your MOSA collection on your chest (later)

Online mode: fetch what a wallet (or the badge's own address) holds from MOSA
and show it as a slideshow with the piece's link as a QR. Your collection
becomes your badge's screensaver. Needs a small-thumbnail endpoint on the API.

- Ship speed 3 · Funnel 3 · MOSA-ness 4 · Badge-native 3

### H. Sound room: the mics as an instrument (exploratory)

MOSA has spatial music zones authored per room. A badge app that turns the
room you're "in" into its soundtrack's visualiser and lets the crowd's noise
level fill a meter (the DEF CON floor is loud) until a balloon drop happens
everywhere at once. Fun, weak funnel.

- Ship speed 3 · Funnel 2 · MOSA-ness 3 · Badge-native 4

### I. A standalone arcade game as an advert (considered, not chosen)

Something like a balloon shooter in MOSA's colours, unrelated to the rooms. It
would be easy to make but it isn't MOSA's identity, and the hand-off to the
museum would feel bolted on. Night Shift already is the game, and its content
is real MOSA content.

## The plan

1. **Now (v0.1, this repo):** A + B + C (badge side) + D. One app, `mosa`,
   installable from the App Store. No MOSA code changes required.
2. **Next:** the museum reads `?shift=` and welcomes badge visitors; booth
   beacon (E); `/at/room/<id>` canonical links so badge links land in their room.
3. **Then:** upstream `badge.identity` (F) and the pocket gallery (G).

See [FLOW.md](FLOW.md) for the visitor journey end to end.
