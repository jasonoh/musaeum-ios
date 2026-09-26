# The library header recedes — evidence

The owner's report, 2026-09-25:

> the entire header (title + toolbar + search) is *fixed* to the top of the window, portrait and landscape. tho header should recede when scrolling as one expects, and reappearing when pulling down (as one expects), like safari

This directory holds what decided it: the frames from `scripts/live-probe.sh` on iPhone 17 Pro / iOS 26.1 (1206 × 2622 px, **3×** — divide any pixel number by 3 for points), the app's own log lines, and the mutation campaign that shows the rule's cases can fail.

## The rule

`Musaeum/Core/Library/HeaderReveal.swift` — a **travel** rule, not a position rule: which way the list is moving decides, and how far it has moved that way. 44 pt of travel one way moves the bar, and a change of direction discards the run (a reader who pushes 40 pt and then pulls 40 pt back has asked for the header, not for nothing). Two floors sit under it:

- **the band is the floor** — the chrome cannot leave until the list has gone by its own measured height, or it would slide away to reveal the background rather than content;
- **a pull at the top is a refresh** — the chrome never hides while the list is being dragged past its own start.

Safari's chrome behaves this way, and UIKit's own `hidesBarsOnSwipe` decides the same thing from a pan's translation with a threshold of this order. The owner's words were *like safari* — and his second frame (below) settled the other half of it: **the whole chrome goes, the strips under the header included**.

## What the structure had to change, and the measurement that said so

**On the old shape the list was laid out *below* the chrome**, so the band the header would vacate was not covered by the list at all. Measured, not assumed: the grid's frame was `top=219 height=621` with `contentInsets 0`. Off-setting the header alone under that structure would have slid it away to reveal `Palette.ink` — the defect the first attempt produced and the reason the change is a layout change and not one modifier.

The screen now composes as: the whole stack runs to the top of the screen; the chrome is drawn as an **overlay**; the header carries the status bar's band inside its own padding (so `headerHeight` *is* the band, `safeTop` included); and the list holds the chrome's **measured** height open as a `contentMargins(.top, …)` — a margin on the content rather than space the list is not given, so the list can still scroll up into it.

Measured after the change: `library list band=219 header=180 viewport=621 content=1279`, and the grid's frame `top=0 height=840`. **`621 + 219 = 840`** — the viewport plus the band is the whole screen, which is the arithmetic that says the list reaches the top edge and can draw in the band.

The **whole chrome** offsets by that same measured height, so at `progress == band` the last of it — the shelf's row, the lowest strip — is exactly off the screen and the list's content holds every point of the band. One number is both the floor and the distance: the band the list keeps clear is the band the chrome vacates.

The phases that do not scroll (the spinner, the error card, the three "nothing to show" cards) hold the same band open as a **real view** rather than as a `.safeAreaInset`: measured, an inset does not move a `.frame(maxHeight: .infinity)` child's centre on this OS — the empty card sat **110 pt high** in `frame-empty.png`'s first capture, which is a frame's catch and not a source read's.

## The frames

