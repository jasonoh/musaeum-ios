# Musaeum iOS — a reading client for the Mac's library (v1)

**Date:** 2026-09-22
**Status:** **slice 2 is built, gated and probed** (2026-09-23) — not yet committed; the owner commits this repo himself. Slice 1 landed as `ed7abf6` (*initial ios app*, 44 files, 4,803 insertions) and its numbers are in *Built — slice 1* at the end of this document, together with the corrections that build made to its own commands; the probe's frames are committed at `docs/evidence/slice1/`. Slice 2 (the upward path) is complete against its annex `docs/plans/2026-09-22-slice2-upward.md`: **build exit 0, 61 cases across 9 suites, 0 failures**, and three live probe runs against a real Musaeum — the numbers are in *Built — slice 2* below and its frames at `docs/evidence/slice2/`. That closes CD8's own scope: the design has no slice 3. What comes next is the deferred list's, revived only by its stated condition. The three forks slice 1 rests on were settled by the owner on 2026-09-22 (CD1, CD2 and the slice boundary) — Readium for v1, iOS 18, and slice 1 is the whole *downward* path.
**Scope:** a SwiftUI app that talks to a running Musaeum on the Mac over the tailnet: configure (base URL + token), connect-check, the paginated library as a cover grid, a book's detail, a download into the app's own storage, the reader opening at the fraction the Mac holds (slice 1), and the fraction written back when the reader closes or the app leaves the foreground, queued while the Mac cannot take it (slice 2). **Not in v1:** resumable downloads, search UI, facets/filters UI, metadata edits, device sends, annotations.
**Depends on (both read, neither restated):** `musaeum/docs/rest-api.md` — the frozen contract, API version 1, written against commit `0a0bdd4`; and `musaeum/docs/superpowers/specs/2026-09-22-ios-companion-design.md` — the workstream's design, whose D1 (bespoke app, own repo), D5 (the fraction is the member that travels), D6 (a report is ordered by its clock), D12 (the contract is provable without a phone), D14 (the Mac must be running; the client caches so that *reading* does not need it) and D15 (Range) are decisions this document **inherits and does not re-open**.
**Supersedes:** nothing.

---

## Why now

The Mac side is finished: the server, the read surface, the one write and the Settings row are built, reviewed and committed (`2477944`, `707313b`, `47e5381`, plus slice 2), and `scripts/api-smoke.sh` walks the whole contract against a live app. What has never existed is a *client*: nothing has cached a book, held progress, or spoken to a Mac that is asleep. v1's own definition (D1) ends with a book readable on the phone that resumes where the Mac left off — so the workstream is not done until this app exists.

**The one reading the Mac spec left open, measured today, 2026-09-22.** The parent spec names Readium Swift as its candidate reader and says plainly it is "general knowledge, not verified from this machine". A throwaway harness outside both repos settled it before a line of this app was written: an XcodeGen project depending on Readium `3.11.0` (a local clone of the tag) built clean for the **iOS 26 simulator under Xcode 27 / Swift 6.4** — Readium and its nine transitive packages — and then, installed and launched, opened a real EPUB off the share:

| Measurement                          | Value                                                              |
| ------------------------------------ | ------------------------------------------------------------------ |
| book                                 | `Negotiation Genius…epub`, 660,053 bytes, 26 reading-order items    |
| `publication.locate(progression: 0.42)` | `href=OEBPS/…c06_r1.htm progression=0.07 total=0.42 position=113` |
| after open, `currentLocation`        | `totalProgression = 0.4198265179677819`                            |
| `go(to: 0.75)` → `ok=true`, landed   | `totalProgression = 0.7490203958605446`                            |

That is the phone-side mirror of the number the Mac's own probe landed at for the same request (`0.4226639399398549` — `ios-companion-design.md`, D17). Both engines honour a requested fraction to within half a page, which is what makes a fraction a coordinate two engines can share (D5). `totalProgression` is also reported continuously by the navigator, so the *upward* half (slice 2) reads the same quantity it opens at.

## D-numbered decisions

### CD1 — Readium 3.11 is the v1 reader (settled)

**Decision:** the phone reads EPUB through the Readium Swift toolkit, pinned to `3.11.0`, added as an SPM dependency on `https://github.com/readium/swift-toolkit`. `EPUBNavigatorViewController` renders; `publication.locate(progression:)` converts the contract's fraction into a `Locator`; `currentLocation.locations.totalProgression` is the quantity the client will report.

**Why:** it is the parent spec's own candidate, and it now has a measurement behind it rather than a reputation — it built here, opened one of *this* library's books, and honoured a fraction to four decimal places. It is BSD-licensed, maintained, and its coordinate model already carries the fraction the wire carries, so the client's position plumbing is "hand it a number, read a number" rather than a translation layer.

**Rejected: foliate-js in a `WKWebView`** — the Mac's own engine, which would make page mechanics, CFI handling, TOC and in-book search behave identically on both devices and reuse the tree already vendored in the Mac repo. It is rejected for v1 on cost, not on quality: the engine is a bundle of JS we would have to keep in step across two repos, and every capability the Mac has (TOC, search, images, CSS) becomes a message we own the protocol for, whereas Readium gives it as a Swift API. **Revival condition:** a typography or fidelity defect that Readium's `EPUBPreferences`/CSS pipeline cannot answer *and* that foliate-js demonstrably handles — i.e. a defect found by looking at the phone, not by reasoning about it.

