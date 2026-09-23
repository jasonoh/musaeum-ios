# Musaeum iOS — roadmap

## Slice 1 — the downward path (**landed, committed** `ed7abf6` 2026-09-22)

Config → connect → the library grid → a book's detail → download → read at the fraction the Mac holds. Design: `docs/specs/2026-09-22-client-v1-design.md` (CD1–CD8, criteria 1–14); the readings and the frames are in that document's *Built — slice 1* section.

Landed as 16 app files + 7 test files, 43 unit cases, against a live Musaeum on an isolated profile:

| Instrument          | Result                                                                                     |
| ------------------- | ------------------------------------------------------------------------------------------ |
| `xcodebuild build`  | exit 0, no warnings in this repo's own files (Readium's packages excluded)                  |
| `xcodebuild test`   | exit 0 — 43 cases, 0 failures, across 6 suites (7 files, one of them the stub)              |
| live probe, library | `library page count=8 total=8 limit=100 offline=online`, 7 of 8 covers painted              |
| live probe, reader  | asked for `0.42` → landed **`0.4198265179677819`**, in `OEBPS/…c06_r1.htm`                  |
| live probe, Mac off | server stopped, no listener: read from the phone's own copy at **`0.4198265179677819`** — its own position, which was further along than the Mac's stale `0.1` |

The probe is re-runnable: `scripts/live-probe.sh` (its header carries the whole server recipe).

## Slice 2 — the upward path (**built, gated, probed** 2026-09-23 — not yet committed)

The progress report: the fraction written back when the reader closes or the app leaves the foreground, queued while the Mac is unreachable, flushed oldest first and ordered by the report's own clock (the Mac spec's D6, applied by the client).

