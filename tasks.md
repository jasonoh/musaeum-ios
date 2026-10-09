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

## Slice 3 — the phone's library: sorting, search and filters (**3a and 3b landed** 2026-09-23 — not yet committed)

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

**Stage 3b — the filter chips — landed 2026-09-23.** Read status, format, a rating floor, and the library's own authors, series and tags, in a sheet that draws the contract's own vocabulary and the Mac's own counts; every tick applies at once, the toolbar says how many are on, one control clears them, and a set that matches nothing says *that* rather than claiming an empty library. Gates: `xcodegen generate` then `xcodebuild build` exit 0 with no warning in our own files, `xcodebuild test` **exit 0 — 90 cases, 0 failures, 12 suites** (75 across 11 before it; the 15 new are `LibraryFilterTests`), `../musaeum/scripts/api-smoke.sh` **56 passed, 0 failed**, AC13's source walk clean, and a **14-mutation campaign, 14/14 killed**, every file restored (`docs/evidence/slice3/slice3b-campaign.log`). All 15 of the suite's cases are reddened by at least one row — four had to be written at their own subjects after the first ten rows left them untouched.

| What a probe run decided | The reading |
| ------------------------ | ----------- |
| `TAG=filters FILTERS=status=reading` | `count=2 total=2 filters=status=reading first=Caliban's war \| Negotiation Genius` — and 2 is the **server's** own answer for that parameter, measured directly |
| `TAG=narrow FILTERS=status=unread;format=epub` | `count=6 total=6` — two axes **ANDed**, not 8 and not the union |
| `TAG=filter-empty FILTERS=status=read` | `total=0`, then `kind=noFilterMatches(1) macBooks=8` — the card names the *filter*, and the Mac's own 8 is what makes it that rather than an empty library |
| `TAG=sheet SHEET=1` | `facets authors=8 series=2 tags=27 formats=epub:8 statuses=unread:6,reading:2` — the sheet's rows and the Mac's counts |
| `TAG=unknown FILTERS=nonsense=1` | `probe: filters 'nonsense=1' carried nonsense=1, which this build does not know` — an unreadable token says so instead of looking like a run that found nothing |

Frames and log lines: `docs/evidence/slice3/`. Three findings this slice paid for, all in the spec's own section: an empty selection is the **client's** rule rather than the server's (measured — `formats=` returns the whole library, and the annex said otherwise); a parameter *name* the server does not know is **ignored** rather than refused, so a typo has to be caught by a case that reads the composed request; and one facet value the sheet offers, **`William Stixrud, PhD`**, is a filter that finds nothing because the wire's multi-value parameter is comma-separated — left standing, since the fix is an encoding the contract does not have.