**Consequence, stated honestly:** the phone's reading experience is Readium's, not the Mac's, and the owner judges that by looking at it. Readium ships its own CSS; the app's own palette (the Mac's amber-on-near-black "dark library" look) can only reach the page through `EPUBPreferences`/`CSSRSProperties`, which slice 1 exposes for exactly one preference (theme) and no more.

### CD2 — iOS 18, one declarative project

**Decision:** deployment target **iOS 18.0** (Readium's floor is 15, so this is our choice). The Xcode project is generated by **XcodeGen** from `project.yml`, and the generated `.xcodeproj` is committed so a clone opens in Xcode with no extra tooling; `project.yml` is the source of truth and the only file edited when the target changes.

**Why:** iOS 18 admits `@Observable`, `SwiftUI`'s current navigation APIs and the modern concurrency surface without the availability gymnastics an iOS 17 floor forces across the app, and it covers every device the owner might read on. XcodeGen exists on this machine (`/opt/homebrew/bin/xcodegen`), and a generated project is the difference between a repo whose build settings are reviewable text and one whose build settings are a 900-line `project.pbxproj` diff — while a committed `.xcodeproj` keeps the "clone and open" promise that a gitignored one breaks.

**Rejected:** a hand-authored `project.pbxproj` (unreviewable, and every file addition becomes a merge hazard); Tuist (not installed; heavier than this app needs).

### CD3 — there is no local library database. The server *is* the library.

**Decision:** the app holds exactly three kinds of local state, and no fourth:

1. **Settings** — base URL (UserDefaults) and the bearer token (Keychain).
2. **The download index** — one small JSON record per book the phone has pulled: the book's payload *as fetched* (so a downloaded book can be listed, opened and described with the Mac asleep), the local file name, its byte count, and when it was fetched. This is the surface that makes D14's promise true — reading does not need the Mac.
3. **The report queue** (slice 2) — the fractions that have not been accepted yet.

Everything else — the library list, the facets, a book's detail — is fetched from the server and **not** cached. **What this design deliberately does not need:** a sync engine, a delta protocol, a local SQLite/SwiftData store, a migration story for it, conflict resolution, or a background refresh policy.

**Why:** the list is paged, latency-bound and cheap (the contract's own numbers: covers are ~79 KB and read in 0.05 s, the JSON routes answer from SQLite and never touch the share), so a local copy of 7,100 rows would buy a second source of truth, a staleness question and a schema, to save one request. What genuinely must survive the Mac being asleep is *the book you are reading*, and that is the download, not the catalogue.

**Consequence, named so it is not discovered:** with the Mac asleep the app can show the downloaded shelf and read from it, and **cannot** browse or search the library. That is D14's own line, not a defect introduced here.

### CD4 — the wire is decoded strictly, and the goldens are vendored by script

**Decision:** the payloads in `docs/rest-api.md` are transcribed once into `Tests/Fixtures/contract/*.json` **by a script that parses the document itself** (`scripts/vendor-contract-fixtures.sh`, reading `../../musaeum/docs/rest-api.md`, or `MUSAEUM_DOC` when set), and the app's models are hand-written `Codable` types whose decoding of an **always-present** field is strict: a missing key throws, an explicit `null` decodes to `nil` (the contract says "every field is always present; a value the row does not hold is `null`… so a client's decoding is unconditional").

**Why:** a hand-typed fixture is a second hand-copy of the contract, which is the thing that rots first; deriving the fixtures from the document means the client's deciders and the server's goldens are reading the same text. Strictness is what turns the contract's promise into a decision: with the synthesized `Codable` decoding, a missing key and an explicit `null` are indistinguishable, so a server that dropped a field would render as a book with a `nil` title and no test could object.

**Deliberately not needed:** no code generation, no JSON Schema, no `apiVersion` negotiation beyond a refusal — the contract's version is one integer and the client refuses what it does not know (CD7).

### CD5 — the phone opens at the fraction the Mac holds, and keeps its own precise place locally

**Decision:** when a book is opened, the reader's initial location is a fraction:

- the server's `reading.percent` when the book has no local record, or when the local record's fraction is **not greater**;
- otherwise the phone's own last position, restored from the precise Readium `Locator` the app stored locally.

In one line: **the reader opens at whichever of the two is further along**, and a local `Locator` is kept for the phone's own benefit so a resume on the phone is exact.

**Why:** the fraction is what travels (D5) and a `Locator` is an engine coordinate that must never go on the wire — but keeping one *locally* costs nothing and buys back the precision the fraction loses, for the one reader that can use it. Taking the further-along of the two is the rule that never loses the reader's place: it needs no clock comparison across two machines (which D6's ordering deliberately does for the *write*, where a regression would drag the library backwards, and which would be the wrong instrument here, where a regression would only lose the reader's own page). **Rejected:** the phone's local position always — it silently ignores a Mac that read further, which is the one thing the workstream exists to carry. **Rejected:** a clock comparison against `reading.updatedAt` — the two machines' clocks are the residual D6 already records, and this decision does not need a second consumer of it. **Revival:** a book where the phone's own position is *stale yet further* (rereading after a jump backwards on the Mac), reported from the phone rather than reasoned about.

**Consequence:** the phone's `Locator` is *not* the same object the Mac's CFI is, and nothing tries to reconcile them — exactly the position the schema already takes.

### CD6 — downloads go into the app's own storage, and are excluded from backup

**Decision:** a book is fetched with `URLSession` into `Application Support/Books/<book id>.<ext>`, named by the extension the server served (`formats[0]` of the payload — the contract's own preference order — never a canonical name), and that directory is marked `.isExcludedFromBackup`: it is a cache of files that exist on the Mac, and an iCloud backup of 500 MB of EPUBs is a cost with no reader behind it.

**Why:** the client asks for a book by id and format and never by path (the wire carries no path), so the local file's own name is the client's business; and the app must be able to answer "is this downloaded" without touching the network.

**Deferred: resumable downloads.** The contract supports a single `Range` and the library holds **80 books whose EPUB exceeds 100 MB** (the largest 528 MB — the parent spec's census). Slice 1 fetches whole files and treats a dropped transfer as a failed download. **Revival condition:** one transferred file large enough that restarting it hurts — i.e. the owner reports it, or the first 100 MB+ book is pulled over the tailnet.

### CD7 — failure is a surface, not a dialog

**Decision:** the app treats the contract's ordinary answers as states, never as errors to shout about:

| Situation                                      | What the client does                                                                                                 |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `library: "offline"` in `/api/health`          | says so on the library screen, still lists (the JSON routes answer from the cache) and still opens downloaded books    |
| the Mac unreachable / connection refused        | the library screen says the Mac is not answering, offers Retry, and the downloaded shelf stays usable                  |
| **401**                                        | a wrong or rotated token is a credential problem: the connect screen says so and links to the settings                  |
| `apiVersion` ≠ 1                               | the client refuses the server by name rather than half-decoding it                                                      |
| **503 `busy`** on a byte route                 | retried, honouring `Retry-After`, and covers are fetched **two at a time** — the budget is two, and a fan-out of 60 answers 58 refusals |
| **503 `library offline`** on a byte route      | a book cannot be downloaded right now; the row says the share is offline                                                |
| **404**                                        | an unknown book is a missing book; the client neither retries nor explains which of the contract's reasons applied       |

**Why:** the contract's failure table is written for a client that is not a dependency of the server, and D14 makes the Mac's absence routine rather than exceptional. A client that surfaces these as errors would be lying about what happened.

### CD8 — the slice boundary: down in slice 1, up in slice 2

**Decision:** slice 1 is the **downward** path end to end — configure, connect, list, open a book's detail, download it, and read it starting at the fraction the Mac holds. Slice 2 is the **upward** path — the report on stop, its queue while the server is unreachable, and D6's ordering — plus resumable downloads if CD6's condition has fired.

**Why:** the two halves have different instruments. The downward half is decided by decoding the contract's goldens, a stubbed `URLProtocol`, and a live probe that reads the app's own screen; the upward half adds a write against a live server and a queue whose ordering is a rule about clocks. Cutting between them keeps each half's evidence the kind of evidence it actually needs — and the owner chose the bigger slice 1 as the *downward* half, which is the reading path, the thing that has never existed.

## Acceptance criteria (slice 1)

1. **The build is reproducible from a clone.** `xcodegen generate && xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` succeeds with no manual step; `project.yml` is the only build-settings source. _Decider:_ the two commands, exit 0. **Deviation 1: the `name=` form of that destination does not resolve on this machine — the working command is `-destination "id=DE0B5601-…"`, which is what was run.**
2. **Every payload in the contract decodes.** Each vendored fixture (`health`, `library`, `book`, `facets`, `reading`, `error`) decodes into its model with the values the document states — including `reading: {status, percent, updatedAt}` with `percent` present, and a book whose nullable metadata (`isbn10`, `seriesName`, `goodreadsId`…) is explicitly `null`. _Decider:_ unit cases over the fixtures, asserting field values rather than "did not throw".
3. **A missing always-present field is refused, an explicit `null` is not.** Removing any top-level key from a `book` fixture makes decoding **throw**; setting it to `null` decodes to `nil`. _Decider:_ two cases over a mutated copy of the golden.
4. **`apiVersion` is checked.** A health payload with `apiVersion: 2` is refused by the client with a named outcome, and `apiVersion: 1` is accepted. _Decider:_ unit cases.
5. **The client asks the contract's routes, and only those.** The request builder is a pure function: `/api/health`, `/api/library?limit=&offset=` with the contract's defaults, `/api/books/{id}`, `/api/books/{id}/cover?size=full&v=<version>`, `/api/books/{id}/file?format=<ext>` — each carrying `Authorization: Bearer <token>`, and the cover URL carrying the **version** member (a replaced cover must not be answered from a cache). _Decider:_ unit cases asserting the composed `URLRequest`s, including the default `limit = 100` and the `v=` parameter.
6. **401 and 503 are distinguished, not collapsed.** A stubbed 401 with `WWW-Authenticate` yields the credential outcome; a 503 with `Retry-After` yields the retryable outcome and the retry honours the header. _Decider:_ `URLProtocol` stub cases over the client.
7. **Covers are fetched two at a time, and a 503 `busy` is retried rather than dropped.** A page of 9 covers against a stubbed server that answers 503 for the first two requests in flight yields all 9 images and never has more than 2 requests open. _Decider:_ a case that counts concurrent in-flight requests in the stub.
8. **A downloaded book is readable with the server unreachable.** After a download, the app lists it from its own index, and opening it renders the book **without any network request** — the stubbed client records zero calls. _Decider:_ unit case over the store + a UI-level probe stub.
9. **The reader opens at the Mac's fraction.** With a book whose payload carries `reading.percent = 0.42` and no local position, opening it lands near 42% — measured, not asserted by construction, and reported with the number the engine gives (`currentLocation.locations.totalProgression`). _Decider:_ the **live probe** (a simulator run against the live server, reading the landing number off the app's own log) plus the harness measurement above.
10. **The reader opens at whichever of the two positions is further along.** With a local locator stored at 0.70: a book the server reports at 0.42 opens at **0.70**, and the same book reported at 0.80 opens at **0.80** — a Mac that read further is never ignored, and a stale local position never drags the reader backwards. _Decider:_ unit cases over the pure `initialFraction(local:server:)` function, one case per direction.
11. **The real library loads on the phone.** Against a live Musaeum on an isolated profile, the app's grid shows the first page of books with their covers painted, and scrolling to the end of the page fetches the next one. _Decider:_ the **live probe** — frames captured from the simulator, with the book count read off the health screen.
12. **The app is usable with the Mac asleep.** With the server stopped, the app opens, says the Mac is not answering, retries on demand, and reads a already-downloaded book. _Decider:_ live probe with the server stopped.
13. **No `file://`, no path, no token in a log.** The app never composes a file URL for a book it serves to a web view — Readium reads the local file through its own file asset (no HTTP server inside the app), and no code path logs the bearer token. _Decider:_ a source walk over the repo for `URL(string: "file:` / `tok`-logging, plus the request composer's unit case asserting the header is the only place the token appears.
14. **Gates.** `xcodebuild build` and `xcodebuild test` both exit 0 on the slice's own tree; the test count is reported per file.

## Acceptance criteria (slice 2 — the upward path)

Added by slice 2, never renumbered: slice 1's 14 criteria above are unchanged, and the 18 cases that decide them still pass.

| # | Criterion | Decider |
| - | --------- | ------- |
| 2.1 | **Closing the reader sends exactly one `PUT` with the fraction the engine reports and the phone's timestamp** | `ReadingWriteTests`: the request is asserted (path, method, `Content-Type`, and the body's own field list) over a stubbed `URLProtocol` — the same instrument as CD4's |
| 2.2 | **A report sent while the server is unreachable is queued, not lost, and the queue is empty once the server answers** | `ReadingReporterTests`, over a client pointed at a port nothing listens on, then a stubbed 200 — plus the **live** half: `write-queued-mac-asleep.png` and `write-flushed.png` |
| 2.3 | **A queue of three reports flushes oldest-first, each carrying its own read time** | `ReadingReporterTests`: the stub records the bodies; the case reads them back in order and asserts the `at` of each is the reading's clock, not the flush's |
| 2.4 | **A queued report for a 404'd book is dropped and announces itself, and the flush carries on past it** | `ReadingReporterTests`: the stub answers 200 / 404 / 200, and the case asserts three requests in order with an empty queue after |
| 2.5 | **The queue survives a restart** | `ReportQueueTests` over a temporary directory, and `ReadingReporterTests` for the reporter-over-a-reopened-queue shape — slice 1's `StoreTests` pattern |
| 2.6 | **Live: read to a position on the phone, close, and the Mac's own `reading_percent`/`reading_position` move** | live probe + `sqlite3` on the probe profile, the number read either side. Two runs, both directions: the Mac's `0.42` → the phone's `0.4198265179677819`; and the Mac's stale `0.05` → the phone's `0.4198265179677819` with `reading_position` blanked |
| 2.7 | **Live: with the Mac stopped, read, close, start the Mac, and the Mac's row catches up** | live probe, both directions: the report queued with no listener on 8788, then the flush wrote the row with **the queued report's own clock** |
| 2.8 | **The reader's opening position still follows CD5, and no report is sent on open** | `InitialFractionTests` (slice 1's five cases, unchanged) + the live runs above, where the reader opens at whichever of the two is further along and only the door reports |
| 2.9 | **Nothing new carries the token, and no `file://` appears** | the AC13 source walk, re-run on this slice's tree |
| 2.10 | **Gates.** `xcodebuild build` and `xcodebuild test` both exit 0 on this slice's own tree, with the count reported per file | the two commands |

**What slice 2 deliberately does not do.** No UI surface for the queue (it announces itself in the probe log; a "N reports waiting" row is a new decision, not a debt). No background `URLSession`, so a report taken while the app is being backgrounded usually reaches the Mac on the phone's *next* foreground rather than at that instant — the queue is what makes that safe rather than lossy, and the residual is named in *Built — slice 2*. No `Range` resume: CD6's own revival condition — one transfer large enough that restarting it hurts — has not fired, and this slice's library is a few hundred KB per book.

## Slices

| Slice | What lands | Files (honest) |
| ----- | ---------- | -------------- |
| **1 — down** (landed, `ed7abf6`) | project + app shell, settings/connect, API models + strict decoder + client, download store, library grid, book detail, reader at a fraction, vendored contract fixtures, live probe | ~22 code + 5 test + docs |
| **2 — up** (built, uncommitted) | the report on stop, its queue and D6's ordering; **not** resume-by-`Range` | 3 new app files + 5 edited, 3 test files, `scripts/live-probe.sh` + docs |

The slice-1 count is stated rather than discovered: the owner chose the bigger slice (config → health → list → detail → download → reader), and each of those is a screen with a model behind it. They are built in that order, each with its own decider, so the slice lands in coherent pieces rather than one unreviewable diff.

## Rejected and deferred, with the condition that would revive them

- **A local library cache (SQLite/SwiftData/JSON).** Rejected (CD3): a second source of truth for data that is one cheap request away. Revived when the library is slow enough to page through on every launch, or when browsing with the Mac asleep is wanted for its own sake.
- **Resumable downloads** (CD6) — deferred; the wire supports `Range` today, so this is client-only work. Revived by one transfer large enough to hurt.
- **Search and filters in the client.** The contract serves both (`q`, `sort`, facets). Deferred to its own slice because the list slice is already the whole downward path; revived the first time the owner reaches for search on the phone and it is not there.
- **The Mac's `musaeum://` cover semantics on the phone** — not applicable: the phone asks the REST route and decodes `image/jpeg`.
- **Reading PDF on the phone.** The library holds 1,798 books with a PDF and the wire serves them; Readium can render PDF through a separate navigator and a PDFium/`PDFDocument` factory, which is not wired here. Revived when an owner's book that is PDF-only is wanted on the phone.
- **A sync/refresh policy that pulls unread books in the background** — the parent spec already names this as the cheap later answer and not v1 (D14).

## Risks, stated plainly

1. **Readium's reading experience is unjudged.** It renders correctly (measured), and whether it is *good* — typography, page turns, margins, the dark palette on a real page — is a judgement the owner makes by looking at the phone. Nothing in this repo's test suite will say.
2. **One big slice.** The owner chose config → list → detail → download → reader in one go; the mitigation is that each piece lands with its own decider and the report names which piece carried which criterion.
3. **The Mac must be running to *fetch*, and the app says so rather than pretending** (D14, CD3). The first-run experience on a phone with the Mac asleep is "nothing here yet" — which is honest and undeniably worse than a library that is always there.
4. **A token typed by hand on a phone keyboard.** The Mac's Settings row shows the URL and the token to type; a typo surfaces as a 401 from the connect screen. (A QR hand-off is not built and not needed yet.)
5. **Tailnet-only, cleartext, and `http`.** The credential travels inside WireGuard; the app must not be pointed at a non-tailnet address by accident, and the client has no TLS story of its own.
6. **Invariants inherited, none bent:** the Mac repo's invariants are untouched by this app (it is a separate repository and speaks only HTTP). The contract's own rules that this client must not break — extension-based file resolution (asks by id + format), the fraction as the travelling coordinate, `formats[0]` as the preference order the *server* computed — are honoured by construction in CD4/CD5/CD6.

## Start here

```bash
# contract (the frozen input)
sed -n '1,60p' ~/Projects/musaeum/docs/rest-api.md
# the Mac side, if the server must be brought up:
#   ~/Projects/musaeum/.claude/skills/verify/SKILL.md  (isolated profile, MUSAEUM_USER_DATA)

xcodegen generate                     # project.yml → Musaeum.xcodeproj
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro, iOS 26.1 — an id, never a name (deviation 1)
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test
scripts/vendor-contract-fixtures.sh    # re-derive the contract fixtures from the doc
```

Then, in order: `Musaeum/Core/API/ContractModels.swift`, `Musaeum/Core/API/MusaeumClient.swift`, `Musaeum/Core/Store/DownloadStore.swift`, `Musaeum/Features/Reader/ReaderScreen.swift`.

---

## Built — slice 1 (2026-09-22)

Sixteen app files and seven test files; `xcodebuild build` and `xcodebuild test` both exit 0, with **43 unit cases across 6 suites, 0 failures** (the seventh test file is the `URLProtocol` stub the others use). The contract's own executable half was re-run against the same server this client used (`../musaeum/scripts/api-smoke.sh`: **56 passed, 0 failed**), because a client that agrees with a stub and not with the server is the expensive failure.

### The live probe (the app's own instrument)

Three runs against a real Musaeum on an isolated profile (8 EPUBs, 7 of them with covers) at `http://100.125.135.108:8788`, iPhone 17 Pro / iOS 26.1. `scripts/live-probe.sh` is the command that re-runs them; its header carries the whole server recipe, including the two traps this session paid for.

| # | Run              | What the app logged                                                                                                                                                                                | What the frame shows                      |
| - | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| 1 | library          | `library page count=8 total=8 limit=100 offline=online`                                                                                                                                            | 8 books, real covers, amber-on-near-black |
| 2 | download + read  | `probe downloaded … format=epub serverPercent=0.42` → `reader opened … requested=0.42 local=0.4198265179677819 server=0.42` → `reader landed=0.4198265179677819 atHref=OEBPS/Malh_9780553904949_epub_c06_r1.htm` | the page renders, **42%** under the title |
| 3 | the Mac asleep   | `library failed the Mac is not answering` → `probe: the Mac did not answer … falling back to the phone's own copy` → `probe offline id=…` → `reader opened … requested=0.4198265179677819 local=0.4198265179677819 server=0.1` | the same page, the same 42%, no server   |

Runs 2 and 3 decide CD5 in both directions with live numbers: a Mac further along (`0.42` > `0.4198265…`) is what the reader opens at, and a phone further along (`0.4198265…` > the stale `0.1`) is what it opens at — and run 3 does it with `lsof` showing no listener on 8788 at all.

**Criterion 8's decider, stated where it is thin.** The criterion asks for "no network request" while reading a downloaded book. The unit suite decides the local half (the store's index, the file's presence, the payload decoding from the index), and run 3 is the live half: with the server stopped the request it would make cannot succeed and the page renders anyway. What no case does is *count zero calls inside the reader* — because the reader is handed a file URL and has no client to call, which is CD3's design. That is why the live run, not a stub, is the honest instrument here.

### Deviations and corrections this build made

1. **The spec's own build command does not resolve on this machine.** `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` fails with *Unable to find a device matching the provided destination specifier*, and Xcode 27 then lists every device it knows, iOS 17.5 included. The working form is `-destination "id=DE0B5601-7874-455E-A965-9AD80567C30E"`, which is what every run above used. A device *name* is only unambiguous when one runtime carries it.
2. **`NavigatorDelegate.presentError` has no default implementation.** Readium's other delegate members are defaulted in extensions, which makes it easy to assume this one is too; its absence surfaces as `type 'PositionRecorder' does not conform to protocol 'NavigatorDelegate'` — a compile error, which is the good failure.
3. **`EPUBPreferences(theme: .dark)` is the only preference that worked.** Readium's `Color(hex:)` is not usable for `backgroundColor`/`textColor` in that initializer, so the reader inherits Readium's own dark theme rather than the app's tokens. CD1's consequence said the page would be Readium's; this is what that costs in code.
4. **The page's near-black is Readium's, not `Palette.ink`.** A reader that matches the app exactly is an `EPUBPreferences`/CSS pass this slice did not include.
5. **Four contract types needed `Hashable`.** `navigationDestination(item:)` requires it; `ContractBook`, `CoverInfo`, `Reading` and `ReadingStatus` carry it by synthesis.
6. **A three-deep `map(String.init) ?? "nil"` inside one log expression breaks the Swift type checker.** It reports as `failed to produce diagnostic for expression` *and* as a bogus conformance error in a neighbouring type — the tell is a "conformance" failure naming a type that implements everything. `ReaderHost.text(_:)` is the fix, and the reason it exists is written on it.
7. **A unit-test bundle needs `GENERATE_INFOPLIST_FILE: YES`** (`project.yml`), or the generated project refuses to code-sign it.
8. **A missing cover in the grid is faithful, not a defect.** The one placeholder tile in run 1's frame ("In Defense of Selfishness") has no cover on the Mac either — its row's `cover_thumb_path` is null and its folder holds no `cover_thumb.jpg`. Criterion 11's "covers painted" is therefore 7 of 8, and the eighth is verified at the source rather than assumed.
9. **`rest_api_token` must exist before the server will listen.** A seeded profile has to insert one (`openssl rand -hex 32`); from the app, enabling the API is what generates it. The first probe attempt failed on exactly this: `[rest] not listening — rest_api_enabled is on but rest_api_token is empty`.
10. **The dev Electron bundle is `Musaeum.app`, not `Electron.app`** (`node_modules/electron/dist/Musaeum.app/Contents/MacOS/Electron`). A probe that stops the Mac must kill *that*; a pattern naming `Electron.app` kills nothing, and the "offline" run then takes its reading against a live server — which is what the first attempt at run 3 did.
11. **A criterion added late, by name.** Criterion 11's paging half has no live decider at this corpus size (8 books, page size 100), so `Tests/MusaeumTests/LibraryPagingTests.swift` decides it over a stubbed two-page server, including the guard that a row which is *not* the last one asks for nothing.
12. **XcodeGen globs a `sources:` directory when it *generates*, not when it builds.** `LibraryPagingTests.swift` was written, the suite was re-run, and the total stayed at 41 with the new file never collected — the gate looked green while the criterion had no decider at all. `xcodegen generate` before the gate is what makes a new file exist. This is the "a decider has to run *and* discriminate" trap arriving through the project generator rather than the test file.
13. **A `@MainActor` `XCTestCase` whose stub closure touches the handler will crash the test host, not fail a case.** The class's isolation is inherited by a closure written inside it, and `StubURLProtocol` calls that handler from a background thread — where the inherited isolation is an assertion that fails as `dispatch_assert_queue_fail` and `SIGTRAP` (`~/Library/Logs/DiagnosticReports/Musaeum-2026-09-22-222455.ips`). The symptom is the app *quitting* — which is how the owner reported it (*"the app quit multiple times"*) before the crash report was read; two reports, both the test host, both this file. **The gate for that run was red, not silent**, and the distinction matters: `xcodebuild` printed `** TEST FAILED **`, exited **65** and logged *Restarting after unexpected exit, crash, or test timeout* — the crashed launch reported `LibraryPagingTests` as **`Executed 0 tests`** (its first case, `testTheLastRowFetchesThePageAfterIt()`, printed immediately before the failure) while the other five suites re-ran and passed. So a crash inside a case fails the gate, but only the crash report names its cause — while the run *before* it (41 cases, exit 0) is the one that was silently undecided, because its new file was not in the project yet. The fix is `nonisolated` on the helper that defines the closure, and it is written on those helpers so the next person does not re-derive it. **The probe profile's dev app was started and stopped three times, all by this session on purpose** (once to seed `rest_api_token` and twice around the probe runs — the last of them the SIGTERM that makes run 3 an offline reading, recorded by the shell as `exit 143`); no crash report exists for any of them, and no process of the owner's own profile was involved at any point. The only crash reports on this machine for today are the two from the test host above.

14. **Four compile errors from this tree's first full build, worth knowing before the next `SWIFT_STRICT_CONCURRENCY: complete` pass.** (a) A `private` decoding helper in `ContractModels.swift` was invisible to a `private extension` of the same type declared at the bottom of the file — the *same-type* extension is a different scope for access control, so the helper is internal and the extension is gone. (b) `ISO8601DateFormatter` held in `static let` is rejected under complete concurrency, and the fix that keeps one allocation is `nonisolated(unsafe)`, not a fresh formatter per call. (c) `let error = try Self.mapStatus(…)` does not compile when the callee returns `Void`: the assignment types the binding as `()`. The compiler's *first* error in that family reads as `inaccessible`/`conforms` and hides the next two, so expect to fix, rebuild, and find one more. (d) Inside a `URLProtocol` subclass's `startLoading`, the captured `request` is `self.request` — Swift 6 demands the explicit `self.` in the closure and the error names the property rather than the closure, which reads as unrelated to the line it is on (`StubURLProtocol.swift:67`).

### Defects the owner found by looking, and what fixed them (2026-09-22)

Both come from one session the owner spent running the app **from Xcode** — the path every probe in this slice had skipped.

1. **The app showed a blank white screen on launch.** Cause: the window and the launch screen were never declared dark. The app's look is dark and it forces it in SwiftUI (`.preferredColorScheme(.dark)`), but that applies when SwiftUI *paints* — so a cold launch drew a **white** launch screen with the Connect screen laid out white-on-white on top of it, then flipped to dark. A debugger-attached launch (Xcode's default) leaves that on screen long enough to read as a hung app, which is how it was reported. **Fix:** `UIUserInterfaceStyle: Dark` in `project.yml`'s `info.properties`, so the window and the launch screen are dark from the first frame.
   **Why three green probes missed it:** every run launched with `MUSAEUM_PROBE_BASE`/`TOKEN` — so the app was always already configured and went straight to the library — **and each sampled after a 20–35 s wait**, while the white exists only in the first frames. The instrument that decided it is a **cold-launch frame sampled with no sleep** (`xcrun simctl launch` then `simctl io … screenshot`): before and after, `docs/evidence/slice1/launch-before-fix-white.png` and `launch-after-fix-dark.png`. Verification that it is really fixed: the first frame after `simctl launch` is black, and the settled frame is the Connect screen.
2. **The Mac's tailnet address was baked in as the connect form's placeholder** (`ConnectScreen.swift:28`, `prompt: "100.125.135.108:8788"`) — a personal address in the UI, and a misleading one, since it displays as though the app already knew it. Now `host:8788`: the shape, not the owner's address. Found in the same screenshot that reproduced the white screen.
3. **A consequence, recorded rather than fixed:** with the style forced dark, the system controls on that screen (the token toggle, the fields) render in their dark variants — what `connect-screen.png` shows, and what the app meant all along.

### Handed to the owner's own judgement

- **Typography — looked at, accepted, closed (2026-09-22).** The owner reviewed the frames and judged Readium's page fine for v1, so **CD1's revival condition for foliate-js is not fired** and foliate-js stays rejected on its own stated ground (cost). The observation that prompted the look: Readium's justified body text shows wide inter-word gaps on long lines. Nothing follows from it — a future typography pass is a new decision, not a debt this slice left, and the next session should not re-raise it as open work.
- **Every frame in this slice is the reader's first page.** Page turns, the palette on a real page, and the reading experience over a longer sitting were not exercised (no tap-driving instrument in this slice).
- **The Mac's app was stopped for run 3**, and the probe profile's Mac-side app was not restarted afterwards. Nothing on the owner's own profile or library was touched: the probe ran entirely inside `~/.hermes/profiles/dev/cache/scratch/ios-probe`.

---

## Built — slice 2 (2026-09-23)

The upward path. Three new app files (`Core/API/ReadingReport.swift`, `Core/Store/ReportQueue.swift`, `Core/Store/ReadingReporter.swift`), five edited (`Core/API/MusaeumClient.swift` — a `body:` on request composition, the `PUT` route and its hand-written body; `Core/Reader/ReaderHost.swift` — `settledFraction`; `Features/Reader/ReaderScreen.swift` — the two doors and the write probe; `App/MusaeumApp.swift` — the reporter in the environment and the two flush triggers; `Core/Support/Probe.swift` — the `write` action named), three test files, plus `scripts/live-probe.sh` and the docs.

**No design decision was re-opened.** CD1–CD8 are closed and this build changed none of them; the two readings it had to settle for itself are below.

### Gates

| Instrument | Result |
| ---------- | ------ |
| `xcodebuild build` | **exit 0**, no warnings in this repo's own files (Readium's packages excluded) |
| `xcodebuild test` | **exit 0 — 61 cases, 0 failures, across 9 suites** |
| `../musaeum/scripts/api-smoke.sh` | **passed 56, failed 0** against the same server |
| AC13's source walk | re-run: no `file://`, no `URL(string: "file:`, and no `Probe.log`/`print` line mentions the token or the header |
| **Mutation campaign** (8 mutations, one per criterion that has a unit decider) | **8/8 killed**, every file restored and sha256-verified — `docs/evidence/slice2/mutation-campaign.log` |

