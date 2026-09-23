# Musaeum iOS

A reading client for a [Musaeum](https://github.com/) library on the Mac. It browses the library over the tailnet, downloads a book into its own storage, and reads it — starting at the fraction the Mac last recorded, so a book carries on where you left it on the other machine.

**The contract is not in this repo.** The Mac app serves the HTTP surface and owns its description:

- **`docs/rest-api.md` in the Musaeum repo** — routes, payloads, statuses, auth, failure semantics, API version 1. It is the interface this app is written against, and this README deliberately does not restate it. Locally that is `../musaeum/docs/rest-api.md`.
- **`../musaeum/scripts/api-smoke.sh`** — the contract's executable half: it exercises every route against a live app and prints PASS/FAIL per line. Run it when the server side looks wrong rather than guessing from the phone.
- **`docs/specs/2026-09-22-client-v1-design.md`** (this repo) — the client's own design: what it decides, what it deliberately does not do, and the measurements behind the reader engine.

## Build and run

```bash
xcodegen generate          # project.yml → Musaeum.xcodeproj (committed output; regenerate after adding a file)
open Musaeum.xcodeproj     # or, from the command line — the destination is an id, never a device name:
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro on iOS 26.1
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" test
```

Requires Xcode 27+, XcodeGen (`brew install xcodegen`), and **the Mac app running with the REST API enabled** for anything that touches the network.

## Pointing it at the Mac

1. In Musaeum on the Mac: **Settings → Remote access**, turn it on. The row shows the URL to type into the phone and the bearer token beside it.
2. In this app: **Connect** — paste the URL and the token, then check the connection. The health payload names the contract version, the app version, the number of books and whether the library share is mounted.

The phone must be on the same tailnet as the Mac. The server binds the tailnet address only; there is no LAN or public surface.

## What works today

Slice 1 (the *downward* path): configure and connect, the paginated library as a cover grid, a book's detail, a download into the app's own storage, and the reader opening at the fraction the Mac holds. Books already downloaded are readable with the Mac asleep or off.

**Not built yet** (slice 2): the progress report travelling back up — the app does not yet write where you stopped on the phone back to the Mac. Downloads are whole-file; resumable downloads are deferred (`docs/specs`, CD6).

## Layout

```
Musaeum/
  App/                    app entry and the root navigation
  Core/API/               contract models, the strict decoder, the HTTP client, the cover pipeline
  Core/Store/             settings (Keychain + UserDefaults), the download index, local positions
  Core/Reader/            the Readium host and the pure initial-fraction rule
  Features/               Connect · Library · Detail · Downloads · Reader
Tests/MusaeumTests/       the deciders: contract fixtures, strict decoding, request composition, the cover cap, positions
Tests/Fixtures/contract/  payloads extracted from the contract document by scripts/vendor-contract-fixtures.sh
scripts/                  the fixture vendoring script
```
