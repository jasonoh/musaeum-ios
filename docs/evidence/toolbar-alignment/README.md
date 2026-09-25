# The library bar's alignment — evidence

The owner reported the library screen's control bar as *misaligned and janky*: "the `Send` icon/label set is misaligned with everything else to the right of it". This directory holds the frames that decided it, taken 2026-09-24 on iPhone 17 Pro / iOS 26.1 (1206 × 2622 px, 3× — so **divide the pixel numbers below by 3 for points**) through `scripts/live-probe.sh`, plus one frame from `HEAD` as the control.

The rule the change landed is in `LibraryScreen.barControl` and its two tables; the readings are below so the numbers that rule was derived from are not lost with the session.

## What was measured, and by what

The instrument is a pixel ink-box measurement of the bar's own band (`y 200…300`, a luminance threshold of `0.45`), taken on the same frame the eye looks at — a claim about geometry is not a source read. The bar's band is `y ≈ 215…300` in every frame here; nothing else on the screen is in it.

| Control | Symbol ink, before | Symbol ink, after | Ink centre, before | Ink centre, after |
| ------- | ------------------ | ----------------- | ------------------ | ----------------- |
| `Send` (share) | **73 px** | **65 px** | y 254.0 | **y 251.0** |
| filter ring | 66 px | 65 px | y 251.5 | y 251.0 |
| sort arrows | 62 px | 65 px | y 252.5 | y 252.0 |
| downloads ring | 66 px | 64 px | y 251.5 | y 251.5 |
| `Send` text cap | 39 px | 39 px | y 252.0 | y 252.0 |
| sort text cap | 38 px | 38 px | y 251.5 | y 251.5 |

So the *whole* of the report was two facts: the share glyph stood **73 px against the rings' 66 and the arrows' 62**, and the pair's ink centre sat **254.0 against 251.5** — one control in four, taller than the rest and hanging a point low. Everything else in the bar already agreed with everything else (the two text runs are one size, `39 / 38`, and level, `252.0 / 251.5`).

**Why the sizes differed at all:** SF Symbols each fill their own em box, so four symbols at one font size do not draw four equal marks — and the toolbar gives an item's `Image` its own symbol size, so `.font(.body)` on the label changes nothing about the glyph. That was measured, not assumed: a throwaway build with a different explicit size per control drew inks of `71 / 57 / 47 / 42` at `17 / 15 / 13 / 11` pt, i.e. **linear, 3.6–4.2 px per point** — which is the slope the tables in `barControl` are the solution to. The second frame of the pair is what the `-1` offset in `symbolOffsets` came from: equal ink was not yet level ink (the share glyph's box landed at `y 222…286` against the rings' `219…283`).

## The frames

| Frame | The run | What it shows |
| ----- | ------- | ------------- |
| `bar-before.png` | band crop of the frame on `HEAD`'s build | The report, in a frame: the share glyph visibly larger than the rings and hanging low, the sort's words and the downloads ring **gold**, `Send` and the filter parchment — a colour split that was no rule at all, only a `Menu` label and a `NavigationLink` taking the app's `tint` while a `Button` with its own `foregroundStyle` does not. |
| `bar-after.png` | band crop, the same band, the change | All four symbols at one ink box (`65 / 65 / 65 / 64`) centred within half a point of each other (`251.0 / 251.5`), and one colour: parchment. |
| `bar-after-filtered.png` | band crop with `FILTERS='status=reading'` | The one gold the bar is allowed: the filter's filled glyph and its count. 3.13's decider — *an active filter with a visible cause* — preserved exactly, its wording and its gold unchanged. |
| `bar-before-after.png` | the three bands stacked | The comparison, in one image. |
| `live-title-az.png` | `TAG=bar-live`, the Mac up on the probe profile (`http://100.125.135.108:8789`, 13 books) | The bar in the app's normal state: all four controls inline, `Send · filter · ⇅ Title A–Z · ring`. Items span `x 188…1117` = **310 pt**, capsule `x 178…1120` = **314 pt** of the 402 pt screen. |
| `live-filtered.png` | `TAG=bar-live-narrowed FILTERS='status=reading'` | Same, narrowed: the filter gold with its `1`, items `x 150…1117` = **323 pt** — still inline, so the count is inside the budget. |
| `live-recently-added.png` | `TAG=bar-live-recently-added SORT=date_added:desc` | **The finding this fix did not touch, and the reason it is committed.** With the longest order label iOS takes the sort control *and* the downloads ring off the bar and leaves a `•••` overflow: `Send · filter · •••`, items `x 603…1117` = **172 pt**. The remembered order — the whole point of the label 3a fought for — is behind a menu, and the bar shrinks from its leading edge. |
| `head-recently-added.png` | the same run against `HEAD`'s build | The control: **`HEAD` overflows identically**, so the overflow is not this change's — the change is `+1.3 pt` of items (the sort arrows gained a point of size; the share glyph lost two), which is why it is a finding to hand back rather than a regression to fix. |

## The log lines

