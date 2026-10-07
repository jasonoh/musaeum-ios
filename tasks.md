# Musaeum iOS — roadmap

The client's roadmap: what is open, and what is still owed by hand rather than by code. The per-slice build record — every landed slice, its gates, its probe readings and its mutation campaign — moved verbatim to **`docs/roadmap-history.md`** on 2026-10-06, so this file reads as a backlog rather than a changelog. For what changed in a user's terms read `CHANGELOG.md`; for the decisions (CD1–CD8) and each slice's own *Built* section read `docs/specs/2026-09-22-client-v1-design.md`; `docs/what-works-today.md` is frozen at slice 6b.

## Where it stands (2026-10-06 — tree `632b422`, clean and pushed)

Everything v1 was drawn to do is built, gated, probed and committed: **slices 1–7**, 2026-09-22 → 2026-09-28 — the downward path, the upward path, sorting/search/filters, uploading to the Mac, sharing a download out, the reader's immersive chrome and its typography, and shelves — plus the work that followed each of them and was never numbered: the library header that recedes by its own measured height (invariant 12), the Mac's wordmark, the icon set, and the shelf's own fixes. The archive's opening entry names each unnumbered change with its commits and its figures.

Gates on the committed tree (run 2026-10-06 on `632b422`): `xcodegen generate`, then `xcodebuild build` **exit 0** (the log's one warning is Apple's `appintentsmetadataprocessor`, not a file of ours); `xcodebuild test` **exit 0 — 218 cases, 0 failures, 26 suites**; `../musaeum/scripts/api-smoke.sh --profile <the probe profile>` **70 passed, 0 failed**.

**Nothing on the wire moved for any of it.** No route added, no field changed, no design decision (CD1–CD8) re-opened — the contract is still the Mac's `docs/rest-api.md` at `apiVersion` 1. A client slice that needs a route the document does not carry **cannot start**: the fixtures are extracted from the document itself, so the contract slice lands in the Mac repo first.

## Deferred, with the condition that would revive it

- **Resumable downloads.** The wire supports a single `Range` today (the smoke run re-confirms `206` and `416`); this is client-only work. Revived by one transfer large enough that restarting it hurts — 80 books in this library hold an EPUB over 100 MB, the largest 528 MB, so the tailnet is what decides how often it bites.
- **Search and filters in the client.** The contract serves both (`q`, `sort`, `dir`, facets, `minRating`). Revived the first time search is wanted on the phone and it is not there. **Revived 2026-09-23 — it landed as *Slice 3*, and its record is in `docs/roadmap-history.md`; its fork was already marked fired in the design's own deferred list.**
- **PDF in the reader.** The library holds 1,798 books with a PDF and the wire serves them (`format=pdf`); Readium renders PDF through a separate navigator and a PDF document factory, which is not wired here. Revived by a book wanted on the phone that is PDF-only.
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

## Slice 7's own open items

- **Shelf edits with the Mac asleep** (F4's reversal condition) — a queue with a row-state question attached, not a debt.

- **Creating, renaming and deleting shelves** remain the Mac's: the document's *Not in this version*.

## What is still owed by hand — the frames and gestures no test can drive

Collected from the slices' own records, each of which says the same thing in its own words: `simctl` presents no sheet and taps nothing, so every line below is a claim for the owner's own hands. Each names the slice that owes it.

- **Slice 2** — a progress report taken while the app is being backgrounded: it usually reaches the Mac on the phone's *next* foreground. The queue is what makes that safe rather than lossy, and the reading is a claim for a human frame.
- **Slice 3a** — that the sort menu *opens*, that the search field *accepts typing*, and that a tap from a sorted library opens the right cover.
- **Slice 4** — that the picker *opens*, and that a book *can be chosen from it*.
- **Slice 5** — that the share sheet offers AirDrop, Mail and Messages for a staged EPUB, and what the receiving app shows it as (AC9); and what a *tap* does on a downloads row.
- **Slice 7** — the shelf picker menu open, the checklist sheet, and a check moving under a finger.

Nothing else here waits on a person: the icon and the wordmark have their frames under `docs/evidence/`, and every other reading is the app's own path — state → request → rendered outcome — plus the Mac's own record of what arrived.