**The app icon landed with it** (the desktop's own artwork, `musaeum`'s `build/icon.png`, cropped to its own bounds and filled to 1024² so iOS's mask rounds it exactly once): `CFBundleIconName = AppIcon` in the built bundle, and `docs/evidence/slice3/app-icon-before-after.png` for the home screen.

**Slice 3 is complete.** Nothing in 3a or 3b changed a design decision, the contract, or the Mac repo — the wire already carried every parameter both stages needed.

## Slice 4 — sending a book to the Mac (**4a and 4b landed** 2026-09-24 — not yet committed)

A book picked on the phone — or shared to Musaeum from Files, Safari or Mail — goes to the Mac's own importer, so what lands is what the Mac would have imported itself: the same metadata pass, the same covers, the same rule for a book it already has. Annex: `docs/plans/2026-09-23-slice4-upload.md`. The wire is `../musaeum/docs/rest-api.md` § `## POST /api/books`, whose Mac-side slice landed 2026-09-23 — **no contract change, no Mac-repo slice, and no design decision (CD1–CD8) re-opened.** Landed as `7d0fc65` (15 files, 1,707 insertions) with the annex itself in `cd613ed`.

**Two stages, and the second landed as a different shape than the annex drew.** 4a is the client, the picker and the outcome row: `MusaeumClient.uploadBook` — the bytes as the body, the bearer header, and the **`413` the client had no case for**, which is the gap this slice opened on (`mapStatus`'s `default` reported a deliberate refusal as *the Mac is not answering*, and `isRetryable` then said *send it again* about a book that can never fit) — `UploadModel` (the state machine, and the refusal vocabulary in four classes), `UploadSheet` (the only `fileImporter` in the app), `UploadInbox` (what a share leaves behind, and what may be deleted), `LibraryScreen` (the toolbar's one control, the outcome row, the sweep) and `Probe` (`MUSAEUM_PROBE_UPLOAD`). **4b was planned as a share extension and is not one.** An extension is a second target, and getting the file across needs either an app-group container or a keychain access group; both are Apple Developer Program capabilities, this app is signed with a **free personal team**, and adding either stops the profile being issued — so the extension would have taken *the app's own installability* with it while the simulator, which ignores provisioning, kept every gate green. What landed instead is the system's own **Copy to Musaeum**: the four document types declared with `LSSupportsOpeningDocumentsInPlace` false, so Files, Safari and Mail copy the file into this app's own `Documents/Inbox` and open the app, which sends it through exactly the door the picker uses. No entitlement, no second binary, one file at a time, and the token stays in one process (invariant 10).

Gates: `xcodegen generate` then `xcodebuild build` **exit 0** (the project regenerated from `project.yml` byte for byte); `xcodebuild test` **exit 0 — 117 cases, 0 failures, 15 suites**; `../musaeum/scripts/api-smoke.sh` against the probe profile **70 passed, 0 failed** (the annex's own expected number, measured again on 2026-09-24 against the current Mac HEAD); a **15-mutation campaign, 13/15 killed**, every file restored, with two rows reported as a finding rather than a kill — both survivors are **the same mutation**, and it is the one that says AC1's *shape* half is asserted rather than decided (the spec's correction 4); nine live-probe frames and the library the runs wrote to in `docs/evidence/slice4/`.

**The suite's own count moves twice here, and only one move is this slice's.** Slice 4 adds **22 cases**: `UploadTests` 13, `UploadInboxTests` 7, and two in `ClientTests` (14 → 16 — the composed upload request, and the `413`'s outcome with its non-retryability). The other five are `CoverBoxTests`, which came in with `d98f3a9` (*fixed cover sizing*, the change the changelog's 2026-09-23 *Fixed* entry covers) — so 12 suites became 15, and 90 cases became 117, for two reasons rather than one.

| What a probe run decided | The reading |
| ------------------------ | ----------- |
| `TAG=upload-a` | *Sent to the library* — the `201`'s row, and the book is named by the name the **wire** carried; the library holds that row, 1,404 bytes |
| `TAG=upload-b`, the same file again | *Sent — and you already had it*, the match named as `title_author` — and the Mac's answer is a **second book**, which is `add-new` working rather than a refusal |
| `TAG=upload-528` (553,649,623 bytes) | *Sent to the library* — the Mac's own census's worst case, sent from the phone and landed as a row with the file on the share |
| `TAG=upload-over-cap` | *The Mac refused it* / *content too large for it to take* / *Sending it again would be refused the same way*, **no retry offered** — so `URLSession` **does** read a `413` answered while it is still writing the body, which the Mac's socket-level proof had left open for a real client |
| `TAG=upload-offline` | *The Mac is not answering* with **Try again** — the class worth waiting out (this is `unreachable`; the 503's own arm is the unit case's) |
| `TAG=swept` | the row and the copy both gone: the screen is the plain library, so a refused send leaves nothing behind |
| `TAG=control` / `TAG=sortctl` / `TAG=restored` | the toolbar one control heavier: the upload's renders as a glyph **with `Send`**, and the sort control keeps its words (`Title A–Z`, `Author Z–A`) — 3a's icon-only trap, one item later |

**The owner's own upload has since crossed a real wire**, which no probe on this profile can decide: *The Art of Spending Money*, 1,081,907 bytes, uploaded from his iPhone, on the share at `books/540bd9a6-…/` with both covers and its own `metadata.json`, the share's `catalog.json` rewritten at 13:28:49Z and the row dated `2026-09-24T13:28:46.611Z`.

**Nobody has tapped anything yet, and that is where the limit is honest:** that the picker *opens*, that a book *can be chosen from it*, and that the share sheet *offers Musaeum* are claims for a human frame — `simctl` can drive none of them. Everything above is the app's own path (state → request → rendered outcome) plus the Mac's own record of what arrived. The `docs/evidence/slice4/` README also records a gap rather than hiding it: **the runs' log lines were not captured to files**, so the frames and the library the runs wrote to are what decide these readings.

## Slice 5 — sharing a downloaded book out (**landed** 2026-09-24 — not yet committed)

A book the phone already holds goes out to somebody else through the system's own share sheet — AirDrop, Mail, Messages, *Save to Files* and whatever else the phone offers for an EPUB. Annex: `docs/plans/2026-09-24-slice5-share-out.md`. **Nothing on the wire moves, no route is added, no design decision (CD1–CD8) is re-opened, and — unlike slice 4b — no capability is needed at all:** the bytes are already at `<appSupport>/Musaeum/Books/<id>.<format>`, and what the sheet hands out is a file in the app's own container. The tree still holds no `.entitlements` file, which is the whole difference between this arrow and 4b's inbound one.

**One stage, three new files and six edited.** `ShareStaging` is the pure rule (the name the recipient sees, and the staging itself — a hard link where the volume allows, a copy where it does not, swept on dismissal, before the next stage, and at launch); `ShareSheet` is the sheet's presentation (`ShareRequest` + `UIActivityViewController`, since this is one of the few places SwiftUI's `ShareLink` cannot reach when the item must be staged first); `ShareStagingTests` is the 19 cases. `DownloadStore` grows `stagedForSharing`/`sweepStaging` and the launch sweep; `BookDetailScreen` gets the door beside *Read*; `DownloadsScreen` gets one on each shelf row; `Probe`, `MusaeumApp` and `LibraryScreen` carry the seam the frame needs; `scripts/live-probe.sh` learns the action. **The ninth file is the one addition the annex did not draw** (`LibraryScreen`), and it is named rather than folded in.

**Two doors, and the name is the work.** A share called `<id>.epub` is a share the recipient cannot do anything with, so the staged copy is named from the contract's own fields — `Title - Author.ext` — with the format taken from the **stored file's** extension rather than from what the wire preferred (`formats.first` is the contract's order, not necessarily what this phone downloaded), the id as the fallback for a title with nothing in it, and the whole stem clipped to 180 **bytes** so a Cyrillic or CJK title cannot overrun the filesystem's own limit. The copy is a **hard link** — one file with two names, so a 528 MiB book is not duplicated on the phone to send it — falling back to a copy where linking is refused, and the sheet is handed the file, never a boxed type.

Gates: `xcodegen generate` then `xcodebuild build` **exit 0**; `xcodebuild test` **exit 0 — 136 cases, 0 failures, 16 suites**, moved from the **117 across 15** this slice started on, and the whole move is this slice's own **19 cases in `ShareStagingTests`**; `../musaeum/scripts/api-smoke.sh --profile <the probe profile>` **70 passed, 0 failed** — unchanged, which is what a slice that moves no route should read; a **21-mutation campaign, 21/21 killed**, every file sha256-verified restored, with **all 19 of the suite's cases reddened by at least one row**.

| What a probe run decided | The reading |
| ------------------------ | ----------- |
| `ACTION=share TAG=share BOOK=ef91875e-…`, the Mac up | `share staged … name=Negotiation Genius - Deepak Malhotra.epub linked=1 bytes=660053`, then `share reading … bytes=660053 source=660053 same=1` — the **title and the byline** rather than the stored id, the **link** rather than a second copy, and the staged bytes *are* the download's |
| the same run with **the Mac stopped** | `library failed … falling back to the phone's own copy` → **the same name, the same link, the same bytes** — the file a share hands out comes off the phone's disk, and no client is in that path |
| `TAG=detail DETAIL=ef91875e-…` | the frame: gold **Read**, raised **Share** with its words, *Remove the download* beneath — and the staged listing **empty** where the previous run's copy had been, which is the launch sweep decided on real data |
| the container listing | `…/Musaeum/Share/Negotiation Genius - Deepak Malhotra.epub` — one file, beside `Books/`, and nothing at all before a share asks for it |

**The sheet itself is the owner's frame (AC9):** whether AirDrop, Mail and Messages appear for a staged EPUB, and what the receiving app shows it as — `simctl` presents no sheet and taps nothing. **And the shelf's own rows were not captured by this slice**, because reaching that screen needs a navigation the build had no seam for; the seam arrived the next day, with the row it was needed for — `DOWNLOADS=1` pushes the same destination the door does, and the row's geometry is a reading in `docs/evidence/downloads-row-alignment/` (the two glyphs were drawing 56 px and 46 px of ink at one font size; they draw 46 and 46 now).

## Deferred, with the condition that would revive it

- **Resumable downloads.** The wire supports a single `Range` today (the smoke run re-confirms `206` and `416`); this is client-only work. Revived by one transfer large enough that restarting it hurts — 80 books in this library hold an EPUB over 100 MB, the largest 528 MB, so the tailnet is what decides how often it bites.
- **Search and filters in the client.** The contract serves both (`q`, `sort`, `dir`, facets, `minRating`). Revived the first time search is wanted on the phone and it is not there. **Revived 2026-09-23 — it is now *Slice 3* above; its fork was already marked fired in the design's own deferred list.**
- **PDF in the reader.** The library holds 1,798 books with a PDF and the wire serves them (`format=pdf`); Readium renders PDF through a separate navigator and a PDF document factory, which is not wired here. Revived by a book wanted on the phone that is PDF-only. **Partly answered 2026-10-09 (slice 8):** a PDF with a text layer is laid out by the Mac as an EPUB and read through the existing EPUB reader (`docs/evidence/slice8/`; the owner's tap, open and page-turn are still to confirm). **Still open:** the image-only PDFs (about 10 %, the Mac answers 422 for them) and the original PDF's own view, which is the Readium PDF navigator this entry describes.
- **A local library cache.** Revived when the library is slow enough to page through on every launch, or when browsing with the Mac asleep is wanted for its own sake (CD3's own reversal).
- **Reading-position precision beyond the fraction, travelling.** The Mac's CFI is a coordinate no other engine can use and the parent spec's D5 settled this; a per-device position map is `../musaeum/docs/superpowers/specs/2026-09-20-portable-decisions-design.md`'s ground and must not be pre-empted here.
- **A QR hand-off for the URL and token** — a phone keyboard typo currently surfaces as a 401 from the connect screen, which is acceptable and honest.
- **A surface for the report queue** ("N reports waiting"), and a **background `URLSession`** so a report taken on background reaches the Mac at that instant rather than on the next foreground. Both are new decisions rather than debts: see *Built — slice 2*.
- **Resuming an upload.** The wire has no `Range` on `POST /api/books` and no idempotency key, so a failed send is a *new* send — safe, because a book the Mac already has is added rather than refused (measured: the same file sent twice is two rows), at the cost of the transfer. Revived by a book large enough that sending it twice hurts, which slice 4 has already made realistic: it sent **553,649,623 bytes** as one body.
- **A batch — a run of books in one gesture.** One body per request and one book per answer, so a batch is a queue the phone would own, and there is none. Revived by wanting to send several books at once rather than one at a time.
- **A background `URLSession` for the upload** (the annex's F1(b), deliberately not taken). `URLSession`'s default was chosen because the *outcome* survives the app being backgrounded — a failed send settles with a message — not because the transfer does. Revived by a measurement showing the foreground window ends before a normal book finishes: that is reading R2, and slice 4 did not take it.
- **Sharing a book the phone holds no copy of** (slice 5's F1(a), deliberately not taken). The door exists only where the bytes do, so it is instant and works with the Mac asleep; the other shape would fetch the file from `GET /api/books/{id}/file` and put the Mac back in the path of a gesture that is usually about the person you are sending to rather than the file. Revived by wanting to send a book without first downloading it — and its reversal would want a progress surface, which is the deferred item below.
- **Choosing the format a share carries.** What goes out is `formats.first` as the phone stored it — an EPUB for this library, which Apple Books opens anywhere; a Kindle-format-only book goes as that file and a DRM-locked one is no more useful to a recipient than it was to the owner. Revived by a share refused because of the format, which is also when `ebook-convert` on the Mac becomes relevant to the client at all.
- **A seam onto the downloads shelf.** Slice 5's second door is real but has no frame, because `downloadsRow` is a `NavigationLink` and the run cannot reach the shelf — so whether the row's two glyphs read as *open* and *share* at a glance is the owner's judgement on the device rather than a reading. Revived the next time a slice wants a frame of that screen, which is also when the seam should be added (`Probe` carries the pattern). **Revived 2026-09-24 — the shelf's rows were reported misaligned, `DOWNLOADS=1` pushes the same destination, and the row's geometry is now a reading (`docs/evidence/downloads-row-alignment/`); the two glyphs' frames are unchanged in kind, so what remains the owner's is only what a *tap* does, not what the row looks like.**
- **A staged share left by an app the OS killed, on a device that is never relaunched.** The launch sweep covers every launch, and the sweep before a stage covers every share; the gap is a device whose app is killed mid-sheet and then uninstalled or never opened again, where one file sits in the container until it is. Accepted rather than deferred, and named here because it is the only residue this slice can leave.

## Slice 7 — shelves on the phone (2026-09-28)

**The scope, and the checklist.** `../musaeum`'s slice 5 put shelves on the wire; this slice reads it — `GET /api/shelves` as the capability probe, `?shelf=` on both library reads, `shelves` on every book payload, and the membership `PUT`/`DELETE` behind a book's own page. Annex: `docs/plans/2026-09-28-slice7-shelves.md` (its F5 amended during the build); readings: `docs/evidence/slice7/`; record: the design doc's *Built — slice 7*. Gates: **209 cases across 25 suites, 0 failures** (from 191/24), build exit 0. **No contract change, no Mac-repo slice.**

The one thing it settled for itself that the annex left open: **toggles are refused with a sentence, never queued** (F4), because the writes are idempotent and a queued toggle would need an answer for what the row shows until it lands. Its reversal condition is the third item below.

Deferred and named:

- **Frames that need a tap:** the picker menu open, the checklist sheet, a check moving under a finger — the owner's, as everywhere.
- **A shorter in-shelf sort label** — *"if the Mac's own *Date Added to Shelf, Newest First* reads badly in the phone's bar"*. **Revived 2026-09-29 and landed.** The owner's device showed what the frame had only hinted at: the label is 255.5 pt at the bar's 17 pt, the title row came to **532 pt on a 402 pt screen**, and the page itself was laid out to that width — every shelf, portrait only, until the phone was turned. The bar draws `Shelf: Newest` / `Shelf: Oldest` (the menu keeps the Mac's sentence), the title row gives way by construction, and the bar's own width is a probe line now (`docs/evidence/shelf-bar/`).
- **Shelf edits with the Mac asleep** (F4's reversal condition) — a queue with a row-state question attached, not a debt.
- **Creating, renaming and deleting shelves** remain the Mac's: the document's *Not in this version*.
