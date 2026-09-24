# Musaeum iOS

A reading client for a [Musaeum](https://github.com/jasonoh/musaeum) library on the Mac (locally `../musaeum`). It browses the library over the tailnet, downloads a book into its own storage, reads it — starting at the fraction the Mac last recorded, so a book carries on where you left it on the other machine — and sends a book the other way, into the Mac's own importer.

**The contract is not in this repo.** The Mac app serves the HTTP surface and owns its description:

- **`docs/rest-api.md` in the Musaeum repo** — routes, payloads, statuses, auth, failure semantics, API version 1. It is the interface this app is written against, and this README deliberately does not restate it. Locally that is `../musaeum/docs/rest-api.md` ([on GitHub](https://github.com/jasonoh/musaeum/blob/main/docs/rest-api.md)).
- **`../musaeum/scripts/api-smoke.sh`** — the contract's executable half: it exercises every route against a live app and prints PASS/FAIL per line. Run it when the server side looks wrong rather than guessing from the phone.
- **`../musaeum/README.md`** — what the Mac app is and does; this repo is the phone half of that product.
- **`docs/specs/2026-09-22-client-v1-design.md`** (this repo) — the client's own design: what it decides, what it deliberately does not do, and the measurements behind the reader engine.

## Build and run

```bash
xcodegen generate          # project.yml → Musaeum.xcodeproj (committed output; regenerate after adding a file)
open Musaeum.xcodeproj     # or, from the command line — the destination is an id, never a device name:
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro on iOS 26.1
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" test
```

Requires Xcode 27+, XcodeGen (`brew install xcodegen`), and **the Mac app running with its server switched on** (Settings → Phone access) for anything that touches the network.

## Pointing it at the Mac

1. In Musaeum on the Mac: **Settings → Phone access**, turn it on. The row shows the URL to type into the phone and the bearer token beside it.
2. In this app: **Connect** — paste the URL and the token, then check the connection. The health payload names the contract version, the app version, the number of books and whether the library share is mounted.

The phone must be on the same tailnet as the Mac. The server binds the tailnet address only; there is no LAN or public surface.

## What works today

Slice 1 (the *downward* path): configure and connect, the paginated library as a cover grid, a book's detail, a download into the app's own storage, and the reader opening at the fraction the Mac holds. Books already downloaded are readable with the Mac asleep or off.

Slice 2 (the *upward* path): the fraction is written back when the reader closes or the app leaves the foreground, queued on the phone while the Mac cannot take it and flushed when it answers — ordered by the report's own clock, which is what stops a phone's stale reading from dragging the Mac's position backwards.

Slice 3 (finding things): the Mac's own **eight sort orders** and its **full-text search**, so the same query returns the same books in the same order on both machines, plus a **filter sheet** carrying the contract's own vocabulary and the Mac's own counts — read status, format, a rating floor, and the library's own authors, series and tags. The sort is remembered between launches; the search is not.

Slice 4 (sending a book to the Mac): a book picked in the app — or shared to Musaeum from Files, Safari or Mail — goes to the Mac's own importer, so what lands is what a Mac-side import would have produced: the same metadata pass, the same covers, the same rule for a book you already had. The row reports what happened in the Mac's own words and claims nothing before the Mac has answered; a book past the Mac's size limit, or one it cannot take, says *that* rather than offering a retry, while a Mac that is busy or whose share is unmounted is worth waiting out — and the phone keeps its own copy, so **Try again** sends the same bytes rather than asking for the file again. A book handed over while the Mac cannot be reached waits in the app's own storage and goes out when it can.

**Not built yet:** PDF in the reader; resumable downloads (whole-file today, `docs/specs` CD6); an upload that outlives the app is a *new* send rather than a resumed one (the route has no `Range` and no idempotency key — a book the Mac already has is added rather than refused, so trying again loses nothing but the transfer); one book at a time; and a file that is not a file on the phone — an undehydrated iCloud Drive placeholder, a Photos item, a link — is reported rather than worked around. Plus the deferred list in `tasks.md`, each item revived only by its own stated condition.

## Layout

```
Musaeum/
  App/                    app entry and the root navigation
  Core/API/               contract models, the strict decoder, the HTTP client, the cover pipeline,
                          the progress report and the refusal rule that decides its fate
  Core/Store/             settings (Keychain + UserDefaults), the download index, local positions,
                          the report queue and the reporter that drives it, the upload's own state
                          and the hand-off a shared file leaves behind
  Core/Reader/            the Readium host and the pure initial-fraction rule
  Core/Support/           the launch seam the live probe drives
  Features/               Connect · Library · Detail · Downloads · Reader
Tests/MusaeumTests/       the deciders: contract fixtures, strict decoding, request composition,
                          the cover cap, positions, the queue, the reporter, the two writes and the
                          upload's refusal classes
Tests/Fixtures/contract/  payloads extracted from the contract document by scripts/vendor-contract-fixtures.sh
scripts/                  the fixture vendoring script, and live-probe.sh — the app's own instrument
docs/specs/, docs/plans/  this client's own design and the plan for each slice
docs/evidence/            the frames each slice's live probe produced, with the numbers beside them
```
