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
7. **No local library cache.** Local state is exactly: settings, the download index, local positions, and the report queue. No SQLite, no SwiftData, no catalogue copy.
8. **Readium is a pinned SPM dependency, never patched in place.** A divergence lives in our code.
9. **`project.yml` is the source of truth for build settings**; `Musaeum.xcodeproj` is generated output and is committed only so a clone opens without tooling.
10. **No secret in a log, no `any`-shaped decoding.** The bearer token appears in one place — the `Authorization` header — and in no `print`, no error message and no interface.
11. **A cover is bounded by its cell, never by its artwork.** `CoverImage`'s box comes from a child with no intrinsic size (`Palette.raised` with `.aspectRatio(2.0/3.0)`, the artwork in an `overlay`) — the Mac's own `aspect-[2/3] … object-cover` (`src/components/library/BookCard.tsx`). `.aspectRatio(_:contentMode:)` fits the **proposal** to the ratio, not the result: put an image anywhere the geometry is decided and a 3:2 jacket draws 2.25 cells wide and a 1:2 one rides over its own title. Three sites draw it (grid, detail hero, downloads row); `CoverBoxTests` decides the box, `docs/evidence/cover-box/` the crop.

## Gates

```bash
xcodegen generate     # first, always — a file added since the last generate is not in the target
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # xcode-select points at the Command Line Tools on this machine
DEV=39D29C73-B2DD-4041-8ECD-46923376D0F9   # iPhone 18 Pro, iOS 27.0 (slice 6 onward; the iOS 26.1 device is gone)
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test
TAG=library BOOK=<book id> ./scripts/live-probe.sh   # the UI instrument; its header carries the server recipe
ACTION=write TAG=write BOOK=<book id> ./scripts/live-probe.sh   # the write instrument (slice 2)
ACTION=share TAG=share BOOK=<book id> ./scripts/live-probe.sh   # the share instrument (slice 5) — **TAG is a label, ACTION is the switch**
TAG=detail DETAIL=<book id> ./scripts/live-probe.sh   # a book's detail, so the share door is in a frame
TAG=downloads DOWNLOADS=1 ./scripts/live-probe.sh   # the downloaded shelf itself — one row per book, the screen a tap otherwise reaches
TAG=chrome READER=chrome BOOK=<book id> ./scripts/live-probe.sh   # the reader's raised chrome (slice 6); also contents · typography · ink · paper
```

**The probe profile** the last three slices measured against is `~/.hermes/profiles/dev/cache/scratch/ios-probe` (its own `musaeum.db`, `library_root` pointed at its own folder, **13 books** — 8 seeded EPUBs plus the rows upload and smoke runs left — a `rest_api_token`, and `rest_api_port` **8789**, because the owner's packaged app holds 8788) — and scratch is pruned when idle, so if it is gone, rebuild it from the header of `scripts/live-probe.sh` rather than hunting for it: the seeding is six commands and the imports hydrate in about a minute. The Mac app is started with `env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<that profile> npm run dev` from `../musaeum` (`ELECTRON_RUN_AS_NODE` is set in this shell and makes Electron run as plain Node — no window, no app).

**The probe needs two things, and the script refuses to guess either:** `$ROOT/token.txt` and `$ROOT/base.txt` (the server binds the **tailnet** address, so `127.0.0.1` answers nothing — `lsof -nP -iTCP:8788 -sTCP:LISTEN` says which). A run with no base URL comes up unconfigured, logs nothing, and reads as "the probe found nothing" — which is why it is a hard failure now.

**The simulator's state, verified 2026-09-25 after slice 6a's probes:** device `39D29C73-…` booted, `dev.jasonoh.Musaeum` installed, holding `Books/63e85c8d-….epub` (**Designing Machine Learning Systems**, 173 contents entries) with its position at `0.2`; the Mac's row for it is `reading` at `0.2`. The probe profile was rebuilt that day (two books, `rest_api_port` 8789) and the scripts' `DEVICE=` must name this device. **A reading taken on a shut-down simulator returns nothing and reads as "the app is gone"** — `xcrun simctl listapps` on a `Shutdown` device lists no apps and `get_app_container` fails with *Unable to lookup in current state: Shutdown*; boot it first (`xcrun simctl bootstatus <id> -b`), then look.

**A probe that waits cannot see a launch defect.** Every run in slice 1 sampled its frame after a 20–35 s wait, so a white launch screen — a real defect the owner hit the moment he ran the app from Xcode — survived three green probes: it lives only in the first frames, and the probes' own `MUSAEUM_PROBE_*` env meant the app was always already configured and never drew the connect screen at all. A cold-launch frame is `xcrun simctl launch <dev> <id>` immediately followed by `xcrun simctl io <dev> screenshot`, **with no sleep in between**; the fix that defect needed was `UIUserInterfaceStyle: Dark` in `project.yml`, because `.preferredColorScheme(.dark)` applies only once SwiftUI paints. Both the before/after frames are committed under `docs/evidence/slice1/`.

**Two traps slice 2's write runs paid for, and both cost more than one attempt.** (a) **The Mac writes reading state *after* its listener closes** — stopping the dev app by its listener pid frees `8788` first and runs the quit handshake second, which flushes reading state into the profile's SQLite *and* the book's `metadata.json`; the next startup rebuilds the row from the derived store as well. An edit to the probe profile's row made in that window is silently overwritten and the old value comes back, which is a run that looks green and decides nothing. Edit either once `pgrep -f 'electron/dist/Musaeum.app'` is **empty** (not merely `lsof` clean), or **after the Mac is up and immediately before the run**. (b) **A row equal to the phone's position decides nothing** — a report that "succeeds" against the Mac's own number moves no position, only a clock. Set the row to a *different* number first, with a stale CFI beside it so the D5 blanking has something to remove. Both are written up in `docs/evidence/slice2/README.md`.

Expected on the committed slice-6a tree: build **exit 0**, no warnings in this repo's own files beyond the Xcode 27 `main actor-isolated` ones in six older test files; test **exit 0, 158 cases, 0 failures across 19 suites** (slice 6a's 21 on top of a 137 baseline measured on iOS 27 — the slice-5 record said 136) (17 files — the seventeenth is the `URLProtocol` stub; slices 1–4's own 117 across 15 are inside that and unchanged); and `../musaeum/scripts/api-smoke.sh --profile <the probe profile>` against the same server **70 passed, 0 failed** (it needs `--profile` or `MUSAEUM_USER_DATA` — with neither it exits before running a check). **Reconcile a moved total against the cases you actually added** — slice 5 moved it by exactly its own 19.

**The destination is an `id`, never a name.** `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` fails on this machine (*Unable to find a device matching the provided destination specifier* — the name resolves across runtimes and Xcode 27 gives up). This bit the first build of slice 1, and it is the one command in this file that cannot be run as it reads.

**A gate reports exit codes, so a green total is not a decider.** A test file written after the last `xcodegen generate` is absent from the target: the suite re-runs, the total does not move, and the new criterion is undecided while everything reads pass. Read the per-suite line, not only the total.

Both must exit 0. Report the test count per file, not an adjective. A UI claim needs a **live probe** — a simulator run against the Mac, with the number or the frame it produced — because nothing in this repo's unit suite can see a screen. The probe's own frames and numbers from both slices are committed under `docs/evidence/slice1/` and `docs/evidence/slice2/`. **A claim that needs a tap, or a backgrounded app, is a claim for a human frame** — `simctl` can drive neither, and saying so is the honest answer.

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
