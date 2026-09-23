# Slice 2 — the upward path (the report on stop)

**Date:** 2026-09-22
**Slice:** 2 of 2 in `docs/specs/2026-09-22-client-v1-design.md` (CD8 draws the line here)
**Annex to:** that design. It settles **readings and wiring**, not product decisions — CD1–CD8 are closed and this document does not re-open them.
**Read first:** `docs/specs/2026-09-22-client-v1-design.md` (CD5 and CD8 above all), then `../musaeum/docs/rest-api.md` → *The one write* (`PUT /api/books/{id}/reading`), then `../musaeum/docs/superpowers/specs/2026-09-22-ios-companion-design.md` → D6 (a report is ordered by its *own* clock, and why not the server's).

---

## What this slice is

1. **A report on stop.** When the reader closes — and when the app goes to the background mid-read — the phone sends `PUT /api/books/{id}/reading` with the fraction it is at. The report's own timestamp travels only when the report had to wait (see the *what it carries* row below).
2. **A queue while the Mac is asleep.** The report that cannot be sent is kept on the phone and flushed when the Mac answers again, oldest first, so the Mac converges on the phone's latest position.
3. **D6 applied by the client.** A report that waited carries the phone's *clock* for when it was read — the Mac's D6 exists so a queued report cannot drag the library backwards past a later position set on the Mac, and the client is what supplies that timestamp. A live report omits it, so the Mac's clock is the truth while the Mac is answering.
4. **The download's `Range` resume, only if CD6's condition has fired** (one transfer large enough that restarting it hurts). The wire already serves `206`, so this is client-only work; the probe profile's library is a few hundred KB per book and has not fired it.

**Explicitly not in this slice:** search/filter UI, PDF in the reader, a local library cache, a per-device position map.

## The readings this slice must settle itself

| Reading | The rule to build | The alternative it beats | Reversal condition |
| ------- | ----------------- | ------------------------ | ------------------ |
| **When a report is sent** | on reader close, and on `scenePhase` leaving `.active` while the reader is open — one flush, both doors | only on reader close (a reader who never closes the book reports nothing) | a report arriving *during* a read is wanted for a live "where is this book" on the Mac |
| **What the report carries** | `percent` (from `currentLocation.locations.totalProgression`), plus the phone's clock **only when the report is flushed from the queue** — a live attempt omits `at` so the Mac's own clock is the truth | sending the locator (no — D5: it is an engine coordinate); always sending `at` (no — the contract says to omit it for a live read, and a phone whose clock trails would have its own report refused as stale by D6) | never; D5 is settled in the parent spec, and the live/queued split is the contract's own wording — **sharpened when built, see *Built — slice 2*** |
| **Where the queue write happens** | **before** the Mac is asked, removed on acceptance | attempt-then-queue (loses the report to a suspension mid-request, which is exactly the background door's expected outcome) | never |
| **Queue order on flush** | oldest report first, so the last write wins with the newest position | newest only (drops the ordering question, and loses a position set after the newest) | the Mac's route gains a compare-and-set the client can rely on |
| **A flush the Mac refuses** | **stops at the first "not now"** — a sleeping Mac must not be asked once per queued report | walking the whole queue regardless (a burst of refusals) | a batched report route, or a server that answers "how many will you take" |
| **A queue entry for a book the Mac no longer holds** | dropped on the 404, counted in the log, and the flush carries on past it | retried forever | never |
| **`Range` resume** | not built | a whole-file refetch | the first transfer large enough to hurt (CD6's own condition) |

## Acceptance criteria (as landed)

This table was a draft when the slice was planned; the deciders below are what each criterion actually got. **The authoritative list is `docs/specs/2026-09-22-client-v1-design.md` → *Acceptance criteria (slice 2)*, which also adds 2.8–2.10** (CD5 unchanged, the AC13 source walk, and the gates); this one is kept beside the plan because a plan that quietly rewrites itself teaches nothing.

| # | Criterion | Decider |
| - | --------- | ------- |
| 2.1 | Closing the reader sends exactly one `PUT` with the fraction the engine reports and the phone's timestamp | `ReadingWriteTests` over a stubbed `URLProtocol`: path, method, `Content-Type`, and the body's own field list |
| 2.2 | A report sent while the server is unreachable is queued, not lost, and the queue is empty once the server answers | `ReadingReporterTests` (a real connection refusal, then a stubbed 200) + the live `write-queued-mac-asleep.png` / `write-flushed.png` runs |
| 2.3 | A queue with three reports flushes oldest-first | `ReadingReporterTests`: the stub records the bodies in order, and each carries its own `at` — the reading's clock, not the flush's |
| 2.4 | A queued report for a 404'd book is dropped and announces itself | `ReadingReporterTests`: 200 / 404 / 200, three requests in order, empty queue, the flush carries on past the drop |
| 2.5 | The queue survives a restart | `ReportQueueTests` over a temporary directory + `ReadingReporterTests.testAQueuedReportIsStillThereAfterARelaunch` |
| 2.6 | **Live:** read to a position on the phone, close, and the Mac's own `reading_percent`/`reading_position` move | live probe + `sqlite3`, both directions: the Mac's `0.42` → the phone's `0.4198265179677819`; and the Mac's stale `0.05` → the phone's number with the CFI blanked |
| 2.7 | **Live:** with the Mac stopped, read, close, start the Mac, and the Mac's row catches up | live probe, both directions: queued with no listener on 8788, then the flush wrote the row with the queued report's own clock |

**One criterion the draft did not have, added because the build needed it:** *a live report omits the clock and a flushed one carries it* — the contract's own distinction, which `2.1`'s body assertion now decides. Without it a phone whose clock trails the Mac's would have its own report refused as stale.

## What the build found (the short version)

The full record is *Built — slice 2* in the design doc. In three lines: the queue is written **before** the Mac is asked (a suspension mid-request must not lose a reading); a flush **stops at the first "not now"**; and the probe script needed `chmod +x` and a base URL before it was the re-runnable instrument both this annex and `AGENTS.md` claimed it was.

## Start here

```bash
git log --oneline -3                      # ed7abf6 "initial ios app" — slice 1, the base; 1eac131 is slice 1's evidence and docs

# the gate, with the landed counts as the expected values
xcodegen generate     # first, always: a file added since the last generate is not in the target
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro, iOS 26.1 — an id, never a name
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build   # exit 0
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test    # 61 cases, 0 failures, 9 suites

# the live probe (its header carries the server recipe, and it refuses to run without base.txt + token.txt)
ACTION=write TAG=write BOOK=<book id> ./scripts/live-probe.sh
```

**Slice 2 is landed** — built, gated (61 cases), probed (three live runs) and its record written. The design's own scope ends here: CD8 drew v1 as two slices, so there is no slice 3, and what follows is `tasks.md`'s deferred list, each item revived only by its own stated condition. **The one product question this slice inherited is closed:** the owner reviewed Readium's typography on 2026-09-22 and accepted it, so CD1 stands and foliate-js is not revived.


## What must not move

- **CD5's rule.** The reader's opening position stays "whichever of the two is further along"; the write is what makes a *server* position appear, and a naive wiring (report on open, then read) would create a loop where the phone's own report drags it backwards.
- **CD3's state list.** The queue is the third kind of local state and does not grow a fourth: no local library database rides in with it.
- **The token.** It stays in the Keychain and in the `Authorization` header, and no log line carries it (slice 1's AC13 source walk must still be clean when this slice is done — re-run it).
- **Slice 1's criteria.** All 43 cases stay green; an AC that this slice changes is *added*, never renumbered.

## What the slice actually touched, in the order it was read

The plan's own reading order, corrected to what the build did — kept because the *shape* of it was right and the file names are the ones a later session wants:

1. `Musaeum/Core/Store/DownloadStore.swift` — **the shape the queue copies**, exactly as planned: one JSON index, an injectable root, `@MainActor @Observable`. Landed as `Musaeum/Core/Store/ReportQueue.swift`.
2. `Musaeum/Core/API/MusaeumClient.swift` — the request composer gained a `body:` (and the `Content-Type` that goes with it), and the `PUT` seam that existed with no caller now has one: `reportReading(id:percent:at:)`, beside a hand-written `readingBody(percent:at:)` whose whole job is that **absence is real absence** for `at`.
3. `Musaeum/Features/Reader/ReaderScreen.swift` + `Musaeum/Core/Reader/ReaderHost.swift` — the engine's `totalProgression` was indeed the value to carry; `ReaderModel` gained `settledFraction(timeout:)` (what the engine says *now*, with a bounded wait, and `nil` when it never laid out — `nil` is not `0`), and the screen gained the two doors.
4. `Musaeum/App/MusaeumApp.swift` — the probe seam, as planned: `MUSAEUM_PROBE_ACTION=write` is how the live write runs non-interactively. The reporter is also injected here and flushed on launch and on every return to `.active`.
5. **Not on the plan's list, and it had to be built:** `Musaeum/Core/Store/ReadingReporter.swift` — the thing that owns *when* a report is sent, and what happens to the answer. The plan's table named the rules; the build needed somewhere for them to live that is not a view.

