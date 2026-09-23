# Musaeum iOS — agent brief

An iOS reading client for a Musaeum library on the Mac. SwiftUI, deployment target **iOS 18**, built with XcodeGen from `project.yml`. The reader is **Readium 3.11** (`EPUBNavigatorViewController`).

**Load this before you touch code, then the design.** `docs/specs/2026-09-22-client-v1-design.md` carries the decisions (CD1–CD8), the acceptance criteria, the deferred items with their revival conditions, and the measurements the reader engine was chosen on. The Mac repo's `docs/superpowers/specs/2026-09-22-ios-companion-design.md` carries the workstream; its D1/D5/D6/D12/D14/D15 are inherited here and are **not** re-opened.

| Read this                          | Before you touch                                                                       |
| ---------------------------------- | -------------------------------------------------------------------------------------- |
| `../musaeum/docs/rest-api.md`      | anything that crosses the wire: a model, a request, a status code, a payload field      |
| `docs/specs/…-client-v1-design.md` | the reader, the download store, positions, or a decision that looks like a fork        |
| `../musaeum/.claude/skills/verify/SKILL.md` | bringing the Mac up on an isolated profile to probe against (`MUSAEUM_USER_DATA`) |

## Invariants — never break these

1. **The contract lives in the other repo.** Never restate `docs/rest-api.md` here — models and test fixtures derive from it (`scripts/vendor-contract-fixtures.sh` extracts the document's own `json payload=` blocks). A field you need and the document does not name is a change to the *server* and its document, in the Mac repo, in one slice.
2. **The wire carries no path.** A book is asked for by `id` and by `format`; the local file's name is this app's business. Nothing composes a `file://` URL for a web view — Readium reads the file through its own file asset, and the app runs no HTTP server.
3. **The fraction is the only position that travels.** `reading.percent` in, `percent` out (slice 2). A Readium `Locator` is an engine coordinate and stays local.
4. **`null` is not absent.** Every always-present field decodes strictly: a missing key **throws**, an explicit `null` decodes to `nil`. A silent `nil` title is the drift this rule exists to catch.
5. **The server is never a dependency.** Offline, 401, 404, 503 and an unknown `apiVersion` are ordinary states with their own surfaces, never a crash and never a dialog nobody can act on. Reading a downloaded book must work with every one of them true.
6. **Covers are pipelined two at a time, and `503 busy` is retried** honouring `Retry-After`. The cap is the server's own budget; a fan-out of 60 answers 58 refusals.
7. **No local library cache.** Local state is exactly: settings, the download index, local positions, and (slice 2) the report queue. No SQLite, no SwiftData, no catalogue copy.
8. **Readium is a pinned SPM dependency, never patched in place.** A divergence lives in our code.
9. **`project.yml` is the source of truth for build settings**; `Musaeum.xcodeproj` is generated output and is committed only so a clone opens without tooling.
10. **No secret in a log, no `any`-shaped decoding.** The bearer token appears in one place — the `Authorization` header — and in no `print`, no error message and no interface.

## Gates

```bash
xcodegen generate     # first, always — a file added since the last generate is not in the target
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro, iOS 26.1 (the one this slice measured on)
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test
TAG=library BOOK=<book id> ./scripts/live-probe.sh   # the UI instrument; its header carries the server recipe
```

**The probe profile slice 1 measured against** is `~/.hermes/profiles/dev/cache/scratch/ios-probe` (its own `musaeum.db`, `library_root` pointed at its own folder, 8 seeded EPUBs, a `rest_api_token`) — and scratch is pruned when idle, so if it is gone, rebuild it from the header of `scripts/live-probe.sh` rather than hunting for it: the seeding is six commands and the imports hydrate in about a minute. The Mac app is started with `env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<that profile> npm run dev` from `../musaeum` (`ELECTRON_RUN_AS_NODE` is set in this shell and makes Electron run as plain Node — no window, no app).

**The simulator's state, verified 2026-09-22 after the probe:** device `DE0B5601-…` booted, `dev.jasonoh.Musaeum` and the Readium harness's `dev.jasonoh.ReadiumProbe` both still installed, and the phone **still holding its own copy** — `Books/ef91875e-….epub` (660,053 bytes, its cover beside it) with `positions.json` at `0.4198265179677819`, the fraction the offline run opened at. So `TAG=offline` reproduces the offline reading with no download step, and `TAG=read` re-downloads. The throwaway Readium harness is still at `~/.hermes/profiles/dev/cache/scratch/readium-harness` (`rt/` = the tag checkout, `Probe/` = the app, its `run.log` and frame) if a Readium measurement is ever needed again. **A reading taken on a shut-down simulator returns nothing and reads as "the app is gone"** — `xcrun simctl listapps` on a `Shutdown` device lists no apps and `get_app_container` fails with *Unable to lookup in current state: Shutdown*; boot it first (`xcrun simctl bootstatus <id> -b`), then look.

**A probe that waits cannot see a launch defect.** Every run in slice 1 sampled its frame after a 20–35 s wait, so a white launch screen — a real defect the owner hit the moment he ran the app from Xcode — survived three green probes: it lives only in the first frames, and the probes' own `MUSAEUM_PROBE_*` env meant the app was always already configured and never drew the connect screen at all. A cold-launch frame is `xcrun simctl launch <dev> <id>` immediately followed by `xcrun simctl io <dev> screenshot`, **with no sleep in between**; the fix that defect needed was `UIUserInterfaceStyle: Dark` in `project.yml`, because `.preferredColorScheme(.dark)` applies only once SwiftUI paints. Both the before/after frames are committed under `docs/evidence/slice1/`.

Expected on the committed slice-1 tree (`ed7abf6`): build **exit 0**, no warnings in this repo's own files; test **exit 0, 43 cases, 0 failures across 6 suites** (7 files — the seventh is the `URLProtocol` stub); and `../musaeum/scripts/api-smoke.sh` against the same server **56 passed, 0 failed**.

**The destination is an `id`, never a name.** `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` fails on this machine (*Unable to find a device matching the provided destination specifier* — the name resolves across runtimes and Xcode 27 gives up). This bit the first build of the slice, and it is the one command in this file that cannot be run as it reads.

**A gate reports exit codes, so a green total is not a decider.** A test file written after the last `xcodegen generate` is absent from the target: the suite re-runs, the total does not move, and the new criterion is undecided while everything reads pass. Read the per-suite line, not only the total.

Both must exit 0. Report the test count per file, not an adjective. A UI claim needs a **live probe** — a simulator run against the Mac, with the number or the frame it produced — because nothing in this repo's unit suite can see a screen. The probe's own frames and numbers from slice 1 are committed under `docs/evidence/slice1/`.

## Escalate — stop and hand back — when

- The task needs a decision the design doc does not settle.
- Readium would have to be forked, patched, or replaced (CD1's revival condition is a *reading*, so bring the measurement).
- The contract would have to change: that is a slice in the **Mac** repo.
- The work exceeds roughly 10 files.
- Two consecutive repair attempts fail on the same test.

## Conventions

- Swift 6 language mode, `@MainActor` on view models; `async/await`, no completion handlers.
- One type per file, `PascalCase.swift`; a pure rule lives in its own file so a test can reach it without a view.
- Networking goes through `MusaeumClient`; a view never builds a `URLRequest`.
- Views are small and composable; state lives in `@Observable` models.
- Markdown prose is not hard-wrapped: one line per paragraph, bullet and table row.