Landed as 3 new app files + 5 edited, 3 test files, plus the probe script and the docs. **61 unit cases across 9 suites, 0 failures** (slice 1's 43 unchanged and included); `../musaeum/scripts/api-smoke.sh` against the same server: **56 passed, 0 failed**.

| Instrument                       | Result                                                                                                  |
| -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| live probe, write (Mac further)  | the Mac's `0.42` → **`0.4198265179677819`** — the phone's engine's number, not the one the Mac sent      |
| live probe, write (phone further)| the Mac's stale `0.05` + a stale CFI → **`0.419826517967782`**, the CFI **blanked** (D5, through the report) |
| live probe, Mac asleep           | no listener on 8788: `report queued`, `pending=1`, the Mac's row untouched                              |
| live probe, after it woke        | `report queue drained`; `reports.json` `[…] → []`; the row's `updated_at` is **the queued report's own `readAt`**, not the flush's clock; `metadata.json` agrees |

Frames: `docs/evidence/slice2/` (its README carries the log lines and the two traps the runs paid for).

**Not done, deliberately:** a UI surface for the queue, a background `URLSession` (so a report taken on *background* usually lands on the phone's next foreground — safe because it is queued first, and a claim for a human frame), resumable downloads, the **filter** half of slice 3 (sort and search landed 2026-09-23 — see *Slice 3* below), PDF in the reader.

**That closes the design's own scope.** CD8 drew v1 as two slices and there was no slice 3: what followed was the deferred list below, each item revived only by its own stated condition. **One of them has now fired** — see *Slice 3* — which is that list working as written rather than a change of plan.

## Slice 3 — the phone's library: sorting, search and filters (**3a landed**, 3b scheduled — 2026-09-23)

The deferred item *Search and filters in the client*, revived by its own written condition: the owner reached for search on the phone on 2026-09-23 and it was not there. Annex: `docs/plans/2026-09-23-slice3-search-sort-and-filters.md`. **Two stages, because the honest count runs past the house's ~10-file bound** — **3a: sort and search** (11 files: 4 code, 2 test, 4 documents, the probe script) and **3b: filters** (~6 files). The three forks were settled in one form the same day: all three features now, built in two stages; the sort is remembered like the desktop's and the query never is; and the active sort stays live while searching, so the same query returns the same order on both devices. **Deliberately not needed:** no contract change (the wire already carries `sort`, `dir`, `q`, the filter parameters and `minRating`), no Mac-repo slice, no new dependency, and no change to CD3's local-state inventory beyond one `UserDefaults` key.

**Stage 3a — sort and search — landed 2026-09-23.** Gates: `xcodebuild build` exit 0 (the one warning in the log is Apple's `appintentsmetadataprocessor`, not a file of ours), `xcodebuild test` **exit 0 — 75 cases, 0 failures, 11 suites** (61 across 9 before it; the 14 new are `LibrarySortTests` 8 and `LibraryQueryTests` 6), `../musaeum/scripts/api-smoke.sh` **56 passed, 0 failed**, AC13's source walk clean, and a **9-mutation campaign, 9/9 killed** with every file restored (`docs/evidence/slice3/slice3a-campaign.log`).

| What a probe run decided | The reading |
| ------------------------ | ----------- |
| `TAG=library SORT=title:asc` | `sort=title:asc first=Caliban's war \| Dragon Wing \| The Hidden Palace` — the Mac's own title order |
| `TAG=sort SORT=author:desc` | `sort=author:desc first=The Self-Driven Child \| …` — **a different first title**, which is what makes a sort run decide anything |
| `TAG=kept`, no `SORT` at all | one line, `sort=author:desc` — the sort survived a relaunch; the only run that can decide it |
| `TAG=search QUERY=negotiation` | `count=1 total=1 q=negotiation first=Negotiation Genius` — the total is the **server's**, not the page's |
| `TAG=nomatch QUERY=zzzz` | `total=0`, then `kind=noMatches("zzzz") macBooks=8` — *no matches* and *empty library* are different screens |

Frames and log lines: `docs/evidence/slice3/`. The probe profile moved to **8789** for these runs, because the owner's own packaged app held 8788 while they were taken — his instance was never touched or signalled. **Nobody has tapped anything yet:** that the sort *menu opens*, that the field *accepts typing* and that a tap from a sorted library opens the right cover are claims for a human frame, and `simctl` can drive none of them.

**Stage 3b — the filter chips — is not built.** Its files and criteria are in the annex.

## Deferred, with the condition that would revive it

- **Resumable downloads.** The wire supports a single `Range` today (the smoke run re-confirms `206` and `416`); this is client-only work. Revived by one transfer large enough that restarting it hurts — 80 books in this library hold an EPUB over 100 MB, the largest 528 MB, so the tailnet is what decides how often it bites.
- **Search and filters in the client.** The contract serves both (`q`, `sort`, `dir`, facets, `minRating`). Revived the first time search is wanted on the phone and it is not there. **Revived 2026-09-23 — it is now *Slice 3* above; its fork was already marked fired in the design's own deferred list.**
- **PDF in the reader.** The library holds 1,798 books with a PDF and the wire serves them (`format=pdf`); Readium renders PDF through a separate navigator and a PDF document factory, which is not wired here. Revived by a book wanted on the phone that is PDF-only.
- **A local library cache.** Revived when the library is slow enough to page through on every launch, or when browsing with the Mac asleep is wanted for its own sake (CD3's own reversal).
- **Reading-position precision beyond the fraction, travelling.** The Mac's CFI is a coordinate no other engine can use and the parent spec's D5 settled this; a per-device position map is `../musaeum/docs/superpowers/specs/2026-09-20-portable-decisions-design.md`'s ground and must not be pre-empted here.
- **A QR hand-off for the URL and token** — a phone keyboard typo currently surfaces as a 401 from the connect screen, which is acceptable and honest.
- **A surface for the report queue** ("N reports waiting"), and a **background `URLSession`** so a report taken on background reaches the Mac at that instant rather than on the next foreground. Both are new decisions rather than debts: see *Built — slice 2*.
