# Solana: trust tiers for the badge

*Written for the earlier Solana DEF CON badge platform (ESP32-S3, mics,
ESP-NOW). Night Shift now runs on Solana OS on the Breakpoint 2026 badge; see the
[changelog](../CHANGELOG.md) for what changed.*

The badge is a Solana device in a literal sense: every one generates an
Ed25519 keypair on first boot, preferably inside its NXP SE050 secure element,
and its public key **is a Solana address** (the badge ID is its first 8 base58
characters). MOSA is a Solana museum: tickets, postcards and finds are minted
as compressed NFTs (Bubblegum) and paid for with a wallet.

The design problem is trust. The app is open-source Lua, so anything it can
compute, anyone can compute. Each tier below adds a stronger proof, and each
one is useful on its own.

## Tier 0: links (shipped)

The badge prints canonical MOSA links. Collecting happens in the museum,
with the visitor's own wallet, through MOSA's existing payment and minting
paths. The badge holds no keys and makes no claims. **Nothing to abuse.**

## Tier 1: the shift report as a claim (badge shipped, museum next)

`?shift=<code>` encodes rooms visited and bottles found (layout in
`tools/lib/shift.mjs`, the reference decoder). Treat it as **a claim, not a
proof**: anyone could type a perfect code. So only grant what's fine to grant
on an honest-looking claim:

- a **free, one-per-wallet "Night Shift" commemorative** collectible (MOSA
  already enforces one-per-wallet for free pieces), and
- the welcome and stats (personal, harmless).

Never gate anything scarce or paid on tier 1.

## Tier 2: proof of presence via booth beacons (next)

A MOSA-run badge at the booth or party runs a tiny beacon app that broadcasts
a token over ESP-NOW every few seconds:

```
MOSA1 B <window> <tag>
tag = first 8 bytes of HMAC-SHA256(beacon_secret, "<event>|<window>"), base32
window = minutes since the event epoch, // 5
```

- The **secret lives only on the beacon badge** (pushed over USB, never in the
  public repo) and in MOSA's API env. Visitor badges just relay what they
  heard: Night Shift stores the latest `(window, tag)` per event and appends it
  to the shift report (`&b=<window>.<tag>`).
- The API recomputes the HMAC for that window (±1 for clock drift). A valid tag
  proves the badge was within radio range (tens of metres) of the beacon in that
  window. Tags are replayable within a window, so the claim is "was at the
  event", not "is this person". That's the right strength for a POAP-style
  **"Night Shift @ DEF CON" collectible**, a booth-only bottle, or a raffle.
- SHA-256 is all 32-bit arithmetic, so it runs fine on the badge's int32 Lua.
  The beacon's clock is its own uptime; the window epoch is set when it's pushed.

## Tier 3: badge signatures (needs a small upstream change)

Solana OS already signs with the badge key (`identity::sign()`, used to
register with the App Store broker) but doesn't expose it to Lua. The upstream
PR we'd propose to `spacemandev-git/solana-defcon-badge-26`:

```lua
badge.identity.pubkey()        --> base58 string (the badge's Solana address)
badge.identity.badge_id()      --> first 8 chars
badge.identity.source()        --> "secure element" | "software"
badge.identity.sign(message)   --> base64 Ed25519 signature, or nil + reason
```

With an OS-level confirmation (the OS, not the app, shows "Night Shift wants to
sign: <message>" and waits for SELECT), so a malicious app can't sign silently.

What MOSA gets:

- **Signed shift reports.** The QR carries `&pk=<pubkey>&sig=<sig>` over
  `mosa-shift:1:<code>:<beacon tags>`. The API verifies with the badge's own
  address. One badge, one claim; forging needs the secure element.
- **Badge-bound passes.** Mint the Night Shift pass **to the badge's own
  address**, which is a real Solana wallet whose key can't leave the SE050. The
  badge becomes a hardware-held collectible: your MOSA pass lives on your
  lanyard.
- **Sign in with your badge.** The museum shows a nonce as a QR; the badge
  can't scan, but it can sign a short code typed into it with the D-pad, or
  receive the nonce over the BLE bridge. That links the badge address to the
  visitor's main wallet in MOSA's people table.

## Tier 4: the pocket gallery (later)

Online mode (Wi-Fi or the phone's BLE bridge): fetch what a wallet holds from
MOSA (`/finds/me`-style read, or DAS for the badge's own address) and show it
as the lanyard slideshow, each piece's QR one press away. Needs a
small-thumbnail endpoint (≤ 96 px PNG) since the badge decodes at most 256 KB
images.

## What never goes on the badge

- Wallet seed phrases or the visitor's own keys. The badge key is the badge's.
- Payments. Collecting happens in the museum, in the visitor's wallet, through
  MOSA's existing audited flows (`docs/WALLET_COMPAT.md` in the MOSA repo).
- Anything that trusts the phone bridge for integrity: the phone terminates TLS
  (Solana OS README, "Phone bridge"), so bridged data is display-only.
