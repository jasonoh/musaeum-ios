# The downloaded shelf's row glyphs — evidence

The owner reported the row's trailing icons as misaligned, from a screenshot of the **Downloaded** screen: *"the icons for read/share are not properly aligned"*. This directory holds what the report was, what was measured, the frames that decided it, and the rule the change landed.

Taken 2026-09-24 on iPhone 17 Pro / iOS 26.1 (1206 × 2622 px, **3× — divide the pixel numbers below by 3 for points**) through `scripts/live-probe.sh`, against the probe profile's own library. The Mac was **down** for every run here (`lsof -nP -iTCP:8789 -sTCP:LISTEN` empty): the shelf is the screen that works without it, and the row's geometry does not depend on who answered.

## The report, in pixels

`owner-report.png` is the report's own image — the shelf's first row, cropped and resized (its glyphs measure **0.88** of the probe frame's, so its pixels are not comparable to the frame's; the frames are the measurement and this is the report).

It carries **three thin red rules** across the icon area — at `y 306` (`x 1055…1230`), `y ≈332` (`x 1073…1213`) and `y 356` (`x 1181…1207`) — and the row's own ink sits between them: the gold read glyph at `y 310…350`, the muted share glyph at `y 308…356`. Read as a pair of brackets, that is the whole of the report: the two glyphs do not share a **top** (2 px apart) and do not share a **bottom** (6 px apart).

**Those rules are not the app's drawing.** The same screen captured from a `simctl` launch, scanned for red ink in the same region with the same thresholds, returns **0 rows** — `shelf-before.png` and `shelf-after.png` both. So they are mark-up on the screenshot (or an overlay only an Xcode-attached launch draws), and nothing in the app draws them.

## What was measured, and by what

The instrument is `scripts/measure-glyphs.swift` — a pixel ink-box measurement of a band of a frame, one run per glyph, at a luminance threshold of `0.45`. It is committed rather than rebuilt because this is the third time this repo has measured a glyph against its neighbour by hand (the library bar's four controls, the cover box, and now this), and the numbers below are worth being able to re-derive:

```bash
swift scripts/measure-glyphs.swift docs/evidence/downloads-row-alignment/shelf-before.png 380 620
```

The band `y 380…620` is row one and nothing else: its cover, its title and its two trailing glyphs. Row two (`y 620…900`) was measured the same way and agrees, which is why the table below carries two rows of numbers rather than one.

| Row | Glyph | Ink, before | Ink, after | Ink centre, before | Ink centre, after |
| --- | ----- | ----------- | ---------- | ------------------ | ----------------- |
| 1 — *Negotiation Genius* | read `book` (gold) | 55 × **46** px | 55 × **46** px | y 492.5 | y 492.5 |
| 1 | share `square.and.arrow.up` (muted) | 44 × **56** px | 36 × **46** px | y 493.5 | y 493.5 |
| 2 — *Caliban's war* | read `book` (gold) | 55 × **46** px | 55 × **46** px | y 780.5 | y 780.5 |
| 2 | share `square.and.arrow.up` (muted) | 44 × **56** px | 36 × **46** px | y 781.5 | y 781.5 |

So the report was **one fact, not two**: the share glyph drew **56 px of ink against the read glyph's 46** — a fifth taller, standing out of a pair that has nothing else in it to say which of the two was the right size. The vertical half of the report is *not* reproduced by the measurement: the two ink centres were level within **1 px** (0.33 pt) before the change, so this pair needed no optical nudge — unlike the library bar, where the same glyph sat 3 px low and took a `-1 pt` offset (`LibraryScreen.symbolOffsets`).

**Why the sizes differed at all:** SF Symbols each fill their own em box, so two symbols at one font size do not draw two equal marks. That is the library bar's own defect, one screen over, and this row had inherited it — the bar's fix measured its four controls (65 / 65 / 61 / 65 px, of which the share glyph was the outlier at 71) and gave each symbol the size its own shape needed; the row had kept the single `.body` it started with.

## What the change is

`DownloadsScreen` now carries the row's two sizes in one measured table — `readGlyphSize` 17 pt, `shareGlyphSize` **14 pt** — instead of applying one `.body` to both glyphs. **The read glyph keeps the size it had** (it is the row's own tap), and the share glyph, the door slice 5 added beside it, is the one that moves. 14 pt is not arithmetic: SF Symbols snap to optical sizes, so `17 × 46/56 = 13.96` was only the starting point, and the frame is what decided it — at 14 pt the glyph draws exactly the read glyph's 46 px.

The rest of the row is untouched, deliberately: the two glyphs' horizontal rhythm (the read glyph has no frame of its own, so the pair sits **close together and away from the row's edge** — 18 pt between their inks against 32 pt from the share glyph to the screen's edge) groups them, and moving the read glyph into its own 44 pt box would have spread that gap to 29 pt and taken the grouping with it. The share door's 44 × 44 tap target, the two colours (gold = the row's own tap, muted = the second thing) and the separate tap targets are all as slice 5 left them.

## The frames

| Frame | The run | What it shows |
| ----- | ------- | ------------- |
| `shelf-before.png` | `TAG=downloads DOWNLOADS=1` on the row's own sizes | The whole screen — the shelf's two rows, drawn entirely from the phone's disk with no Mac listening. The report's state. |
| `shelf-after.png` | the same run, the change in | The same two rows, the pair on one ink box. |
| `rows-before.png` / `rows-after.png` | band crops, `y 380…900` | Both rows whole, so the reading is two rows and not the one the report happened to crop. |
| `rows-before-after.png` | the two bands stacked | The comparison, in one image. |
| `glyphs-before.png` / `glyphs-after.png` | band crops, `y 430…560`, `x 920…1206` | The pair alone, at twice the linear scale of the stacked image above. |
| `glyphs-before-after.png` | the two glyph crops stacked | The defect and the fix, side by side of each other. |
| `owner-report.png` | the owner's own screenshot | The report as received, with its three red rules. |

## The log lines

Every run's own words, from `Documents/probe.log` in the app's container — the frame is the decider here, and this is what makes the frame's provenance explicit: no Mac answered, and the shelf still had rows to draw.

```
library failed the Mac is not answering — Could not connect to the server.
probe downloads shelf rows=2
```

**The second line is the new seam.** `DOWNLOADS=1` pushes the shelf's screen by state, because the door to it is a `NavigationLink` and `simctl` taps nothing — the same shape as `SHEET=1`, `UPLOAD_SHEET=1` and `DETAIL=`, and it was the revival condition `tasks.md` had already written for this screen (*"A seam onto the downloads shelf … revived the next time a slice wants a frame of that screen"*).

## What no run decides

- **The two doors' taps.** That a tap on the read glyph opens the book and a tap on the share glyph opens the system sheet is a human frame: `simctl` presents no sheet and taps nothing. What the frames here decide is the row's *look*; the tap targets are unchanged by this change and are the same ones slice 5's AC-deciders covered.
- **A narrower screen.** The reading is at 402 pt. The row is a `List` with a flexible title between a fixed cover and the glyph pair, so the arithmetic is comfortable — but it is arithmetic and not a frame.
- **VoiceOver.** The share glyph's label is asserted in the source (`Share <title>`), and how it sounds is a human frame.
- **The toolbars.** This change touches `DownloadsScreen`'s row and adds a navigation seam to `LibraryScreen`; the library bar's own measured tables are not on that path and were not re-measured.