Per file, because a total is not a decider — and slice 1's own 43 are inside the first five rows, unchanged:

| Suite (file) | Cases |
| ------------ | ----- |
| `ClientTests` | 14 |
| `ContractDecodeTests` | 11 |
| `CoverPipelineTests` | 3 |
| `InitialFractionTests` | 7 |
| `LibraryPagingTests` | 2 |
| `ReadingReporterTests` **(new)** | 8 |
| `ReadingWriteTests` **(new)** | 6 |
| `ReportQueueTests` **(new)** | 4 |
| `StoreTests` | 6 |

**The campaign is what makes those 18 new cases a result rather than a green light.** Slice 1's record had no such row, and its criteria were argued from their assertions — a suite proves the cases *ran*, never that they *decide*. So each criterion here was mutated one at a time and its focused suite required to redden, with the baseline run green first so a red row means an assertion failed rather than a suite that does not exist:

| Mutated | Decider | Failure count |
| ------- | ------- | ------------- |
| the write is a `POST` | `ReadingWriteTests` | 1 |
| the body **always** carries the clock (a live report's `at` is no longer absent) | `ReadingWriteTests` | 1 |
| a report is not kept when the Mac cannot take it (attempt-then-forget) | `ReadingReporterTests` | 12 |
| the flush walks newest-first | `ReadingReporterTests` | 4 |
| a 404 is retried rather than dropped | `ReadingReporterTests` | 2 |
| a flush against a sleeping Mac walks the whole queue instead of stopping | `ReadingReporterTests` | 1 |
| the queue is in memory only (the index is never written) | `ReportQueueTests` | 4 |
| a live report carries its own clock (the reporter's half of D6) | `ReadingReporterTests` | 1 |

**What the campaign proved these deciders cannot see**, said plainly rather than left to be discovered: criteria **2.6 and 2.7 are live-only** — no unit case can decide that the Mac's *own row* moved, so they are decided by the probe runs above and nothing else. And the two clock mutations are a **pair**: the rule "`at` travels only on a flush" has one half in the body (`MusaeumClient.readingBody`) and one in the reporter (`attempt`'s `includingClock`), and a campaign that listed either alone would have reported the case load-bearing while the other half was free to delete.

*One row's failure count is worth reading rather than counting.* The attempt-then-forget mutation reddens **12 assertions across 8 cases** — that is not 12 deciders, it is one symptom (nothing stays queued) reaching every case that inspects the queue afterwards. Read as a set, it is collateral; read as a number, it is noise.

### The live probe

Three runs against a real Musaeum on slice 1's isolated profile (8 EPUBs at `http://100.125.135.108:8788`, iPhone 17 Pro / iOS 26.1), all on book `ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d` (*Negotiation Genius*). The decider is the **Mac's own row**, read out of the probe profile's SQLite either side; the frames are committed under `docs/evidence/slice2/`, whose README carries the full log lines.

| # | Run | The Mac's row, before → after | What the app logged |
| - | --- | ----------------------------- | ------------------- |
| 1 | write, Mac up, **the Mac further along** | `0.42` → **`0.4198265179677819`**, position `null` | `reader opened … requested=0.42 local=0.09777541747801971 server=0.42` → `reader landed=0.4198265179677819` → `report accepted` → `probe write the Mac now holds percent=0.4198265179677819` |
| 2 | write, Mac up, **the phone further along** | `0.05` + a stale CFI, `updated_at 2026-09-22T00:00:00.000Z` → **`0.419826517967782`**, position **blanked** (the stale CFI gone) | `reader opened … requested=0.4198265179677819 local=0.4198265179677819 server=0.05` → `report accepted` → `probe write pending=0` |
| 3 | write with **no listener on 8788**, then start the Mac, then flush | `0.05` + a stale CFI, **unchanged while it was asleep** → **`0.419826517967782`**, position **blanked**, `updated_at 2026-09-23T13:50:37.387Z` | run A: `library failed the Mac is not answering` → `report queued` → `probe write pending=1`. Run B: `report queue drained`; `reports.json` `[…] → []` |

Run 1 is what a report that merely echoed the request back could **not** produce: the Mac sent `0.42` and got `0.4198265179677819` — the phone's engine's number, the same figure the pre-build Readium harness measured for that request. Run 2 is the same fact in the direction that matters for a real reader: the Mac's stale `0.05` and its stale CFI were both replaced by the phone's `0.42`, and the CFI's disappearance is the Mac's D5 blanking reached through the phone's report. Run 3's `updated_at` is **the queued report's own `readAt`** (`13:50:37.387Z`), not the flush's clock, and `metadata.json` beside the book (`{"position": null, "percent": 0.4198265179677819, "updated_at": "2026-09-23T13:50:37.387Z"}`) agrees — D6's client half, measured rather than argued.

### The two readings this slice settled for itself

**1. The clock travels only on a *flush*.** The annex's row said the report carries "`percent` plus the phone's clock". The contract is sharper — *"send it for a report that was queued… omit it for a live read, when the server's clock is the truth"* — and the difference is not pedantry: the Mac's D6 refuses a report older than its row, so a phone whose clock runs a few seconds behind would have **its own live report refused as stale** by its own timestamp. So the queue always stores when the reading happened, and the **live attempt** is the one that omits `at` from the body. Decided by `ReadingWriteTests.testALiveReportOmitsTheClockAndAQueuedOneCarriesIt` (the body's key set is `["percent"]`, not `["percent","at"]`) and `ReadingReporterTests.testALiveReportReachesTheMacWithoutItsClock` (asserted on the bytes the request actually carried), with the flushing half in `testAQueueOfThreeFlushesOldestFirstCarryingEachReportsOwnClock`.

**2. A report is queued *before* the Mac is asked.** `ReadingReporter.report` writes the queue, then attempts, then removes on acceptance — rather than the obvious attempt-then-queue. Why: the door that matters most is the app *leaving the foreground*, where being suspended mid-request is the expected outcome rather than the unlucky one, and queue-first makes "queued, not lost" true by construction instead of by timing. The cost is stated rather than hidden: a report that succeeds leaves a transient on-disk write behind it, and the queue is read at most twice per reading.

Both are wiring, not product: the annex's own table is the ground, and neither touches CD1–CD8.

### Corrections and traps this build paid for

1. **`scripts/live-probe.sh` was committed `100644` — not executable.** The command `AGENTS.md` and the slice-1 record both tell the next session to run (`TAG=library ./scripts/live-probe.sh`) answered `Permission denied`. Fixed with `chmod +x`; the mode change rides in the commit.
2. **The probe script never passed a base URL, and the app stores none on the simulator** (`Library/Preferences/dev.jasonoh.Musaeum.plist` does not exist in the container). Slice 1's runs must therefore have set it by hand — so the "re-runnable" script would in fact come up **unconfigured**, log nothing, and read as *"the probe found nothing"*: a silently undecided run, which is the same class as slice 1's trap 12. It now reads `$ROOT/base.txt` (or `BASE=…`) and **refuses to run without it**, exactly as it already refused without `token.txt`.
3. **The Mac writes reading state *after* its listener closes.** Stopping the dev app by its listener pid frees `8788` first and runs the quit handshake — which flushes in-memory reading state into SQLite *and* `metadata.json` — a second or two later; and the next startup rebuilds the row from the derived store. An edit to the probe profile's row inside that window is silently overwritten, and the old value comes back. This cost three attempts at 2.6/2.7 before the shape of the race was read off the two stores side by side (`metadata.json` said `0.05`, SQLite said `0.4198` — the write that flipped it was the *startup* adoption). The edit that decides anything is the one made either once `pgrep -f 'electron/dist/Musaeum.app'` is **empty** (not merely `lsof` clean), or **after startup and immediately before the run**.
4. **A row equal to the phone's position makes a run look green and decide nothing.** The first attempt at 2.6 reported `0.1` against a Mac holding `0.1`; the write was accepted, `updated_at` moved, and **no position moved**. Every decisive run therefore sets the profile's row to a *different* number first — and a stale CFI alongside it, so the D5 blanking has something to remove. This is written into `docs/evidence/slice2/README.md` because it is the difference between evidence and a green light.
5. **`ReadingReporterTests` is `@MainActor` and therefore had slice 1's trap-2 crash in front of it.** Its stub-closure helpers are all `nonisolated`, with the reason written on the class — a `@MainActor` case whose closure runs off-main asserts the queue and sends `SIGTRAP`, which reads as "the app quit" rather than a failed case.
6. **The body of a `PUT` is not where a `URLProtocol` finds it.** `URLSession` turns a request with `httpBody` into an upload task and the stub then sees the bytes on `httpBodyStream`. A case that asserted `request.httpBody` would have passed by asserting `nil`. `ReadingReporterTests.body(of:)` reads the property and falls back to draining the stream.
7. **The write reaches `metadata.json` as well as SQLite** — `reading_state: {position, percent, updated_at}` beside the book is what the flush wrote, position `null` included. Worth knowing because it means the probe profile has *two* stores that can disagree, and only one of them is what the route reads.

### Handed to the owner's own judgement, and the residuals

- **The background door is a claim for a human frame.** `simctl` cannot background an app, so run 3 exercised the *close* door and the queue; what is **not** measured is whether a report taken while the app is being backgrounded reaches the Mac before the app is suspended. It usually will not — this slice takes no `beginBackgroundTask` assertion and uses no background `URLSession` — so the report waits in the queue and lands on the phone's next foreground. That is safe rather than lossy (the queue write happens before the attempt), and it is the honest cost of the two doors. **What would change it:** a background `URLSession` with its own delegate, or a grace window around the send — both real decisions, neither taken here. To see the behaviour: read a few pages with the Mac awake, lock the phone, and watch the Mac's row before reopening the app.
- **The queue has no surface in the UI.** It announces itself in the probe log (`report queued` / `report queue drained`) and nowhere else. A "N reports waiting" row is a new decision, not a debt this slice left.
- **A queued report is not bounded by age.** A phone that has not seen its Mac for a month flushes a month of readings, oldest first, one request each. The outcome is right — the Mac's D6 refuses every one older than its row, so the row keeps the newest position — but it is a burst of writes, and it is named here rather than defended.
- **`Range` resume is still not built** and CD6's own revival condition has not fired: the probe profile's books are ~660 KB.
- **The probe profile's final state**, so the next session reproduces from here: the Mac's row for `ef91875e-…` is `reading` at `0.419826517967782` with `reading_position` null; the phone holds the EPUB (660,053 bytes), its cover, its own `positions.json` at `0.4198265179677819`, and an **empty** `reports.json`.
- **The Mac's app was started and stopped four times, all by this session on purpose**, entirely on the probe profile at `~/.hermes/profiles/dev/cache/scratch/ios-probe`. No process of the owner's own profile or library was involved at any point.

