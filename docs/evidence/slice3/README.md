# Slice 3's evidence

Frames and log lines from the live probe of 2026-09-23 — the simulator against a real Musaeum on slice 1's isolated profile (8 EPUBs) at **`http://100.125.135.108:8789`**, iPhone 17 Pro / iOS 26.1. They are committed because the probe profile is throwaway and a measurement that lives only in a session is not a decider. The numbers beside each frame are in *Built — slice 3a* of `docs/specs/2026-09-22-client-v1-design.md`; the command that reproduces them is `scripts/live-probe.sh`, whose header carries the five-run recipe **in the order they must be run** and, below those, 3b's runs — see the second half of this README.

Two things about this profile the next session needs. The port is **8789, not slice 1's 8788**: the owner's own packaged Musaeum held 8788 while these runs were taken, so the probe profile was moved rather than colliding with it, and his instance was never touched or signalled — it answered `401` to this profile's token, which is how the two servers were told apart. And the sort is **remembered**, so the runs are ordered: the `SORT=` run leaves the phone on Author Z–A, which is what `TAG=kept` then reads back.

## The five runs

| Frame and its log lines | The run | What it decided |
| ----------------------- | ------- | --------------- |
| `library-title-az.png` / `.txt` | `TAG=library SORT=title:asc` | the control — 8 books, `first=Caliban's war \| Dragon Wing \| The Hidden Palace`, the Mac's own title order |
| `library-author-za.png` / `.txt` | `TAG=sort SORT=author:desc` | the order reverses and the label follows — `sort=author:desc first=The Self-Driven Child \| …`, **a different first title**, which is the only thing that makes a sort run decide anything |
| `sort-remembered-after-relaunch.png` / `.txt` | `TAG=kept`, **no `SORT` at all** | the persistence, and the only run that can decide it: a single line, `sort=author:desc`, on a launch that named nothing |
| `search-negotiation-one-match.png` / `.txt` | `TAG=search QUERY=negotiation` | a search's total is the **server's**: `total=1`, `first=Negotiation Genius`, below the library's own 8 — and the footer reads `1 match`, not `1 book` |
| `search-no-matches.png` / `.txt` | `TAG=nomatch QUERY=zzzz` | the two empty screens are different facts: `total=0`, then `library empty kind=noMatches("zzzz") macBooks=8`, and the card names the term and offers **Clear search** |

`first=` appears in every line because the *order* is what this slice is about, and a screenshot turned out to be the weaker instrument for it — see below. The frames are corroboration; the log lines are the deciders.

## What the frames decided that the log lines could not

The sort control's **label**, and it took two attempts. A `Label` in a toolbar renders icon-only, and so does the same `Label` carrying `.labelStyle(.titleAndIcon)`; each build shipped a bare ⇅ glyph, and each time it was a committed frame that caught it. That is a defect rather than a nitpick because the sort is **remembered**: a bare glyph means the app can open reordered with no visible cause on screen, which is the exact dissonance the remembered sort was chosen to avoid. The three frames above now read `Title A–Z`, `Author Z–A` and `Author Z–A`, on a control laid out as an explicit `HStack`.

**And one place a frame was wrong.** A run's frame caught the grid showing the *previous* order while its own log line already recorded the new one — a mid-flight read 25 s after launch, indistinguishable from a real defect by looking. It is recorded rather than tidied away, because it is why the order now travels in the log: the rendered array is what `first=` reports, so the order is decided by a line the app wrote about itself rather than by reading pixels.

## What none of these runs can decide

None of them taps anything. `simctl` can neither open the sort menu nor type in the search field, so **the menu opens** and **the field accepts typing** are claims for a human frame — the same honest limit slice 2 recorded for the background door. What is decided here is the app's own path from state to request to rendered order, through `MUSAEUM_PROBE_SORT` and `MUSAEUM_PROBE_QUERY`.

`slice3a-campaign.json` and `slice3a-campaign.log` sit beside the frames because the 14 new cases are a result only to the extent they can be made to fail: nine mutations, one per criterion that has a unit decider, **9/9 killed**, every file restored and sha256-verified.

## Slice 3b — the filters, and the icon

Five more runs on the same profile and the same server (see above for both), plus two that measured a single facet value. Filters are never stored, so the only state they leave behind is the sort run 1 names — which puts the phone back on `title:asc`. The command that reproduces each one is `scripts/live-probe.sh`'s header.

| Frame and its log lines | The run | What it decided |
| ----------------------- | ------- | --------------- |
| `filters-status-reading.png` / `.txt` | `TAG=filters SORT=title:asc FILTERS=status=reading` | two of the eight are being read, in the Mac's own title order — and `total=2` is the **server's** number for that parameter (measured directly before the runs), so the run is not the phone agreeing with itself |
| `filters-unread-and-epub.png` / `.txt` | `TAG=narrow FILTERS=status=unread;format=epub` | two axes are **ANDed**: 6, not the library's 8 and not the union |
| `filters-no-matches.png` / `.txt` | `TAG=filter-empty FILTERS=status=read` | `total=0`, then `kind=noFilterMatches(1) macBooks=8` — the card names the **filter**, and the Mac's own 8 is what makes it that rather than an empty library |
| `filter-sheet-with-counts.png` / `.txt` | `TAG=sheet SHEET=1` | the sheet's own frame: the contract's three statuses and four formats with the Mac's counts, the rating floor, and the three facet rows |
| `filters-unknown-token.png` / `.txt` | `TAG=unknown FILTERS=nonsense=1` | a token this build cannot read **says so** and applies nothing, rather than reading as a run that found nothing |
| `app-icon-before-after.png` / `.txt` | uninstall, then install — same page | the icon, in the slot that was empty, rounded by iOS's own mask |

### What the sheet's frame decided that no log line could

The sheet is the decider for 3.10 and half of 3.13, and it has to be a frame: the probe seam can *open* the sheet but `simctl` cannot tick a chip, so what the frame shows is that the rows are drawn — the contract's three read statuses and four formats, the rating floor, and the three facet rows with the Mac's counts — not that a tap on one of them does what it should (that is a human frame, in the spec's residuals). Two things it settles by looking: **a zero count stays put** (`MOBI 0`, `AZW3 0`, `PDF 0`, `Read 0` are all on screen, so the rows show the contract's vocabulary and not the profile's contents), and **3.13's warning was honoured** — the toolbar indicator is an explicit `HStack` and reads gold **with its `1`**, where a `Label` would have shipped as a bare glyph and left an active filter with nothing on screen to explain it. That is the defect 3a's sort control shipped through two builds.

### What none of these runs can decide

Nothing here taps. `simctl` can neither tick a chip nor press *Clear all*, so *a tick applies immediately*, *every tick re-fetches*, *Clear all empties every row* and *a facet value narrows the list* are claims for a human frame. What is decided is the app's own path — state → request → rendered results — through `MUSAEUM_PROBE_FILTERS` and `MUSAEUM_PROBE_SHEET`.

### The campaign

`slice3b-campaign.json` / `.log` sit beside the frames: **14 mutations, 14/14 killed**, every file restored. All 15 of `LibraryFilterTests`' cases are reddened by at least one row — the four rows at the end of the log exist because the first ten left four cases (the vocabulary, the facet axis lists, the facet-fetch trigger, and the encoder half of the probe round trip) with no mutation aimed at their own subject.