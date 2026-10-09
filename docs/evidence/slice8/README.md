# Slice 8 — reflow client: what was measured

A PDF-only book on the phone is downloaded as the Mac's reflowed EPUB (`format=reflow`, polled through `202` to `200`, saved as `{id}.epub`). This directory is the live reading of the Mac half and of the phone's detail screen. **The phone's download itself was not observed** — see *(c) and (d)*.

## Setup

- Mac: `pdf-reflow-slice-4` worktree (the one with a working `sidecar/.venv` and `helpers/bin/musaeum-layout`), `env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<scratch>/profile npm run dev`, isolated scratch profile and library, REST on the tailnet address port **8790**. The pid listening was the run's own (started 17:46:00); the real profile's `musaeum.db` was not touched (last modified 6 Oct). Never `/Volumes/books`.
- Fixture: a 4-page, 12,180-byte text PDF ("The Reading Room", Times-Roman, built by hand; pypdf extracts 1,780 characters from page 1), no EPUB beside it. Imported by the watcher into one book, formats `["pdf"]`.
- Phone: iPhone 18 Pro, iOS 27.0 simulator `39D29C73-B2DD-4041-8ECD-46923376D0F9` (it exists again on this machine; the 26.1 id in `AGENTS.md` was stale), app built from `feat/reflow-client` at `deaca97`.

## Gates (re-run for this task)

- `xcodegen generate`, build **exit 0** (no `warning:` lines in the build log), test **exit 0, 243 cases, 0 failures, 29 suites**.
- Arithmetic: baseline 218 cases / 26 suites before the slice, Task 1 +8, Task 2 +9, Task 3 +8 = 243; the three new suites are `ReflowDownloadTests`, `ReflowDetailModelTests` and `DownloadPlanTests`.
- Mac smoke (`scripts/api-smoke.sh` on this profile): **82 passed, 1 failed** (`api-smoke.log`). The one failure is the pre-existing `the page carries exactly limit rows — expected 2, got 1`: it needs at least two books, and the smoke's own upload, which makes the second, runs later in the script. Every check in the reflow section passed: `reflow.available` is a boolean, an EPUB-holding book answers `format=reflow` with 404, the PDF-only book answers 200 after a 1 s poll with an EPUB type, an `ETag` and a zip magic.

## (a) The detail frame

`detail-reflow.png`: the live app (`MUSAEUM_PROBE_DETAIL=<id>`) showing the PDF-only book — its cover, "PDF", "12 KB" and the **Download to this phone** button. This is the idle state before any tap. (The "42% read on the Mac" line is the smoke script's own reading write.)

## (b) The Mac's side of the sequence (`reflow-curl.txt`)

From a cold cache (the book's `derived/` moved away first), the payload and then the route:

```
{"id":"c318fc75-…","title":"The Reading Room","formats":["pdf"],"reflow":{"available":true}}
200 70641B t=0.386144s     (content-type: application/epub+zip, etag "70641-1791582416891", body starts "PK")
```

**No `202` was observed.** A 4-page pass finished inside the route's 2 s grace, so the first request already answered 200 in 0.39 s with 70,641 bytes; `derived/reflow.json` records `pages: 4`, `text_pages: 4`, `layout_errors: 0`. The `202` → `200` path is decided on the phone by `ReflowDownloadTests` and on the Mac by its own suite; a live `202` needs a PDF that outlasts 2 s (the Mac measured 176 s for 535 pages), which this fixture was not. No Mac request log was captured; the curl sequence is the record.

## (c) and (d) — `Books/<id>.epub` and `downloads.json`

**Not observed.** The app container's `Books/` held only two EPUBs from earlier slices (`6f1a1f2e-….epub` 1.4 MB, `63e85c8d-….epub` 9.4 MB) and `downloads.json` held no entry for `c318fc75-…`. The download starts from the **Download to this phone** button and `simctl` cannot tap; the existing `MUSAEUM_PROBE_OPEN` path downloads `preferredFormat`, not the reflow, so it was not used as a stand-in. Nothing here claims the app downloaded or opened the book.

In its place: the Mac half is measured above (a 70,641-byte `PK` zip served on `format=reflow`), and the phone's half is covered by the unit suites.

## For the owner, by hand (two things)

1. **Tap Download to this phone on a PDF-only book, then Read.** Progress should show while the Mac lays the book out, the button should become Read, and the reader should open the reflowed EPUB (`Books/<id>.epub` in the app's container, 70,641 bytes for this fixture, and a `downloads.json` entry carrying `reflow.available: true`).
2. **Turn a page, then close.** The reader should report a fraction the Mac's row accepts: the book's `reading_percent` in the Mac's database moves to the fraction the phone reported.
