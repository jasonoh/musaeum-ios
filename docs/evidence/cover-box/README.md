# The cover box's evidence

The owner's report of 2026-09-23, reproduced in the app and measured: **a cover was bounded by its own artwork instead of by its cell.** Rows came out at different heights, a landscape jacket overlapped the cells beside it, and a tall one rode down over its own title and author lines. The frames here are the same probe run on two builds; `CoverBoxTests` is the case that decides it from now on.

**This is a defect fix, not a slice.** No design decision moved (the Mac's own `BookCard.tsx` was already the shape the client meant to keep), the wire is untouched, and nothing in the Mac repo changed. The rule it restores is one the client already claimed: `CoverImage`'s 2:3 box.

- `grid-cover-box-before.png` — the tree before the fix, cover box following the artwork.
- `grid-cover-box-after.png` — the fixed tree, the same run.
- `grid-cover-box-before-after.png` — the two side by side (before left, after right).
- `grid-cover-box-before-after.txt` — the numbers read off both frames, and the unit-level ones.
- `cover-box-campaign.json` / `cover-box-campaign.log` — the campaign that shows the new cases decide.

## Reproducing it

```bash
cd ~/Projects/musaeum-ios
DEV=DE0B5601-7874-455E-A965-9AD80567C30E
CONT=$(xcrun simctl get_app_container $DEV dev.jasonoh.Musaeum data) && rm -rf "$CONT/Library/Caches"
TAG=box-before SORT=title:asc WAIT=25 ./scripts/live-probe.sh   # built from the tree before the fix
TAG=box-after  SORT=title:asc WAIT=25 ./scripts/live-probe.sh   # built from the fixed tree
```

**The library was given something for the defect to do.** A Mac-side `cover_thumb.jpg` normally arrives near 2:3 (the eight seeded covers here measured 0.64–0.75), and art that close to the box leaves a bleed of a few points — visible as uneven gaps, and easy to read as sloppiness rather than as a defect. So two covers were replaced in the probe profile's own copy of the library, on disk, where the cover route reads them:

| book | cover | shape |
| ---- | ----- | ----- |
| *Dragon Wing* (`97f2fd3e-…`) | red/green/blue bands with both extremes marked | **3:2 landscape** (300 × 200) |
| *Negotiation Genius* (`ef91875e-…`) | gold/magenta bands, the box's own top and bottom marked | **1:2 portrait** (100 × 200) |

The phone's `Library/Caches` is removed before each run: covers are fixed filenames and the contract carries `v=` for exactly this reason — a replaced cover is otherwise answered from a cache.

Both runs logged the identical library line, which is what makes the pair a comparison:

```
MUSAEUM_PROBE|library page count=8 total=8 limit=100 offline=online sort=title:asc q=- filters=- first=Caliban's war | Dragon Wing | The Hidden Palace
```

## What the frames decide

| | before | after |
| --- | --- | --- |
| row 1's widest contiguous cover run | **334.3 pt** — a cell is 114 pt, so the landscape jacket swallowed both neighbours | **115.3 pt** — the 114 pt cell and the 1 pt hairline, three times |
| the two gap strips (x 132–142, 260–270 pt) over row 1 | **15510/15510 cover pixels** each: no gap left to see | **0/15510** each |
| column 3's box height (the 1:2 jacket) | **229.3 pt**, against 172.3 pt for the 2:3 jackets in the same grid | **172.3 pt**, like every other cover |

## What the suite decides

`CoverBoxTests` measures the size the cover reports for a cell that proposes a width and leaves the height free — the proposal a `VStack` in a grid cell receives, which is the one the defect lived in:

| artwork | before | after |
| ------- | ------ | ----- |
| none | 114 × 171 | 114 × 171 |
| 2:3 | 114 × 171 | 114 × 171 |
| 1:2 | 114 × 228 | 114 × 171 |
| 3:2 | **256.7 × 171** | 114 × 171 |
| 1:1 | 171 × 171 | 114 × 171 |

The cause, plainly: `.aspectRatio(_:contentMode:)` fits the **proposal** to the ratio; it does not clamp what the child then reports. The ratio sat on a `Group` whose child was `Image.resizable().aspectRatio(contentMode: .fill)`, so the child answered with **its own** shape and the box grew to match — a layout rule with no error and no warning attached, which is why the probe frames taken before it and the whole unit suite read as passing. The fix moves the geometry onto a child with no intrinsic size (`Palette.raised`, which is the placeholder's colour anyway) and puts the artwork in an `overlay`, whose reported size cannot move its parent.

Three sites draw this view and all three are the same rule: the grid (the cell's width), the detail hero (124 pt → 186 pt tall), and a download's row (44 pt → 66 pt tall). **The other two had the defect too, measured on the unfixed tree**: at a fixed width the *width* was clamped but the height still followed the jacket, so a 1:2 cover gave the hero **124 × 248** and a download's row **44 × 88** — a book's detail page changed height from book to book. A wide jacket happened to land on 186/66 at those two sites (the clamp covers the width, and the ratio then supplies the height); the grid, with no width of its own, is where the width could run, which is why the owner saw it there first.

## What only a human can decide

That the artwork is **cropped into** the box rather than bleeding over it: `scaledToFill` plus the clip is the Mac's `object-cover`, and the frames show the crop (the landscape jacket's blue band, its right extreme marker included, sits inside the cell). A *tap* — opening a book's detail and seeing the hero at 124 × 186 — is a claim for a human frame, and `simctl` can drive none of it.
