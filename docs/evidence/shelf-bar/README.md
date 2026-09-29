# The bar's own width — the shelf bleed, and what it cost

The owner's report of 2026-09-29, with his own frame beside this file (`owner-portrait.png`):

> the main "all books" page on the ios companion looks perfect. however, once you click into a shelf, this bleed happens and won't go away unless turned to landscape. all shelves, regardless of shelf name length, displays incorrectly in portrait, correctly in landscape

**What it was, in one line: the in-shelf order label is the Mac's own *Date Added to Shelf, Newest First* — 255.5 pt at the bar's 17 pt — and with it in its capsule the bar's title row asked for 532 pt on a 402 pt screen.** The chrome is drawn as a child of the screen's top-`ZStack` (so the list can run *behind* it — the library's own rule), and a `ZStack` is as wide as its widest child: the *screen* became 532 pt wide, `content` — the grid — was laid out to match, centred, and clipped about 65 pt off each edge. Nothing about a shelf's **name** was involved, which is why every shelf bled by the same amount; landscape was never wrong because 874 pt holds a 532 pt row.

Two consequences of the same shape are in the before frame. The row's contents were laid out from its leading edge, so the wordmark lost its first letters while the capsule overhung the right — the clip is not symmetrical between them, only between the *screen's* two edges. And the grid re-counted its columns: a 532 pt grid fits four 114 pt columns where 402 pt fits three, so the shelf screen was showing *more* columns than the page it was imitating.

The instrument did not exist when the report arrived, so it was built here and the `HEAD` reading taken with it: `bar-before.png` is a build of `HEAD` (`9f3bf35`) with **only** the three width lines added to `LibraryScreen` — no layout change — run with a shelf open in portrait.

## The readings

Every line below is the app's own (`LibraryScreen`): the screen, the chrome and the bar's capsule reported as measured geometry, so a row that has outgrown the screen is a *number* rather than a clipped edge.

| Run | `library screen width` | `library bar capsule` | `library chrome … overflow` | Frame |
| --- | --- | --- | --- | --- |
| `HEAD` + the width lines, shelf open, portrait | 402.0 | **373** | **532 … overflow=130** | `bar-before.png` |
| the fix, the same shelf, portrait | 402.0 | **223** | **402 … overflow=0** | `bar-after.png` |
| the fix, a 45-character shelf name open | 402.0 | 223 | 402 … overflow=0 | `bar-long-shelf-name.png` |
| the fix, *Read Status (reversed)* — the longest order the bar can be asked to draw | 402.0 | **292** | 402 … overflow=0 | `bar-guard-read-status.png` |
| the fix, *Recently Added* — the longest of the menu's eight | 402.0 | 238 | 402 … overflow=0 | `bar-live-recently-added.png` |

Those capsule widths are the whole of the arithmetic, and each is its label plus the capsule's own chrome: **117.5 pt** (its 36 pt of padding, the share and sort glyphs, and the 22 pt between them), which is `373 - 255.5` and `292 - 174.5` agreeing. *Recently Added*, at 120.2 pt of label, is the widest order the menu can produce; **Shelf: Newest** is 105.1.

The four runs' own logs are beside this file: `run-before.log` and `run-after.log` are the pair the table's first two rows come from. What they say, in their own words:

```
library screen width=402.0
…
library chrome width=402 height=219 screen=402 overflow=0
library chrome width=532 height=219 screen=402 overflow=130      ← the shelf opens
library bar capsule=373 screen=402 margin=16
```

```
library screen width=402.0
…
library chrome width=402 height=219 screen=402 overflow=0
library bar capsule=186 screen=402 margin=16
library bar capsule=223 screen=402 margin=16                     ← the shelf opens
```

## What changed

1. **The bar's label is short, and it is the bar's alone.** `LibrarySort.barLabel` draws `Shelf: Newest` / `Shelf: Oldest` for the shelf's pair and every other pair's own label otherwise; the sort *menu* still offers the Mac's sentence, and the wire still carries `shelf_added`. A phrase written for a menu row is not a phrase for a 402 pt bar, and the scope chip beside the search field already says which shelf is open.
2. **The row gives way by construction.** The title is laid out last (`.layoutPriority(-1)`) and may go to nothing — `screenTitle`'s last rung is a zero-width view, so `ViewThatFits` drops the wordmark rather than overhanging; the capsule keeps no `.fixedSize()` any more, so its label (`.lineLimit(1)`) truncates rather than pushing the row out. The controls are still asked for their width *first*; what is gone is the possibility that neither of them can be refused.
3. **The scope chip outranks the field's hint.** Both are squeezed in the narrowing row once the scope is on it: the chip is asked for its width first and the field keeps a 120 pt floor, so a shelf named longer than half the row truncates the *chip* rather than swallowing the field. With `gov & politics` the chip is whole and the field's prompt is `Search "g…"` — the two of them plus the filter genuinely do not fit 370 pt, so one of them must shorten, and the state is worth more than the hint.
4. **The width is an instrument.** `library screen width=`, `library bar capsule=` and `library chrome width=… overflow=` are the three lines this report lacked; a future row that outgrows the screen reports it instead of only showing it.

## What was exercised by accident, and kept

The build left in `./DD` after the guard's own mutation check (`barLabel` reverted to the Mac's sentence, source restored, **app not rebuilt**) was run once before it was noticed — the run after `bar-before` in this directory's history. It read **`capsule=349`, `chrome=402`, `overflow=0`**: the label lost its tail (349 is the row's width, not the sentence's) and the page kept its edges. That is the truncation path, which no label in today's vocabulary reaches — the longest of them, *Read Status (reversed)*, is absorbed by the title's last rung instead — and it is kept here as the one reading of it there has been.

## What no run decided

- **Landscape.** This machine has no Simulator UI — `simctl` has no rotate verb and `Simulator.app` is not in this Xcode installation — so no landscape frame can be taken here, which `docs/evidence/header-recede/` already records. What is measured is what the landscape case turns on: the rule added here can only ever *remove* width (a title laid out last, a label allowed to truncate), so a row that fits 402 pt fit 874 pt before and still does; and the owner's own device is the landscape frame for this fix, as his report is its portrait one.
- **The sort menu's own rows** — the Mac's sentence, unchanged, and a tap that `simctl` cannot make. The bar's short form is what this fix puts on screen; the menu's full wording is the half a human frame sees.
- **Any shelf name longer than the one seeded here.** `bar-long-shelf-name.png` is a 45-character name and it truncates as designed; the rule is a *floor* on the field rather than a solver for arbitrary text, and a name longer still would shorten the chip further rather than the row.

## What was restored

- **The phone's stored sort** — the runs that judged labels set one, and the sort is *remembered*: `TAG=restore SORT=title:asc` put the profile back, and the run after it reads `sort=title:asc` (`docs/evidence/slice7/README.md`'s own warning about this).
- **The probe profile** (`~/.hermes/profiles/dev/cache/scratch/ios-probe`) now holds **8 books** and **two shelves** — *gov & politics* (5) and *Twentieth Century Politics and its Discontents* (3) — on port **8789**. Its books are hydrated from the EPUBs `seed-epubs.py` builds; the shelf file is hand-written and adopted on connect.
- **The owner's packaged app** on 8788 was never touched, signalled or read from; the dev app this work brought up was stopped by its own process tree.
