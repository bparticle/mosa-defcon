# Pixel art for the bottles

Every bottle on the badge is a **16×24 sprite with at most 15 colours plus
transparency**. It shows at 1× in BOTTLES, 3× on the find card and 4×
on the title screen.

There are two sources, and the sync picks one per bottle:

| Source | Where | When |
| --- | --- | --- |
| **Hand-made** | `art/pixel/<collection>/<piece>.png` | If the file exists, it's used exactly as drawn. |
| **Automatic** | the piece's cover render from the MOSA API | Fallback. Background removed, stood upright, a mode filter per pixel, 7 colours, despeckled. |

`docs/pixel-sheet.png` (`pnpm pixel sheet`) shows every bottle's cover next to
its badge sprite, marked HAND or AUTO. Hand-made art is how a bottle goes from
"recognisable" to "belongs on this badge".

### The works

The art on the walls (Community Gallery, the Poet Toads show, the Sirials) is
pixelized by the sync, not drawn by hand, to look like the bottles rather than
a shrunken thumbnail. The image is fitted to at most 24×24 at its own aspect.
A palette of 7 flat colours is picked from the full-size image (4 for an ink
drawing, which most Sirials are), and each sprite pixel takes the colour its
8×8 patch holds most of: a vote, never an average, so there's no blur. Rarer
colours vote a little louder, so eyes and outlines survive. Ink drawings get
their dark lines thickened first, and pixels left alone with no same-coloured
neighbour are cleaned up. There's no transparency (a work is a whole
rectangle). A miniature is a likeness, not a copy. It hangs on the
wall as a 9×9 sample in a frame, and shows at the largest whole scale that fits
on the art card and in THE ART, in a paper frame on a dark mat. A video work
uses its poster frame.

## The rules for hand art

- Exactly **16×24 px** PNG.
- Every pixel is **fully transparent or fully opaque**: no anti-aliased edges.
- **At most 15 colours.** The badge stores colours as RGB565, so two shades
  that differ only in the lowest bits merge into one.
- File name: the piece's id from `mosa.lock.json` → `registry.pieces`, for
  example `art/pixel/bottle/bottle-silo.png`.

`pnpm pixel check` validates every file. `pnpm sync` refuses to run if a hand
sprite breaks a rule, so a bad file can't reach a badge.

Tips that matter at this size:
- **Bottles stand straight.** The cover renders lean about 5° in the frame, like
  the static posters. At 16×24 that lean is a staircase down every edge and
  smears the label, so the automatic sprites are stood upright before they are
  snapped to the grid (`pixelize` in `tools/lib/pixel.mjs`; shapes with no long
  axis, like a face or an hourglass, are left as drawn). Draw hand art
  upright too: vertical sides, cap and neck centred over the body. Imported
  images are straightened the same way.
- **The silhouette is the identity.** The record shows unfound bottles as flat
  plaster casts of their shape, so the outline alone should still say "this one".
- One idea per bottle: the label's main colour block and one motif. A face, a
  logo or a word won't survive at 8 px wide; a colour band and a shape will.
- 4 to 8 colours usually reads better than 15. Pick a dark, a mid and a light
  for the glass, and spend the rest on the label.
- Keep a dark pixel or two of edge: the card and the title put the sprite on a
  near-black well (`#181818`), and the record puts it on `#0b0b0c`.

## Workflow

```bash
pnpm pixel starter      # art/starter/<c>/<p>.png: the automatic sprite for every bottle with no hand art (1x + @8x)
# edit a starter in Aseprite (or Pixelorama, Piskel, Photoshop with nearest-neighbour), save to art/pixel/<c>/<p>.png
pnpm pixel check
pnpm sync && pnpm build # the sprite is in the app
pnpm play               # look at it on the emulator; or pnpm pixel sheet
```

To bring in an image from anywhere else (an AI generator, a drawing, a photo):

```bash
pnpm pixel import path/to/image.png bottle/bottle-silo [--colours 8]
```

This snaps the image to the badge grid: it clears a flat background, takes
the commonest colour in each cell (crisp, unlike averaging), reduces the
palette and drops lone specks. The result goes straight into `art/pixel/`.
Open it afterwards and fix it by hand.

## Can ChatGPT do this?

**Not on its own.** Image models (ChatGPT/DALL·E, Midjourney, most Stable
Diffusion checkpoints) draw something that *looks like* pixel art at 1024 px.
It isn't: the "pixels" aren't on a consistent grid, they come in different
sizes, the edges are anti-aliased, there are hundreds of colours, and a 16×24
design has no room for the detail they add. Shrinking that output gives mush.

What works, best first:

1. **An artist, by hand.** For a museum of artists it's also the best story:
   invite each bottle's artist to pixel their own 16×24. Send them the starter
   (`pnpm pixel starter`) and the rules above. A 16×24 sprite takes a pixel
   artist 15 to 45 minutes.
2. **Starter + cleanup** (no artist needed). The automatic sprite already has
   the right size, silhouette and palette. 10 minutes in Aseprite per bottle
   (simplify the label to one motif, clean the outline, fix the highlight)
   gives most of the hand-made quality.
3. **A tool built for real pixel art**, then `pnpm pixel import` and cleanup.
   PixelLab and Retro Diffusion work at the real pixel size and stick to
   palettes. Give them the cover as the reference image and ask for 16×24 or
   32×48 (then import).
4. **ChatGPT as a sketch source**, then `pnpm pixel import --colours 6` and
   real cleanup. Usable for ideas, not as final art.

If you do use an image model, a prompt along these lines gets the closest
(attach the cover render):

> Pixel art sprite of this bottle, exactly 16 pixels wide and 24 pixels tall,
> shown enlarged with hard square pixels on a strict grid. Front view, upright,
> centred, the bottle filling the height. Limited palette of 6 colours, flat
> colours, no gradients, no anti-aliasing, no dithering, no outline glow.
> Simplify the label to its main colour and one bold shape. Plain flat
> magenta (#ff00ff) background.

The flat magenta background lets `pnpm pixel import` remove it cleanly.
Whatever produced the image, judge it at 1× and 3× on the badge
(`pnpm play`), not at 8×.