| Frame | The run | What it shows |
| ----- | ------- | ------------- |
| `frame-rest.png` | `TAG=rest` | The resting screen, **unchanged** from before the change: title · send · order, the search field, the `Downloaded 2 books ›` strip, and the grid starting immediately under it — no gap, no cover clipped by the band. |
| `frame-recede.png` | `TAG=recede SCROLL=14` | **The report, answered — including its second half.** The list sits at the 14th row: the title, the search field **and the `Downloaded` strip** are all gone, and the grid's own content (covers, labels) fills the band under the status bar with nothing left behind. |
| `frame-returned.png` | `TAG=returned SCROLL=14,4` | The other half of the gesture: pulled back to the 4th row with the list still **257 pt** in, and the whole chrome — shelf's row included — is back in its band, over a mid-list grid. Mid-list, not at the top. |
| `frame-empty.png` | `TAG=empty QUERY=zzzznotathing` | A phase that does not scroll: the header and the shelf's strip draw normally and the `Nothing matches` card is centred in the region below them. This frame is why the band is a real view in `placeholder` — see above. |
| `cold-launch.png` | `xcrun simctl launch …` immediately followed by `xcrun simctl io … screenshot`, no sleep | The first frame the app paints. The chrome is already correct, status-bar band included, so the measured band does not settle visibly and this change adds no launch flicker. (Slice 1's own lesson: **a probe that waits cannot see a launch defect.**) |

## The log lines

The runs' own words, from `Documents/probe.log` in the app's container — the two `chrome out`/`chrome in` lines are the verdict changing, and the `chrome scroll item=` lines say *where* it changed so a run states where the chrome left and returned rather than only that it did. (The profile holds 15 rows in these runs: the contract's own `api-smoke.sh` uploads one, which is why the 14th row is a different book here than in an earlier session's run.)

```
MUSAEUM_PROBE|library side inset=0.0 margin=16.0
MUSAEUM_PROBE|library safe top=62.0
MUSAEUM_PROBE|library page count=15 total=15 limit=100 offline=online sort=date_added:desc q=- filters=- first=Smoke Upload 20260925-235737 | Smoke Upload 20260924-203513 | Smoke Upload 20260924-164242
MUSAEUM_PROBE|library list band=219 header=180 viewport=621 content=1279
MUSAEUM_PROBE|chrome out progress=658 band=219
MUSAEUM_PROBE|chrome scroll item=14 title=In Defense of Selfishness progress=658 chrome=out
MUSAEUM_PROBE|chrome in progress=257 band=219
MUSAEUM_PROBE|chrome scroll item=4 title=Probe Upload 528 progress=257 chrome=in
```

## The second reading: the strips go too (2026-09-26)

The first landing had only the **header** give way, on the argument that the filter's cause and the shelf's door are sentences *about* the list rather than controls the reader has finished with. The owner's own frame of that build — his real library, 12 books on the shelf — showed the answer: **the `Downloaded` row sitting still under a departed header**, *"the 'downloaded' bar is static in both layouts."*

He is right, and the argument was the wrong way round: a strip left in a band that is otherwise content does not read as a deliberate surface, it reads as a bar that is stuck. So the **whole chrome leaves as one** — the header, the filter's cause, the upload's row, the shelf's door and the offline notice — offset by its own measured height, which is the same number the rule uses as the floor. Nothing was left behind to be static: at `progress == band` the last strip is off the screen exactly.

The frames and the log lines above are from the build after that change. **The rule and its 11 cases did not change** — what changed is which views carry the offset — so the campaign's six rows stand against this tree unchanged (`header-recede-campaign.log`).

## What decides the rule, and what only a frame can

`Tests/MusaeumTests/HeaderRevealTests.swift` (11 cases) decides the rule. `header-recede-campaign.json`, run into `header-recede-campaign.log`, is the proof that the cases can *fail*: six mutants, one line of the rule each, every row restored and sha256-verified, and every row killed with a blast radius that names it —

| Mutation | Cases reddened |
| -------- | -------------- |
| the floor is dropped: the header may leave before the band has gone by | 2 — `testTheHeaderCannotLeaveBeforeItsOwnBandHasGoneBy`, `testAPullAtTheTopNeverHidesTheHeader` |
| an unmeasured band acts: the floor's own guard on `band` is dropped | 1 — `testAnUnmeasuredBandHidesNothing` |
| the travel is not required: any movement moves the bar | 3 — `testAPushUnderTheTravelLeavesTheHeaderIn`, `testJitterNeverMovesTheHeader`, `testAChangeOfMindDiscardsTheRunItInterrupted` |
| the reveal half is dropped: a pull never brings the header back | 2 — `testAPullOfTheSameSizeBringsItBack`, `testTheBoxTakesItsDeltaFromTheLastReading` |
| a change of mind keeps the run it interrupted | 1 — `testAChangeOfMindDiscardsTheRunItInterrupted` |
| the box takes the position as the travel rather than the difference | 1 — `testTheBoxTakesItsDeltaFromTheLastReading` |

**The campaign caught a case that could not fail, and that is the reason it is committed.** The change-of-mind case was first written with *equal* alternating runs (+40, −40, +40, −40): those cancel, so the case stayed green with the reset deleted — a decider for nothing, while reading as coverage for exactly that line. It is now written with the unequal pair (+40, −10, +40, −10) that can only pass one way, and the row above is what says so.

**Not decided here.** The animation — `.snappy(duration: 0.26)` on the header's offset — reads as receding rather than as being yanked: that is a frame's judgement, and the owner's, not a case's. And **landscape is a claim for the owner's own device**: this machine has no Simulator UI (`simctl` has no rotate verb, and `Simulator.app` is absent from this Xcode installation), so no landscape frame could be taken here. What *is* measured is everything the landscape case turns on: `library safe top` is `62` in portrait and `0` in landscape, the header's own padding is the size class's, `band` and `headerHeight` come out of the same measured expression either way — and a smaller band means the header leaves correspondingly sooner in landscape than in portrait.

## Rejected

- **Collapsing the chrome's height** (the band shrinking until the header is 0 tall, or a `safeAreaInset` the header slides out of): the region the list is laid out in changes, so the list *lurches* by the band as the header leaves. UIKit's own bars do not move the content they uncover.
- **Off-setting the header alone, with the structure left as it was**: measured — `top=219 height=621`, `contentInsets 0`; the list was not there, so the band showed `Palette.ink`.
- **Putting the header inside the list**, so it scrolls away with the content: this is the reason the header was made *always shown* in the first place — *a search nobody can find is the same as no search*. The change keeps both halves: the list scrolls under the header, and 44 pt of pull brings it back wherever the reader is.

Reproduce any of it with the probe's own seam (`AGENTS.md`, "Gates"): `TAG=recede SCROLL=14 ./scripts/live-probe.sh` for the leave, `TAG=returned SCROLL=14,4 ./scripts/live-probe.sh` for the return, and `TAG=rest` for the resting frame the change had to leave alone.
