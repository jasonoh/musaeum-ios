# Musaeum iOS — roadmap

## Slice 1 — the downward path (**landed** 2026-09-22)

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

**Not done, deliberately:** the progress *write* (slice 2), resumable downloads, search/filter UI, PDF in the reader.

## Slice 2 — the upward path (next)

The progress report: the fraction written back on stop, queued while the server is unreachable, ordered by the report's own clock (the Mac spec's D6, applied by the client). Also here if its condition has fired: resumable downloads by `Range`.

Nothing of slice 2 exists yet — the app reads the Mac's fraction but never writes one.

## Deferred, with the condition that would revive it

- **Resumable downloads.** The wire supports a single `Range` today; this is client-only work. Revived by one transfer large enough that restarting it hurts — 80 books in this library hold an EPUB over 100 MB, the largest 528 MB, so the tailnet is what decides how often it bites.
- **Search and filters in the client.** The contract serves both (`q`, `sort`, `dir`, facets, `minRating`). Revived the first time search is wanted on the phone and it is not there.
- **PDF in the reader.** The library holds 1,798 books with a PDF and the wire serves them (`format=pdf`); Readium renders PDF through a separate navigator and a PDF document factory, which is not wired here. Revived by a book wanted on the phone that is PDF-only.
- **A local library cache.** Revived when the library is slow enough to page through on every launch, or when browsing with the Mac asleep is wanted for its own sake (CD3's own reversal).
- **Reading-position precision beyond the fraction, travelling.** The Mac's CFI is a coordinate no other engine can use and the parent spec's D5 settled this; a per-device position map is `../musaeum/docs/superpowers/specs/2026-09-20-portable-decisions-design.md`'s ground and must not be pre-empted here.
- **A QR hand-off for the URL and token** — a phone keyboard typo currently surfaces as a 401 from the connect screen, which is acceptable and honest.