Every run's own words, from `Documents/probe.log` in the app's container. The first two lines are a run with the Mac **down** (the probe profile's port free), which is the state the bar-only frames were taken in — the bar draws in every phase, and the filter's gold state is the app's own, not an answer from the Mac.

```
library failed the Mac is not answering — Could not connect to the server.
```

…and with the Mac up, in the order the runs were made:

```
library page count=13 total=13 limit=100 offline=online sort=title:asc q=- filters=- first=Caliban's war | Dragon Wing | The Hidden Palace
library page count=13 total=13 limit=100 offline=online sort=date_added:desc q=- filters=- first=Smoke Upload 20260924-164242 | Probe Upload 528 | Probe Upload 20260923-alpha
library page count=13 total=13 limit=100 offline=online sort=title:asc q=- filters=- first=Caliban's war | Dragon Wing | The Hidden Palace
library page count=2 total=2 limit=100 offline=online sort=title:asc q=- filters=status=reading first=Caliban's war | Negotiation Genius
```

**Two traps this run paid for, both cheap and both worth writing down.** (a) `SORT=` takes the app's own stored key, so the order whose label this bar is judged on is **`date_added:desc`**, not `added:desc` — a token the build does not know is *logged* (`probe: sort '…' is not one this build knows`), and a `grep` for the page line alone throws that line away, which is exactly how a run reads green while deciding nothing. (b) The probe profile is the throwaway one at **8789**; the owner's own packaged Musaeum held **8788** for the whole of this work and was never touched, signalled or read from.

## The overflow, and the decision it forced

Measuring the bar turned up something the report did not name, and it is bigger than the alignment: **at 402 pt the bar cannot hold four trailing controls and the widest order label at once, and iOS's answer is to take the sort control off the bar entirely.**

| Configuration | Run | Bar | Items |
| ------------- | --- | --- | ----- |
| four trailing items, `Title A–Z` | `TAG=bar-live` | `Send · filter · ⇅ Title A–Z · ring` | 930 px = **310 pt** |
| four trailing items, `Recently Added` | `TAG=bar-live-recently-added SORT=date_added:desc` | `Send · filter · •••` | 515 px = 172 pt |
| the ring moved to `.topBarLeading`, `Recently Added` | `TAG=bar-leading-recently` | trailing cluster still `Send · filter · •••` | 418 px = 139 pt |
| the ring out of the bar, `Recently Added` | `TAG=bar-noring-recently` | `Send · filter · ⇅ Recently Added` | 920 px = **307 pt** |

Two readings in that table are the reason the fix is what it is. **A leading item is not a way out** (`bar-leading-attempt.png`): the same ring in `.topBarLeading`, which looked free because the two groups read as separate in the source, left the trailing cluster overflowing exactly as before — so the toolbar's width is **one** budget, not one per group, and a hypothesis that looked obvious from the code was wrong in the frame. And **the ring's absence is what buys the label back**: three trailing items measure 307 pt with `Recently Added` and stay inline, where the same three with the ring beside them come to roughly 363 pt and collapse (`head-recently-added.png` is the control: `HEAD` collapses identically, so this was pre-existing and not introduced by the alignment work — that change is +1.3 pt of items).

So the shelf ring **left the bar** and kept a door on the screen instead, which is what the owner chose: the only one of the bar's four controls that is a *destination* rather than something done to the list is the only one that could leave.

| Frame | What it shows |
| ----- | ------------- |
| `bar-three-controls-recently-added.png` | The bar's three controls with the longest label — the reading that decided it. |
| `bar-leading-attempt.png` | The rejected hypothesis, kept because the next session will have the same idea: the ring leading, and the cluster still collapsed. |
| `shelf-row.png` | The door, in the screen's own idiom: `⤓ Downloaded … 1 book ›` on `Palette.raised`, under the search field and above the grid — the same strip shape as the filter bar and the upload's row. Captured after a real download through the app's own path (`TAG=shelf-seed BOOK=9e9ed0ee-…` → `probe downloaded id=9e9ed0ee-… format=epub serverPercent=0.42`), so the count is the phone's own. |
| `shelf-row-empty.png` | The other half, and it is a different decider from the row above: with the shelf emptied (`rm -rf <container>/Library/Application Support/Musaeum`) there is **no row at all** and the grid starts directly under the search field. The door exists exactly when it leads somewhere, which is the same shape the filter bar and the upload row already have. |

## What was not measured

- **The tap surfaces** are unchanged and unmeasured here: the sort menu's own contents, the filter sheet, and the upload sheet are untouched by this change and are `simctl`'s blind spot as always (they are decided by their own frames in `docs/evidence/slice3/` and `slice4/`). **The new shelf row's tap is one of them** — its `NavigationLink` is the same door the toolbar item used, and a tap is a human frame.
- **A device narrower than 402 pt.** The reading above was taken at 402 pt; a 393 pt screen has 9 pt less budget, and 307 pt of items leaves room for that, but the number is arithmetic and not a frame.
- **VoiceOver's reading of the two glyph-only controls** — the change adds `Filters` / `Filters, N on` labels, and that a label *exists* is a source fact; how it sounds is a human frame.

