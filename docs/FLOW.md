# The flow: from a badge at DEF CON to the HD museum

The badge isn't a smaller museum. It's the door. Each step below either gets
the app onto more badges or moves someone from the badge to `mosa.center` on a
real screen.

```mermaid
flowchart TD
  subgraph Reach["1 · Reach: getting the app onto badges"]
    S1[Solana OS App Store] -->|install| APP[Night Shift installed]
    BOOTH[MOSA booth / party<br/>staff plug the badge in] -->|Run on badge| APP
    LANYARD[Someone else's badge<br/>in Lanyard mode] -->|scan| SITE
  end

  subgraph Play["2 · Play: on the badge"]
    APP --> TITLE[Title]
    TITLE -->|idle 30 s| LANY[Lanyard mode<br/>walking billboard]
    TITLE --> INTRO[The cupboard<br/>the janitor takes the flashlight]
    INTRO --> BRIEF[Tonight's rounds<br/>three works missing]
    BRIEF --> WALK[Night Shift<br/>real MOSA floorplans]
    WALK --> ART[Look at a work<br/>pixel miniature, label]
    WALK --> THIEF[Catch a thief<br/>hold the light on them]
    WALK --> FIND[Find a bottle<br/>museum label card]
    WALK --> STAMP[Room stamps<br/>MOSA's own goals]
    WALK <-->|mesh| PEERS[Other janitors nearby<br/>wave · mythical unlock]
    THIEF --> WAVE[All clear, for now<br/>the desk radios the next wave]
    WAVE --> THIEF
    WALK --> CLEAR[Dawn at 06:00<br/>the night's report]
    CLEAR -->|tomorrow| CALL[The desk calls in the evening<br/>a new night, a streak]
    CALL --> APP
    FIND --> REC[Bottles · shift report]
    STAMP --> REC
  end

  subgraph Handoff["3 · Hand-off: badge to phone"]
    FIND -->|QR| PIECE["mosa.center/at/find/&lt;c&gt;/&lt;p&gt;"]
    ART -->|QR| WORK[The work's own page<br/>or its room]
    CLEAR -->|QR| REPORT
    REC -->|QR| REPORT["mosa.center/at/bp26?shift=&lt;code&gt;"]
    LANY -->|QR| SITE["mosa.center/at/bp26"]
  end

  subgraph Museum["4 · The museum, in full resolution"]
    PIECE --> LAND[Arrive in front of that find]
    SITE --> LAND2[Arrive with a DEF CON welcome]
    REPORT --> LAND3[Your night, read back<br/>commemorative collectible]
    LAND --> MINT[Collect it on Solana]
    LAND3 --> MINT
  end
```

## 1. Reach

| Channel | How | Cost to the person |
| --- | --- | --- |
| **App Store** | Night Shift is submitted to the Solana OS App Store; a visitor installs it from the store on their badge. | A minute, no cable |
| **Booth install** | MOSA staff plug a visitor's badge in and use **Run on badge** with a pinned release (see [BADGE.md](BADGE.md)). | None |
| **Lanyard** | Every installed badge left idle for 30 s shows a scannable MOSA QR and rotating art. Strangers scan the wearer's chest. | None; it's the default idle state |
| **Word of mouth** | Mesh presence: badges with the app see each other. The mythical bottle only appears when two players are near. | Standing next to someone |

The App Store installs **one app package**, so the whole app (code, floorplans,
75 works and 41 bottles as pixel art) travels in `apps/mosa/`, with nothing fetched at runtime.

## 2. Play

- **Clock in.** On a first shift: 23:58, the janitor's cupboard. The janitor
  takes the flashlight off its hook and clicks it on; the bulb goes out.
  Every shift: security-camera footage of a thief lifting a work off its
  wall and running, then tonight's list: the three stolen works, as pixel
  art, and the rooms they were taken from, the first one door from the Lobby.
- **Rounds.** The flashlight is one hard cone ahead and a small pool at your
  feet; everything else is dark, with a faint memory of what you've seen.
  Exits glow.
- **Look.** The works hang where the HD museum hangs them. SELECT by one
  shows it up close, with its title, artist and room, and **SEE IT IN HD**
  shows the QR to the real work. Everything you've looked at is in THE ART.
- **Catch.** Thieves creep about in the dark. An empty frame tells you what
  was taken. Hold the light on a thief and a bar over their head fills until
  they drop the work. Dazzled, or hearing you close by in the dark (a "!"),
  they run for a door; reach it and they're away into the next room. The
  LEDs sweep as you close in, and the map blinks the rooms they're in.
- **Travel.** On the clipboard's map, SELECT on a room you've walked and
  the light closes in and opens there, like the HD museum's travel. A trip
  costs twenty minutes of the night.
- **The night.** The clock runs from 23:41 while you walk (the clipboard
  stops it). Catch a wave and it's **ALL CLEAR, FOR NOW**; after a calm the
  desk radios the next break-in, more thieves if you were quick, fewer and
  slower if you weren't. At 06:00 the lights come up on the dawn report:
  works back, works lost, the streak, the !LAMPs earned, what's still out
  there, and the shift report one scan away. [NIGHT.md](NIGHT.md) has it all.
- **Come back.** A new night every day, the same first break-in for every
  janitor that day. Keep a streak. After a first dawn the badge may let the
  desk call in the evening: one notification when tonight hasn't been worked.
- **Sweep.** Bottles from the live MOSA Bottles collection lie on the HD
  museum's find spots, picked as the catalogue hunts them. Walk into one to
  pick it up. The LEDs act as a metal detector: the nearest bottle's colour,
  blinking faster as you close in.
- **Stamp.** Entering a room and finding the Crocodile Vault: the same goals
  as MOSA's room programmes. An uncatalogued room stays off the museum map
  until you find it.
- **Meet.** Another badge running Night Shift nearby shows up on the pause
  screen. Wave. Work the same room and the mythical may turn up.

## 3. Hand-off

Every surface that names a piece of MOSA offers its link as a QR, dark on
light, sized for a phone at arm's length:

| On the badge | QR target | Exists today? |
| --- | --- | --- |
| A found bottle | `mosa.center/at/find/bottle/<piece>`, MOSA's canonical find link | **Yes**: lands in front of that find |
| A work, up close | The work's own link from MOSA's hung-works data (its Mallow or 6529 page); else its room's curated link, else the museum | **Yes**. Sirials open their room or the museum until MOSA's `/at/work/<id>` (lands in viewing mode) is built |
| Lanyard, About | The Janitor Room's curated link (`mosa.center/at/bp26`), found by the sync; else the museum | **Yes**. Nothing to author for the badge |
| Shift report | The same link plus `?shift=<code>` | **Yes**: the museum reads `shift` on any path |

Every URL the badge prints is checked at sync time with MOSA's own link
parser (`apps/frontend/src/lib/linkPaths.ts`), so the badge can't print a link
the museum doesn't understand.

## 4. The museum

The visitor arrives on a phone or laptop, in the real building, in front of
the thing they found in the dark. From there it's MOSA as usual: walk, look,
collect. The badge's job is done once they arrive.

What the museum can add to close the loop (specified in
[MOSA-INTEGRATION.md](MOSA-INTEGRATION.md)):

1. A welcome for badge visitors: the Janitor Room's own link (`/at/bp26`).
2. Read `?shift=`: "You swept 7 rooms and found 12 bottles on the night
   shift", and offer a free one-per-wallet **Night Shift** commemorative
   collectible through the existing free-find path.
3. Count badge arrivals (the `shift` parameter is the attribution), so we know
   what DEF CON brought in.
