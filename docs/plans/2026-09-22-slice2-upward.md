# Slice 2 — the upward path (the report on stop)

**Date:** 2026-09-22
**Slice:** 2 of 2 in `docs/specs/2026-09-22-client-v1-design.md` (CD8 draws the line here)
**Annex to:** that design. It settles **readings and wiring**, not product decisions — CD1–CD8 are closed and this document does not re-open them.
**Read first:** `docs/specs/2026-09-22-client-v1-design.md` (CD5 and CD8 above all), then `../musaeum/docs/rest-api.md` → *The one write* (`PUT /api/books/{id}/reading`), then `../musaeum/docs/superpowers/specs/2026-09-22-ios-companion-design.md` → D6 (a report is ordered by its *own* clock, and why not the server's).

---

## What this slice is

1. **A report on stop.** When the reader closes — and when the app goes to the background mid-read — the phone sends `PUT /api/books/{id}/reading` with the fraction it is at, and the report's own timestamp.
2. **A queue while the Mac is asleep.** The report that cannot be sent is kept on the phone and flushed when the Mac answers again, oldest first, so the Mac converges on the phone's latest position.
3. **D6 applied by the client.** The report carries the phone's *clock* — the Mac's D6 exists so a queued report cannot drag the library backwards past a later position set on the Mac, and the client is what supplies that timestamp.
4. **The download's `Range` resume, only if CD6's condition has fired** (one transfer large enough that restarting it hurts). The wire already serves `206`, so this is client-only work; the probe profile's library is a few hundred KB per book and has not fired it.

**Explicitly not in this slice:** search/filter UI, PDF in the reader, a local library cache, a per-device position map.

## The readings this slice must settle itself

| Reading | The rule to build | The alternative it beats | Reversal condition |
| ------- | ----------------- | ------------------------ | ------------------ |
| **When a report is sent** | on reader close, and on `scenePhase` leaving `.active` while the reader is open — one flush, both doors | only on reader close (a reader who never closes the book reports nothing) | a report arriving *during* a read is wanted for a live "where is this book" on the Mac |
| **What the report carries** | `percent` (from `currentLocation.locations.totalProgression`) plus the phone's clock | sending the locator (no — D5: it is an engine coordinate) | never; D5 is settled in the parent spec |
| **Queue order on flush** | oldest report first, so the last write wins with the newest position | newest only (drops the ordering question, and loses a position set after the newest) | the Mac's route gains a compare-and-set the client can rely on |
| **A queue entry for a book the Mac no longer holds** | dropped on the 404, counted in the log | retried forever | never |
| **`Range` resume** | not built | a whole-file refetch | the first transfer large enough to hurt (CD6's own condition) |

## Acceptance criteria (draft — the implementing session writes the deciders it finds)

| # | Criterion | Decider |
| - | --------- | ------- |
| 2.1 | Closing the reader sends exactly one `PUT` with the fraction the engine reports and the phone's timestamp | stubbed `URLProtocol`: the request is asserted (path, method, body) — the same instrument as CD4's |
| 2.2 | A report sent while the server is unreachable is queued, not lost, and the queue is empty once the server answers | stub answering connection-refused, then 200 |
| 2.3 | A queue with three reports flushes oldest-first | stub recording request bodies in order |
| 2.4 | A queued report for a 404'd book is dropped and announces itself | stub answering 404 on the second entry |
| 2.5 | The queue survives a restart | store case over a temporary directory (slice 1's `StoreTests` shape) |
| 2.6 | **Live:** read to a position on the phone, close, and the Mac's own `reading_percent`/`reading_position` move | live probe + `sqlite3` on the probe profile, the number read either side |
| 2.7 | **Live:** with the Mac stopped, read, close, start the Mac, and the Mac's row catches up | live probe, both directions |

## What must not move

- **CD5's rule.** The reader's opening position stays "whichever of the two is further along"; the write is what makes a *server* position appear, and a naive wiring (report on open, then read) would create a loop where the phone's own report drags it backwards.
- **CD3's state list.** The queue is the third kind of local state and does not grow a fourth: no local library database rides in with it.
- **The token.** It stays in the Keychain and in the `Authorization` header, and no log line carries it (slice 1's AC13 source walk must still be clean when this slice is done — re-run it).
- **Slice 1's criteria.** All 43 cases stay green; an AC that this slice changes is *added*, never renumbered.

## Start here

```bash
git log --oneline -3                      # ed7abf6 "initial ios app" — slice 1, and this slice's base

# the gate, with slice 1's counts as the expected values
xcodegen generate     # first, always: a file added since the last generate is not in the target
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro, iOS 26.1 — an id, never a name
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build   # exit 0
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test    # 43 cases, 0 failures

# the live probe (its header carries the server recipe, including the two traps that cost a round each)
TAG=library ./scripts/live-probe.sh
```

Slice 1's readings are in *Built — slice 1* of the design, with its frames committed under `docs/evidence/slice1/`. **The one product question this slice inherited is closed:** the owner reviewed Readium's typography on 2026-09-22 and accepted it, so CD1 stands and foliate-js is not revived.

Then read, in order:

1. `Musaeum/Core/Store/DownloadStore.swift` — the shape a second local record (the queue) should copy: one JSON index, an injectable root, `@MainActor @Observable`.
2. `Musaeum/Core/API/MusaeumClient.swift` — where the write goes; the request composer and the status → outcome map are already there, and `PUT` needs the method seam that exists but has no caller yet.
3. `Musaeum/Features/Reader/ReaderScreen.swift` + `Musaeum/Core/Reader/ReaderHost.swift` — where the engine's `totalProgression` is already read (`onLocation`), which is the value the report carries.
4. `Musaeum/App/MusaeumApp.swift` — the probe seam; a new action (`MUSAEUM_PROBE_ACTION`) is how a live write gets run non-interactively.
