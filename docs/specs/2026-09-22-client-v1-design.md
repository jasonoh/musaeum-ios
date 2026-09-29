# Musaeum iOS — a reading client for the Mac's library (v1)

**Date:** 2026-09-22
**Status:** **slices 1–5 are built, gated and probed.** **Slice 5 — sharing a downloaded book out (AirDrop, Mail, Messages) — landed 2026-09-24**: `xcodebuild build` exit 0, `xcodebuild test` exit 0 — **136 cases, 0 failures, 16 suites** (19 of them this slice's), `../musaeum/scripts/api-smoke.sh` **70 passed, 0 failed** against the probe profile (unchanged, which is what a slice that moves no route should read), a **21-mutation campaign — 21/21 killed, with all 19 of the new suite's cases reddened by at least one row** — and four live-probe runs in `docs/evidence/slice5/`: a share staged with the Mac up and **the same share staged with nothing listening on the port**, a frame of the detail holding the new door, and the launch sweep clearing what a killed run had left. **No capability, no entitlement, no second target** — the tree still holds no `.entitlements` file, which is the whole difference between this arrow and slice 4b's. Its one human frame, the sheet itself with AirDrop/Mail/Messages on it, is still the owner's to take. **Slice 4 — sending a book to the Mac — landed 2026-09-24**: `xcodebuild test` exit 0, **117 cases, 0 failures, 15 suites** (22 of them this slice's; five more are the cover-box fix `d98f3a9` carried), `../musaeum/scripts/api-smoke.sh` **70 passed, 0 failed** against the probe profile, a **15-mutation campaign — 13/15 killed, with both survivors the same mutation and named as a finding** — nine live-probe frames and the library the runs wrote to in `docs/evidence/slice4/`, and — the reading no probe can make — **the owner's own upload has crossed a real wire** (*The Art of Spending Money*, 1,081,907 bytes, uploaded from his iPhone, in the library on both machines). Its two human frames, the picker opening and a share sheet offering Musaeum, are still his to take. Slices 3a and 3b are built, gated and probed (2026-09-23) — not yet committed; the owner commits this repo himself. *Stage 3a of slice 3 — the phone's own order and its search* — is in the tree: build exit 0, **75 cases across 11 suites, 0 failures**, nine mutations all killed, five live probe runs, its frames at `docs/evidence/slice3/`, and its numbers in *Built — slice 3a* at the end of this document. Stage 3b (the filter chips) is **built** against the same annex — so slice 3 is complete, and with it the deferred item that revived it. Slice 1 landed as `ed7abf6` (*initial ios app*, 44 files, 4,803 insertions) and its numbers are in *Built — slice 1* at the end of this document, together with the corrections that build made to its own commands; the probe's frames are committed at `docs/evidence/slice1/`. Slice 2 (the upward path) is complete against its annex `docs/plans/2026-09-22-slice2-upward.md`: **build exit 0, 61 cases across 9 suites, 0 failures**, and three live probe runs against a real Musaeum — the numbers are in *Built — slice 2* below and its frames at `docs/evidence/slice2/`. That closed CD8's own scope — v1 was drawn as two slices and there was no slice 3 at the time. What came next was the deferred list's, each item revived only by its own stated condition, **and one has since fired**: *Search and filters in the client*, revived the first time the owner reached for search on the phone and it was not there, is **slice 3** — whose stages 3a and 3b are the status above. The three forks slice 1 rests on were settled by the owner on 2026-09-22 (CD1, CD2 and the slice boundary) — Readium for v1, iOS 18, and slice 1 is the whole *downward* path.
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
- **Search and filters in the client.** **Revived 2026-09-23 — its own condition fired and it is now slice 3** (`docs/plans/2026-09-23-slice3-search-sort-and-filters.md`: stage 3a sort + search, stage 3b filters). The contract serves both (`q`, `sort`, facets). Deferred to its own slice because the list slice is already the whole downward path; revived the first time the owner reaches for search on the phone and it is not there.
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
8. **The Connect screen pointed at a settings row that does not exist** (found 2026-09-23, while writing the run-on-your-phone recipe). Its footnote read *"Both are on the Mac, in Musaeum → Settings → Remote access"* — and `Remote access` appears **nowhere** in the Mac's UI: the section is titled **"Phone access"** (`src/components/settings/SettingsModal.tsx:571`) and the row inside it is headed *"Serve the library to your phone"* (`RestApiSection.tsx:111`). Slice 1's own copy, wrong from the day it was written, and undecidable by any test — the suite can see a string, never whether it names something real on the other machine. Fixed to name the real row and to say what generates the token, because *"turning its switch on"* is the step a first-time reader actually needs.

### Handed to the owner's own judgement, and the residuals

- **The background door is a claim for a human frame.** `simctl` cannot background an app, so run 3 exercised the *close* door and the queue; what is **not** measured is whether a report taken while the app is being backgrounded reaches the Mac before the app is suspended. It usually will not — this slice takes no `beginBackgroundTask` assertion and uses no background `URLSession` — so the report waits in the queue and lands on the phone's next foreground. That is safe rather than lossy (the queue write happens before the attempt), and it is the honest cost of the two doors. **What would change it:** a background `URLSession` with its own delegate, or a grace window around the send — both real decisions, neither taken here. To see the behaviour: read a few pages with the Mac awake, lock the phone, and watch the Mac's row before reopening the app.
- **The queue has no surface in the UI.** It announces itself in the probe log (`report queued` / `report queue drained`) and nowhere else. A "N reports waiting" row is a new decision, not a debt this slice left.
- **A queued report is not bounded by age.** A phone that has not seen its Mac for a month flushes a month of readings, oldest first, one request each. The outcome is right — the Mac's D6 refuses every one older than its row, so the row keeps the newest position — but it is a burst of writes, and it is named here rather than defended.
- **`Range` resume is still not built** and CD6's own revival condition has not fired: the probe profile's books are ~660 KB.
- **The probe profile's final state**, so the next session reproduces from here: the Mac's row for `ef91875e-…` is `reading` at `0.419826517967782` with `reading_position` null; the phone holds the EPUB (660,053 bytes), its cover, its own `positions.json` at `0.4198265179677819`, and an **empty** `reports.json`.
- **The Mac's app was started and stopped four times, all by this session on purpose**, entirely on the probe profile at `~/.hermes/profiles/dev/cache/scratch/ios-probe`. No process of the owner's own profile or library was involved at any point.

---

## Built — slice 3a (2026-09-23)

The library's own order, and its search. **Stage 3a of Slice 3**; stage 3b (the filter chips) was still to come when this record was written and its files are named in the annex — **it has since landed: see *Built — slice 3b* below.**

Three new app-side files — `Core/API/LibraryQuery.swift` (the sort, the query and the empty-state rules, as pure values so each has a decider that needs no screen), `Tests/MusaeumTests/LibrarySortTests.swift`, `Tests/MusaeumTests/LibraryQueryTests.swift` — and three edited: `Features/Library/LibraryScreen.swift` (the model's `query`/`sort` and a **generation counter**, every request composed from them, the sort menu, the search field, the two empty cards), `Core/Store/SettingsStore.swift` (the remembered sort, one key beside the base URL), `Core/Support/Probe.swift` (`MUSAEUM_PROBE_SORT` / `MUSAEUM_PROBE_QUERY`). Plus `Musaeum.xcodeproj/project.pbxproj` (regenerated), `scripts/live-probe.sh`, the annex, and four documents.

**No design decision was re-opened** — CD1–CD8 are closed and this build changed none of them. **And no contract change, no Mac-repo slice:** `GET /api/library` already accepted `sort`, `dir` and `q`, and `MusaeumClient.library(limit:offset:sort:direction:query:)` already composed all three. What was missing was entirely the phone's own state, which called `client.library(limit:offset:)` and dropped them.

### Gates

| Instrument | Result |
| ---------- | ------ |
| `xcodegen generate`, then `xcodebuild build` | **exit 0.** One warning in the whole log and it is Apple's `appintentsmetadataprocessor` (*no AppIntents.framework dependency found*), not a file of ours |
| `xcodebuild test` | **exit 0 — 75 cases, 0 failures, across 11 suites** |
| `../musaeum/scripts/api-smoke.sh` | **passed 56, failed 0** against the same server |
| AC13's source walk, re-run on this tree | clean: no `file://` in `Musaeum/` or `Tests/`, nothing logs a token, and the token's whole life is `Probe` → Keychain (`musaeum.token`) → the one `Authorization` header |
| **Mutation campaign** (9 mutations, one per criterion that has a unit decider) | **9/9 killed**, every file restored and sha256-verified — `docs/evidence/slice3/slice3a-campaign.log` |

Per file, because a total is not a decider. Slice 1's and slice 2's 61 cases are unchanged and sit inside this table:

| Suite (file) | Cases | |
| ------------ | ----- | - |
| `ClientTests` | 14 | |
| `ContractDecodeTests` | 11 | |
| `CoverPipelineTests` | 3 | |
| `InitialFractionTests` | 7 | |
| `LibraryPagingTests` | 2 | |
| `LibraryQueryTests` **(new)** | 6 | the model over a stub: what each request carries, the race, the two empty screens, the persistence funnel |
| `LibrarySortTests` **(new)** | 8 | the pure rules: the eight options, the labels, the wire pairs, the stored guard, the trim rule |
| `ReadingReporterTests` | 8 | |
| `ReadingWriteTests` | 6 | |
| `ReportQueueTests` | 4 | |
| `StoreTests` | 6 | |

### The campaign

Each criterion with a unit decider was mutated one at a time and its focused suite required to redden, with the named suites run green first so a red row means an assertion failed rather than a suite that does not exist.

| Mutated | Decider | Failures |
| ------- | ------- | -------- |
| page two of a search loses the narrowing (`loadNextPageIfNeeded` composes its own request) | `LibraryQueryTests` | 3 |
| a superseded search lands (the generation guard, success path) | `LibraryQueryTests` | 1 |
| a whitespace-only term travels as a search | `LibrarySortTests` | 6 |
| an empty library and a term that matched nothing are the same screen | `LibraryQueryTests` | 1 |
| the stored sort is written but never read | `LibrarySortTests` | 2 |
| an unknown stored sort falls back to something other than the default | `LibrarySortTests` | 6 |
| the sort and its direction never reach the wire | `LibraryQueryTests` | 5 |
| choosing a sort remembers the default instead | `LibraryQueryTests` | 1 |
| a search that changes nothing still asks the Mac | `LibraryQueryTests` | 1 |

**The counts reconcile with their mutants, which is the point of printing them.** The page-2 row reddens exactly 3 assertions, and 3 is exactly what page 2 loses — `sort`, `dir` and `q`, and nothing else. The generation-guard row reddens **1**, which is the race itself rather than a broad failure. The two 6s are the guard and the trim rule, each of which several cases touch on purpose. A row whose count could not be derived from its mutation would be a row I would not believe.

### The live probe

Five runs against a real Musaeum on slice 1's isolated profile (8 EPUBs, iPhone 17 Pro / iOS 26.1), committed under `docs/evidence/slice3/`. **The port is 8789, not slice 1's 8788**: the owner's own packaged Musaeum was running and holding 8788 for the whole of this work, so the probe profile was moved rather than colliding with it. It was never touched and never signalled — it answered `401` to this profile's token, which is how the two servers were told apart.

| # | Run | What the app logged |
| - | --- | ------------------- |
| 1 | `TAG=library SORT=title:asc` | `library page count=8 total=8 limit=100 offline=online sort=title:asc q=- first=Caliban's war \| Dragon Wing \| The Hidden Palace` |
| 2 | `TAG=sort SORT=author:desc` | `sort=author:desc q=- first=The Self-Driven Child \| Dragon Wing \| The Hidden Palace` |
| 3 | `TAG=kept`, **no `SORT` at all** | one line, `sort=author:desc q=- first=The Self-Driven Child \| …` |
| 4 | `TAG=search QUERY=negotiation` | `count=1 total=1 … sort=author:desc q=negotiation first=Negotiation Genius` |
| 5 | `TAG=nomatch QUERY=zzzz` | `count=0 total=0 … q=zzzz first=` then `library empty kind=noMatches("zzzz") macBooks=8` |

Run 3 is the persistence and the only run that can decide it: it named **nothing**, and the phone came up on the order run 2 had left. Run 4's total is the **server's** 1 rather than the library's 8, which is what separates a search from a reordering of the page in hand. Run 5's `macBooks=8` is what makes it *no matches* rather than *empty library* — the two screens differ by a fact the app already holds.

**And the question the slice started from, answered by measurement rather than by reading code: `q` is not title-only.** It searches title, author, tags — the `series:` tags included — *and* description. On this same 8-book profile: a word chosen to appear only in one book's description (`dragonlance`, from *Dragon Wing*) finds that book; `Kotler` (an author) finds one; `interplanetary` and `expanse` (tags) each find one; a word in nothing finds none. So descriptions are not something this slice builds — they are part of the path the phone was pointed at, which is why the phone and the Mac agree on what a search finds.

### The readings this slice settled for itself

**1. A frame is not the decider for an order; the app's own log line is.** The first version of these runs reported the order only in the frame, and one run's frame disagreed with its own log — a *mid-flight* read 25 s after launch, showing the previous order while the log already recorded the new one. Nothing about the frame said so, and by looking alone it was indistinguishable from a real defect. So the log line now carries `first=` (the first three titles of the array the screen renders), and the frame is corroboration. This is the slice-1 lesson in a new costume: an instrument that cannot fail loudly will be believed when it is wrong.

**2. The sort control's label has to be a `HStack`, and two cheaper spellings were measured and rejected.** A `Label` in a toolbar renders icon-only; so does the same `Label` with `.labelStyle(.titleAndIcon)`. Each build shipped a bare ⇅ glyph and each time it was a *committed frame* that caught it. It is a defect rather than a nitpick because the sort is remembered: with no label, the app can open reordered and the reader has no on-screen cause for it — which is exactly the dissonance that made the fork go the way it did. The label is the other half of "remember the sort".

### Corrections and traps this build paid for

1. **The annex named a file that does not exist.** Its file list said `Musaeum/Core/API/LibrarySort.swift`; the file landed as **`LibraryQuery.swift`**, because it carries the query and the empty-state rules as well as the sort, and naming it for one of its three parts would have been a name that fights its contents. The annex and its *Start here* block are corrected in place rather than left for the next session to grep for a file that was never written.
2. **A comment that named the other app's behaviour was wrong, and only grepping the other app could show it.** `LibrarySort.storedKey`'s docblock claimed its `field:direction` shape was "the same shape the Mac's own preference uses". The Mac persists a `BookSort` **object** and guards it with `isBookSort` (`src/types/book.types.ts:218-226`); `key(sort)` in `Toolbar.tsx` is a React key, not storage. The vocabulary and the guard's *effect* are shared; the encoding is the phone's own. This is slice 2's trap 8 in another form — a sentence about the other app is undecidable by any test in this repo, so it has to be read out of that repo.
3. **The contract *refuses* a bad sort rather than defaulting it, which is what makes the stored guard load-bearing.** Measured on the probe server: `?sort=athor` → **400 `{"error":"bad request"}`**, `?dir=sideways` likewise. A stored preference from a build that no longer knows a field would therefore reach the reader as a *broken library*, not as the wrong order — so `stored(_:)` falls back to the default, and the probe seam logs when it does (`probe: sort '<raw>' is not one this build knows`).
4. **`q` of bare whitespace is not an error, and the phone still does not send it.** The server answers `q="   "` with the whole library, so the client's trim rule (`LibraryQuery.term`) agrees with the server's own handling rather than merely avoiding a crash — the two produce the same result, which is the stronger thing to be able to say.
5. **Twelve labels, eight shortcuts — and the two lists are different questions.** The menu offers the Mac's eight curated pairs, but a *restored* preference may name any of the twelve the labels cover (the Mac's own `Toolbar.tsx:133-135` appends the current sort when it is not one of the eight, for the same reason). All twelve were read off `SORT_LABELS` in the Mac's source and compared verbatim, en-dashes included, rather than paraphrased.

### Handed to the owner's own judgement, and the residuals

- **No tap is measured; three claims are for a human frame.** `simctl` can neither open the sort menu nor type in the search field, so *the menu opens*, *the field accepts typing* and *a cover tap from a sorted library opens the right book* are claims only a person can settle. What the probe decides is the app's own path — state → request → rendered order — which is the same honest split slice 2 recorded for the background door.
- **Stage 3b — the filter chips — was not built by this stage** (it landed the same day: see *Built — slice 3b* below). Its files and its own criteria (3.10–3.13) are in the annex; the readings it leans on (facets fetched when the sheet opens, an empty selection omits its parameter rather than sending an empty one) are already settled there. Nothing in 3a forecloses it: `LibraryQuery` is where those fields will compose, and the same "every page, and never `formats=`" trap is named in its AC.
- **A search still needs the Mac.** CD3's line holds — there is no local library cache — so with the Mac asleep the app can *read* and cannot *search*. This slice is what makes that newly visible rather than newly true, and it is the standing argument for the cache rather than a debt this slice left.
- **The probe profile's final state**, so the next session reproduces from here: `rest_api_port` is **8789** (moved off 8788 for the reason above) and `base.txt` reads `http://100.125.135.108:8789`; the 8 books are untouched; the phone's stored sort is **`author:desc`**. A 3b probe run should start by putting the phone back with `SORT=title:asc` if it wants the title-order frames.
- **The owner's own app was never touched and never signalled.** It held 8788 when this session began and for the whole of the probe work, which is why the probe profile moved to 8789. It was **no longer running by the end of the session** — and that is not this session's doing: the only processes signalled here were the probe profile's own server (started once, stopped once, by listener pid — which took a second `TERM`, the dev bundle being slower to exit than its listener) and nothing else. His library and profile were never read or written at any point.

## Built — slice 3b (2026-09-23)

The library's own narrowing — read status, format, a rating floor, and the library's own authors, series and tags. **Stage 3b of slice 3**; with it **slice 3 is complete** (3a's sort and search landed earlier the same day) and the deferred item that revived slice 3 is closed. The app icon travels in the same working tree as unrelated work and has its own section below.

Three new files — `Core/API/LibraryFilters.swift` (the filter model, its wire composition, and the probe's own encoding of a set), `Features/Library/FilterSheet.swift` (the sheet: two vocabulary rows, the rating floor, three facet rows), `Tests/MusaeumTests/LibraryFilterTests.swift` (15 cases) — and three edited: `Core/API/LibraryQuery.swift` (the query carries a filter set), `Core/API/MusaeumClient.swift` (the parameters ride every request), `Features/Library/LibraryScreen.swift` (the filter state and its one funnel, the sheet, the toolbar indicator, the bar, the filtered-empty card). Plus `Core/Support/Probe.swift` and `scripts/live-probe.sh` (`MUSAEUM_PROBE_FILTERS` / `MUSAEUM_PROBE_SHEET`), `Musaeum/Resources/Assets.xcassets` + `project.yml` (the icon), `Musaeum.xcodeproj` (regenerated), the annex, and four documents.

**No design decision was re-opened** — CD1–CD8 are closed and this build changed none of them. **And no contract change, no Mac-repo slice:** `GET /api/library` already accepted `readStatus`, `formats`, `minRating`, `authors`, `series` and `tags`, and `GET /api/library/facets` already served the counts the sheet draws. What was missing was entirely the phone's own state, which composed every request from a query that had no filters in it.

### Gates

| Instrument | Result |
| ---------- | ------ |
| `xcodegen generate`, then `xcodebuild build` | **exit 0**, and no warning in this repo's own files — the 1024 icon compiles without the alpha warning an RGBA icon raises |
| `xcodebuild test` (with the icon in the target) | **exit 0 — 90 cases, 0 failures, across 12 suites** |
| `../musaeum/scripts/api-smoke.sh` | **passed 56, failed 0**, against the same server |
| AC 3.14's source walk, re-run on this tree | clean: no `file://` in `Musaeum/` or `Tests/`, the only `print(` is `Probe.log`, and the token's whole life is `SettingsStore` → the Keychain → the one `Authorization` header (`MusaeumClient.swift:89`) |
| **Mutation campaign** (14 mutations) | **14/14 killed**, every file restored — `docs/evidence/slice3/slice3b-campaign.log` |
| **The icon** | `CFBundleIconName = AppIcon`, `Assets.car` + `AppIcon60x60@2x.png` in the built bundle, and the home-screen frame |

Per file, because a total is not a decider (each read off the run's own per-suite line):

| Suite (file) | Cases | |
| ------------ | ----- | - |
| `ClientTests` | 14 | |
| `ContractDecodeTests` | 11 | |
| `CoverPipelineTests` | 3 | |
| `InitialFractionTests` | 7 | |
| `LibraryFilterTests` **(new)** | 15 | the pure rules — what a selection becomes on the wire, what an empty one omits — and the model half: page 2, clearing, the indicator, the filtered-empty state |
| `LibraryPagingTests` | 2 | |
| `LibraryQueryTests` | 6 | |
| `LibrarySortTests` | 8 | |
| `ReadingReporterTests` | 8 | |
| `ReadingWriteTests` | 6 | |
| `ReportQueueTests` | 4 | |
| `StoreTests` | 6 | |

### The campaign

Each mutation applied one at a time, its focused suite required to redden, with the same suite run green first so a red row means an assertion failed rather than a suite that does not exist. Failures are the runner's own count; the case list is beside it for the reason below.

| Mutated | Failures | Cases that reddened |
| ------- | -------- | ------------------- |
| an axis with nothing in it travels as an empty parameter | 15 | **5** — every case that observes a composed request |
| the client joins values with the server's separator | 2 | 1 — `testEachSelectedValueIsItsOwnQueryItem` |
| filters dropped from page two only | 1 | 1 — `testTheFiltersRideOnThePageAfterTheFirstToo` |
| clearing the filters forgets one axis | 4 | 1 — `testClearingTheFiltersAsksForTheWholeLibraryAgain` |
| a filter change that changes nothing still asks the Mac | 2 | 1 — `testAFilterChangeThatChangesNothingAsksTheMacForNothing` |
| the indicator counts axes rather than values | 1 | 1 — `testTheIndicatorCountsEveryValueAcrossEveryAxis` |
| a filter that matched nothing reads as an empty library | 2 | 1 — `testAFilterThatMatchedNothingIsNotAnEmptyLibrary` |
| the format vocabulary needs the facets after all | 2 | 2 — both vocabulary-row cases |
| a failed facet fetch reads as a loaded one | 1 | 1 — `testAFailedFacetFetchLeavesTheVocabularyRowsUsable` |
| the probe parser drops a token it cannot read | 1 | 1 — `testTheProbeParserSaysWhatItCouldNotUse` |
| the status row lists the contract's three in another order | 3 | 2 — the vocabulary case and the no-facets row |
| two axes read each other's list | 2 | 1 — `testTheFacetAxesAreTheContractsOwnListsInItsOwnOrder` |
| a filter change re-fetches the counts | 1 | 1 — `testTheFacetsAreFetchedWhenTheSheetAsksAndNeverWithALibraryPage` |
| the encoder's separator drifts from the parser's | 2 | 1 — `testTheProbeEncodingRoundTripsThroughTheAppsOwnParser` |

**Every one of the suite's 15 cases is reddened by at least one row, and it took a second campaign for that to be true.** The first ten rows were aimed at what criteria 3.10–3.13 name, and four cases survived all of them with no row pointed at their own subject: the vocabulary, the facet axis lists, the facet-fetch trigger, and the encoder half of the probe round trip. Four rows were then written **at those four cases' own subjects** (the last four above), and each reddened exactly its own. A case no mutation can reach is a decider that is green and untested, so this campaign is reported against all fifteen cases rather than against the ten that were obvious.

**The counts reconcile with their mutants, and one of them is why the count must be read with the cases beside it.** Row 1 prints *15 failures* and reddens *5* cases: the mutation removes the omit-when-empty rule from every axis, so every case that observes a composed request fails, and XCTest's number is an **assertion** count (4+1+7+1+2 across those five), not a count of cases. Read alone it is exactly the shape of a suite that has gone red everywhere — which is also the shape a masked survivor hides in — so the campaign script now prints `| N cases reddened: …` beside the runner's own line.

### The live probe

Five runs against the same isolated profile as 3a (8 EPUBs, iPhone 17 Pro / iOS 26.1) at `http://100.125.135.108:8789`, committed under `docs/evidence/slice3/`. Filters are never stored, so the only state these runs leave behind is the sort run 1 names — which puts the phone back on `title:asc`, closing 3a's own residual. Two further runs measured the facet finding (reading 3).

| # | Run | What the app logged |
| - | --- | ------------------- |
| 1 | `TAG=filters SORT=title:asc FILTERS=status=reading` | `count=2 total=2 … sort=title:asc q=- filters=status=reading first=Caliban's war \| Negotiation Genius` |
| 2 | `TAG=narrow FILTERS=status=unread;format=epub` | `count=6 total=6 … filters=status=unread;format=epub first=Dragon Wing \| The Hidden Palace \| In Defense of Selfishness` |
| 3 | `TAG=filter-empty FILTERS=status=read` | `count=0 total=0 … filters=status=read first=` then `library empty kind=noFilterMatches(1) macBooks=8` |
| 4 | `TAG=sheet SHEET=1` | `facets authors=8 series=2 tags=27 formats=epub:8 statuses=unread:6,reading:2` |
| 5 | `TAG=unknown FILTERS=nonsense=1` | `probe: filters 'nonsense=1' carried nonsense=1, which this build does not know` |

Run 3's `macBooks=8` is what makes it *no filter matches* rather than *empty library* — the same fact 3a's `nomatch` run used, one cause over. Run 5 is the seam refusing to read as a run that found nothing: the app names the token it could not use and applies nothing. And run 1's `total=2` is the **server's** own answer for that parameter, measured directly before the runs (`readStatus=reading` → 2, `readStatus=unread` + `formats=epub` → 6), so these runs are not the phone agreeing with itself.

### The readings this slice settled for itself

**1. An empty selection is the *client's* rule, not the server's — and the annex said otherwise.** The annex's file list claimed "the contract refuses a bad *value* with 400, and `formats=` is a bad value". Measured on the probe server: **`formats=` answers the whole 8-book library**, and only a value the parameter cannot parse (`formats=docx`) is refused with 400. So 3.11 stands — an empty selection composes no item — but on the client's own hygiene rather than as a request the server would punish. This is 3a's trap in a new place: *a sentence about what the server does is decidable, and the way to decide it is to ask the server.*

**2. A parameter *name* the server does not know is ignored, not refused.** `?status=reading` — the wrong name — returns all 8 books, where `?readStatus=reading` returns 2. So a typo in a parameter name is **invisible on the wire**: it cannot produce an error, only a request that quietly asks for less. No stub-backed case can catch that either, since the stub answers whatever it is asked; what catches it is a case reading the *composed request* (`testAClearedSelectionComposesNoParametersAtAll` and its neighbours) and the seam's own report of what it carried.

**3. A facet value can be a filter that finds nothing, and the comma is why.** The Authors row is the Mac's own list, and on this profile one of its eight values is **`William Stixrud, PhD`** — drawn with a count of 1. A filter naming it, through the app's own path, returns **0**; a filter naming the comma-less `Steven Kotler` from the same list returns **1**. The multi-value parameter is comma-separated — the same separator this client joins with — so a value containing a comma cannot be expressed through it. This is upstream of this slice (the desktop's sidebar is drawn from the same list over the same wire) and it is **not fixed here**: recorded because it is the one place a filter the sheet *offers* is a filter that finds nothing, and because the honest fix is an encoding the contract does not have.

**4. Filters are not remembered, and these runs decide it rather than assert it.** Run 2 named a filter and run 3's first line reads `filters=-`: the app came up unfiltered, where run 2's `SORT` survived into every run after it. That is CD3's inventory behaving — a sort is a preference, a filter is a narrowing of the moment — and no single run could show it.

**5. 3.13's warning was honoured, and the frame is what says so.** That criterion exists because a toolbar renders a `Label` icon-only, which cost 3a two builds. The active-filter indicator is an explicit `HStack` (glyph, then the count), and `filters-status-reading.png` shows it **gold, with its `1`**, beside the sort control's own label: an active filter with a visible cause, which is the whole content of the criterion.

### Corrections and traps this build paid for

1. **A run that returns the expected number for the wrong reason.** The first measurement of reading 3 used `William Stri**x**rud, PhD` — a misspelling of a facet value, which the app composed and the server matched against nothing. It returned 0, which is what the run was *looking* for, and the finding looked confirmed. The contrast run exposed it: comparing against the facet's own strings showed the value is `Stixrud`. The number that mattered was never the 0 but the **pair** (0 for the comma value, 1 for the comma-less one), and one run cannot produce a pair.
2. **A row's failure count is XCTest's assertion count, not a count of cases** — see *The campaign*. The campaign script now prints the cases beside the count, because a 15-failure row that reddens 5 cases reads like a suite gone red everywhere.
3. **`xcodebuild test` stages a simulator sysdiagnose on every *failing* row** (`simctl diagnose -l -b --timeout=600`) unless `-collect-test-diagnostics never` is passed: about ten minutes of collection per red row, indistinguishable from a hung build — one row sat eight minutes with no count line before this was found. The script passes the flag now, which is what makes a 14-row campaign minutes rather than an afternoon.
4. **Killing a campaign mid-row leaves the mutant in the tree.** The restore is the loop's `finally` and a `kill` skips it — and on this repo the slice's files are still *untracked*, so `git checkout -- <file>` restores nothing at all. Found by killing a run to diagnose trap 2; recovered by reversing the one mutant by hand, then re-checking every row's anchor (counting `old` and `new` across the files) before touching anything.

### The icon

The app carries the desktop app's own artwork — the owner's call, so the two clients read as one product on the home screen. The master, `musaeum`'s `build/icon.png`, is a **macOS** icon: a squircle inset about 10% inside a transparent canvas. Shipped as it stands it would be rounded twice — once by the artwork's own baked corners, once by iOS's mask — and iOS would composite that transparent margin black.

`Musaeum/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` is therefore that artwork **cropped to its own bounds, filled to the frame with each row's own edge colour, and scaled to 1024²**. The crop is the load-bearing step: it puts the artwork's corner radius (≈22.4% of the side, the fraction both platforms mask at) on iOS's own mask radius, so the corners the fill invents are exactly the corners iOS cuts away, and what the home screen shows is the master's own composition. The PNG carries **no alpha** — an iOS icon with one is a build warning and a black-composited icon.

Measured rather than intended: the built app's `Info.plist` reads `CFBundleIconName = AppIcon` and `CFBundleIconFiles = [AppIcon60x60]`; the bundle holds `Assets.car` and `AppIcon60x60@2x.png` (120×120); and `app-icon-before-after.png` is the same home-screen page before and after the install, Musaeum in the last slot and rounded by the same mask as its neighbours. **No dark or tinted variant is declared**: one icon serves all three appearances (iOS 18 tints it itself) rather than a second set this workstream would have to keep in step with the Mac's by hand.

### Handed to the owner's own judgement, and the residuals

- **No tap is measured; the sheet's own controls are a human frame.** The probe seam can *open* the sheet (run 4), but `simctl` cannot tick a chip, so *a tick applies immediately*, *Clear all empties every row* and *tapping an author narrows the list* are claims for a person. What is decided is the app's own path — state → request → rendered results — and that the sheet draws the contract's vocabulary and the Mac's counts.
- **Reading 3 is a real, if small, defect and it is left standing.** A filter the sheet offers that finds nothing has one honest fix, an encoding the wire does not have, and that belongs to a contract change rather than to this slice. Worth the owner knowing it exists: the book it belongs to, *The Self-Driven Child*, is in his library.
- **Filters, like search, need the Mac.** CD3's line holds — there is no local library cache — so with the Mac asleep the app can *read* and cannot filter.
- **The probe profile's final state**, so the next session reproduces from here: the port is **8789** and `base.txt` reads `http://100.125.135.108:8789`; the 8 books are untouched; the phone's stored sort is back to **`title:asc`** (run 1 put it there — 3a's residual, closed); and the filters leave nothing stored at all.
- **The owner's own packaged app held 8788 for the whole of this slice's work** — it was running, as 3a recorded, and every run here used the probe profile on 8789. The two servers never met, his instance was never touched or signalled, and his own library and profile were never read or written.

## Built — slice 4 (2026-09-24)

Sending a book to the Mac: **4a, the client and the picker**, and **4b, the share sheet**. Annex: `docs/plans/2026-09-23-slice4-upload.md`; the wire is `../musaeum/docs/rest-api.md` § `## POST /api/books`, whose Mac-side slice landed 2026-09-23 — so this slice is built against a landed contract, and **no contract change, no Mac-repo slice and no design decision (CD1–CD8) was needed or taken**.

Files: new — `Core/Store/UploadModel.swift` (`UploadFile`, `UploadModel`, `Refusal`), `Features/Library/UploadSheet.swift`, `Core/Store/UploadInbox.swift`, `Tests/MusaeumTests/UploadTests.swift` (13 cases), `Tests/MusaeumTests/UploadInboxTests.swift` (7). Edited — `Core/API/MusaeumClient.swift` (`.tooLarge`, `mapStatus`'s `413`, `uploadBook`, `uploadRequest`), `Core/API/ContractModels.swift` (`ImportResult`, `DuplicateMatch`), `Features/Library/LibraryScreen.swift` (the toolbar's control, the outcome row, the sweep, the probe seam), `Core/Support/Probe.swift` (`MUSAEUM_PROBE_UPLOAD`, `MUSAEUM_PROBE_UPLOAD_SHEET`), `Tests/MusaeumTests/ClientTests.swift` (two cases), `project.yml` + `Info.plist` (the document types), `scripts/live-probe.sh` (`ACTION=upload`), `Tests/Fixtures/contract/import.json` (vendored by `scripts/vendor-contract-fixtures.sh` from the document's own block, invariant 1), `Musaeum.xcodeproj` (regenerated). Landed as `7d0fc65` — 15 files, 1,707 insertions — with the annex itself in `cd613ed`.

### Gates

| Instrument | Result |
| ---------- | ------ |
| `xcodegen generate`, then `xcodebuild build` | **exit 0**, and `xcodegen` reproduced the committed `Musaeum.xcodeproj` byte for byte. Incremental by the time it ran — the campaign had just built this tree — so this row is the target's link step; the compile evidence is the `test` gate, which recompiled the slice's files once per mutation |
| `xcodebuild test` | **exit 0 — 117 cases, 0 failures, across 15 suites** |
| `../musaeum/scripts/api-smoke.sh --profile <the probe profile>` | **passed 70, failed 0** — the annex's own expected number, measured 2026-09-24 against the current Mac HEAD, and the book it uploads is in the probe library (`Smoke Upload 20260924-164242`) |
| **Mutation campaign** (15 mutations) | **13/15 killed**, every file restored, and the two survivors are one mutation aimed at both suites that claim to decide it (below) — `docs/evidence/slice4/slice4-campaign.log` |
| **The live probe** (nine frames) | the `201`, the duplicate, the 528 MiB book, the cap refusal, the unreachable refusal, the sweep, and the toolbar — `docs/evidence/slice4/` |
| **The owner's own upload** | *The Art of Spending Money*, 1,081,907 bytes, `books/540bd9a6-…/` on the share with both covers, row `2026-09-24T13:28:46.611Z` |

Per file, because a total is not a decider (each read off the run's own per-suite line). Two sets of numbers in this table are **not** this slice's: `CoverBoxTests`' five cases came in with the cover-box fix (`d98f3a9`, 2026-09-23), and `ClientTests`' jump from 14 is two upload cases plus that fix's own share of the file.

| Suite (file) | Cases | | |
| ------------ | ----- | - | - |
| `ClientTests` | 16 | | the upload's composed request, and the `413`'s outcome with its non-retryability |
| `ContractDecodeTests` | 11 | | |
| `CoverBoxTests` | 5 | | the cover-box fix, not this slice |
| `CoverPipelineTests` | 3 | | |
| `InitialFractionTests` | 7 | | |
| `LibraryFilterTests` | 15 | | |
| `LibraryPagingTests` | 2 | | |
| `LibraryQueryTests` | 6 | | |
| `LibrarySortTests` | 8 | | |
| `ReadingReporterTests` | 8 | | |
| `ReadingWriteTests` | 6 | | |
| `ReportQueueTests` | 4 | | |
| `StoreTests` | 6 | | |
| `UploadInboxTests` **(new)** | 7 | | the hand-off's four states, the name order, and the one directory this app may delete from |
| `UploadTests` **(new)** | 13 | | the composed body being the session's file, the format from the extension, the vendored `import` payload strictly, the four refusal classes, and the claim that waits for the `201` |

### The campaign

Fifteen mutations, one focused suite per row, every anchor asserted to match its file **exactly once** before the campaign ran, and every row reporting `restored=True`. The runner is `docs/evidence/slice4/focused-test.sh` (the focused suite on the destination **by id**, `-collect-test-diagnostics never`), the raw per-run output is `slice4-runs.log`, and the verdicts are `slice4-campaign.log`.

| Mutated | Verdict | Suite | Case that reddened |
| ------- | ------- | ----- | ------------------ |
| Mutated | Verdict | Suite | The case the log names |
| ------- | ------- | ----- | ---------------------- |
| the upload's body is held in memory instead of read from the file | **GREEN (SURVIVED)** | `UploadTests` | — nothing reddens |
| the wire carries the format where the file's own name belongs | killed | `UploadTests` | `testABusyMacIsOfferedARetryAndTheCopyIsKeptForIt` |
| 413 falls back to the default mapping (the gap this slice opened on) | killed | `UploadTests` | `testAnOversizedBookIsRefusedAndNeverClaimedAndNotSentAgain` |
| the 413 keeps its mapping but loses its own arm in the class funnel | killed | `UploadTests` | `testTooLargeIsTheBooksOwnProblemAndNeverAWorthWaitingOne` |
| 413 is declared retryable (the belt-and-braces line) | killed | `ClientTests` | `testContentTooLargeIsItsOwnOutcomeAndIsNotRetried` |
| an always-present member decodes to nil instead of throwing when absent | killed | `UploadTests` | `testAMissingMemberInTheImportPayloadIsRefused` |
| the format is compared without lowercasing the extension | killed | `UploadTests` | `testTheFormatComesFromTheFilesOwnExtension` |
| a name the contract does not name is sent anyway | killed | `UploadTests` | `testTheFormatComesFromTheFilesOwnExtension` |
| the library is claimed before the Mac has answered 201 | killed | `UploadTests` | `testARefusedTokenIsItsOwnClassAndOffersTheWayBackToTheConnectScreen` |
| a refusal's own class stops deciding whether the bytes stay | killed | `UploadTests` | `testARefusedTokenIsItsOwnClassAndOffersTheWayBackToTheConnectScreen` |
| the collision and the ordinary case say the same sentence | killed | `UploadTests` | `testABookTheMacCreatedIsTheOnlyThingThatClaimsTheLibrary` |
| the system's copy is deleted from anywhere it is handed | killed | `UploadInboxTests` | `testTheSystemsCopyGoesOnlyFromThisAppsOwnInbox` |
| the sweep takes whatever a share ever left, books or not | killed | `UploadInboxTests` | `testAShareThatArrivesBeforeTheAppCanSendItIsStillThereAfterARelaunch` |
| a directory named like a book is taken as one | killed | `UploadInboxTests` | `testAShareThatArrivesBeforeTheAppCanSendItIsStillThereAfterARelaunch` |
| the upload's body is held in memory (the client's own case decides the same thing) | **GREEN (SURVIVED)** | `ClientTests` | — nothing reddens |

**Both survivors are the same mutation, and they are the finding this campaign exists for.** The row pastes the file's bytes into an in-memory body (`upload(for:from: try Data(contentsOf: file))`) where the app hands the session a file — and it leaves `UploadTests`' `testTheUploadBodyIsAFileTheSessionReadsRatherThanBytesInMemory` **green**, so it was re-aimed at `ClientTests`' `testUploadRequestCarriesTheContractsParametersAndNothingElse`, which asserts the same thing for the client's own composer. **Also green.** So the two cases that claim AC1's second half — *the body is a file the session reads, not bytes in memory* — cannot see the difference at all: `URLSession` normalizes either shape into a body stream before a `URLProtocol` sees it, and `XCTAssertNil(request.httpBody)` is true both ways. AC1's *shape* half is asserted rather than decided, and the instrument that could decide it is R1's — a resident-footprint reading while a large file goes out — which this slice did not take. One kill is missing for a reason worth a row: `ClientTests`' `testContentTooLargeIsItsOwnOutcomeAndIsNotRetried` is the decider for the *other* half of AC2 (it asserts the mapping **and** the non-retryability), which is why the retryability row is aimed there and not at `UploadTests`.

### The live probe

Nine frames from the simulator against a real Musaeum on slice 1's isolated profile, taken 2026-09-23/24 and committed in `docs/evidence/slice4/` with their own README. The readings they decide are in *Slice 4*'s roadmap section and beside each frame; the two that only a frame could produce are **the `413` arriving mid-body** (R3 — the row says *content too large*, so `URLSession` reads a refusal the Mac answers while the sender is still sending, which the Mac's socket-level proof had left open for a real client) and **the duplicate's own sentence** (the second send of the same file: *Sent — and you already had it*, `title_author`, and a **second row** in the library, which is `add-new` working rather than a refusal).

**What the probe leaves unmeasured, and the honest shape of it:** R1's resident footprint and R2's cost (seconds, and whether the foreground window is enough for F1's default session) were not taken. The 528 MiB run is the reason to want both — the app sent **553,649,623 bytes** and the row settled, so the *shape* is answered and the *cost* is not. And the runs' own log lines were never captured to files, which the evidence README records first rather than last.

**The owner's own upload is the reading no probe can make.** He picked a book on his iPhone and it is in his library: `The Art of Spending Money`, 1,081,907 bytes, at `books/540bd9a6-…/` on the share with both covers and its own `metadata.json`, the share's `catalog.json` rewritten at 13:28:49Z and the row dated `2026-09-24T13:28:46.611Z` — with the Mac's own record agreeing on every part. That is 4a's whole path over a real tailnet and a real SMB share, which no run on the probe's local folder can rehearse.

### The readings this slice settled for itself

**1. `URLSession` reads a `413` answered mid-body — the annex's R3, answered by a frame rather than by a preference.** The Mac's own slice had proved this for a raw socket (`sent < declared / 4`); a real client was the open question, and a stub-backed case cannot ask it, because a `URLProtocol` never refuses anything. The frame is the answer, and it is why the refusal is classed as *this book's own problem* instead of degrading to *the upload failed*.

**2. A duplicate is the Mac's answer, and its `add-new` policy is what makes a retry safe.** The same file sent twice produced two rows and a payload naming the match type; the alternative reading — that a retry risks a duplicate, so a failed upload must be reconciled — is measurably wrong, and F1's "there is nothing to reconcile on either side" holds.

**3. The `201`'s payload is the row *before hydration*, and the phone's own copy says so.** The frame's sentence ("the Mac's metadata pass is still running, so its series and cover may fill in after this") is the contract's S7 line, and the library agrees: the 528 MiB book's folder holds the epub and a `metadata.json` with `authors: []` and `cover: null`, titled by the wire's `filename` because the import found no metadata of its own.

**4. What a share can reach decided 4b's shape, and it was a measurement rather than a preference.** F2 weighed a shared container against a second copy of the token and found the first requirement invisible: an app group or a keychain access group both need an Apple Developer Program capability, this app is signed with a free personal team, and adding either stops the profile being issued — so the app itself would have stopped installing on the owner's iPhone while the simulator, which ignores provisioning, kept every gate green. The route with no capability at all is the system's own document hand-off, and it keeps the token in one process (invariant 10) as a property of the design rather than a discipline.

**5. Slice 4 forced no contract question.** Every field, refusal and parameter the client needed was already in the document the client derives from, which is the second time a slice has landed with the Mac repo untouched (3b's was the first) — and it is what invariant 1 is for.

### Corrections and traps this build paid for

1. **A survivor can be the campaign's own aim rather than the suite's gap.** The row that makes `413` retryable survived its first run because it was pointed at `UploadTests`, where nothing reads `isRetryable` for that status; the decider is `ClientTests`' `testContentTooLargeIsItsOwnOutcomeAndIsNotRetried`, which asserts the mapping *and* the non-retryability in one case. Re-aimed, it kills. Attribute a verdict before reporting it — the same rule 3b wrote for a kill, applied to a survival.
2. **`simctl diagnose` again, for the rows the flag had not reached yet.** `xcodebuild test` stages a simulator sysdiagnose of about ten minutes on a failing row unless `-collect-test-diagnostics never` is passed; a row of this campaign sat with no verdict line long enough to look like a hung build before the flag was added to the runner. 3b recorded the trap; this build met it because the runner that carried 3b's lesson was not the runner written here.
3. **Killing a campaign mid-row leaves the mutant in the tree — twice.** The restore is the loop's tail and a `kill` skips it. Both times the file was identified with `git diff` and reversed with `git checkout --`, and the anchors were re-checked before the campaign was restarted. On this repo the slice's files *are* tracked, so the restore works — which is what 3b could not rely on and named.
4. **AC1's decider does not decide its own criterion, and both cases that claim it are green under the same mutation.** Both of them that claim this half assert the same thing — that the request the `URLProtocol` sees carries no `httpBody` and a stream of the file's own bytes — and a mutation that replaces `upload(for:fromFile:)` with `upload(for:from: Data(contentsOf: file))` leaves **both green**: `URLSession` normalizes either shape into a body stream before a protocol sees it, so the stub cannot tell an in-memory body from a file. The criterion's *shape* half is therefore asserted rather than decided, and the instrument that could decide it is R1's — a resident-footprint measurement while a large file goes out, which is the reading that was not taken. Recording it here is the point: the suite is green, and one of the four things AC1 promised is not what its case proves.

### Handed to the owner's own judgement, and the residuals

- **The two human frames (AC9) are not captured:** the picker *opening* and a book *being chosen from it*, and — for 4b — a share sheet *offering Musaeum*. `simctl` can drive neither, so they are the owner's, and the tap is also the one thing that would decide the copy's own wording on a real device. Everything else in this section is the app's own path plus the Mac's record of what arrived.
- **R1's footprint and R2's cost are unmeasured**, and R1 is where AC1's unstopped half lives (correction 4). The honest next instrument is a large-book run with the app's own memory read while the body goes out.
- **An upload that outlives the app is a new send** (F1(a), taken deliberately): the default session was chosen because the *outcome* survives backgrounding, not the transfer. Its reversal condition is R2's measurement.
- **One file at a time, no batch, and no resume.** The route takes one body per request and has no `Range` and no idempotency key; a batch is a queue the phone would own, and neither exists. All three are in the deferred list with their conditions.
- **A file the app cannot read is reported rather than worked around** — an undehydrated iCloud Drive placeholder, a Photos item, a URL that would have to be fetched first. The annex said so and the build kept it: `UploadFile.stage` fails, the row says the file could not be read, and nothing is claimed about the Mac.
- **The probe profile's final state**, so the next session reproduces from here: **port 8789**, base `http://100.125.135.108:8789`, the library at **13 books** — the 8 it started with, the two `Smoke Upload …` rows (`api-smoke.sh`'s own upload, one per smoke run) and the three `Probe Upload …` rows (the two alpha sends and the 528 MiB one) — and the sort back on `title:asc`. The owner's packaged app held 8788 throughout and was never touched or signalled.

---

## Built — slice 5 (2026-09-24)

**Sharing a downloaded book out.** Annex: `docs/plans/2026-09-24-slice5-share-out.md`. Three new files (`ShareStaging`, `Features/Shared/ShareSheet.swift`, `ShareStagingTests`), six edited (`DownloadStore`, `BookDetailScreen`, `DownloadsScreen`, `Probe`, `MusaeumApp`, `LibraryScreen`), the probe script, and the docs. **No CD re-opened, no contract change, no Mac-repo slice, and no capability of any kind** — the annex drew eight files and the ninth is `LibraryScreen`, which carries the detail seam the frame needed; that addition is named here rather than folded in.

Gates: `xcodegen generate` then `xcodebuild build` **exit 0**; `xcodebuild test` **exit 0 — 136 cases, 0 failures, 16 suites**, moved from the **117 across 15** this slice started on, and the whole move is this slice's own **19 cases in `ShareStagingTests`**; `../musaeum/scripts/api-smoke.sh --profile <the probe profile>` **70 passed, 0 failed** — unchanged, and that is the reading a slice touching no route should produce; a **21-mutation campaign, 21/21 killed**, every file sha256-verified restored (`docs/evidence/slice5/mutation-campaign.log`, `…-2.log`), with **all 19 of the suite's cases reddened by at least one row**.

### The readings

| What a probe run decided | The reading |
| --- | --- |
| `TAG=share ACTION=share BOOK=ef91875e-…`, the Mac up | `share staged … name=Negotiation Genius - Deepak Malhotra.epub linked=1 bytes=660053`, then `share reading … bytes=660053 source=660053 same=1 dir=…` — **the name is the title and the byline** and not the stored id, the **hard link** was taken, and the staged bytes *are* the download's |
| the same run with **the Mac stopped** (no listener on 8789, `pgrep` empty first) | `library failed the Mac is not answering … falling back to the phone's own copy` → `share staged …` — **the same name, the same link, the same bytes**. The file a share hands out comes off the phone's own disk, and no client is anywhere in that path |
| `TAG=detail DETAIL=ef91875e-…` | the frame: gold **Read**, raised **Share** with its words, *Remove the download* beneath — and the staged listing **empty**, where run 1's copy was still on disk when this run began. That is the launch sweep, decided on real data rather than asserted |
| the container listing after a share | `…/Musaeum/Share/Negotiation Genius - Deepak Malhotra.epub` — one file, beside `Books/`, and the same listing with nothing staged before a share asks |

### Corrections and traps this build paid for

1. **`TAG=` is a label, not a switch — and the first share run decided nothing while looking green.** `TAG=share BOOK=<id>` without `ACTION=share` came up, listed the library, downloaded a book, opened the reader and logged four ordinary lines with **no `share` line at all**. Nothing failed; nothing of this slice was exercised. That is slice 2's trap 7 (a seam variable declared but never consumed) in its plainest form — the run was *named* for an action it was never told to take. The script now refuses to stay silent: a `TAG` that names an action it was not passed prints `warning: TAG=share names an action but ACTION is empty — pass ACTION=share`. The undecided run's own log lines are kept in `docs/evidence/slice5/README.md`, because a run that looked green and decided nothing is the finding, not the embarrassment.
2. **A second guard on the same observable made the first fallback undecidable.** `fileName` originally carried two empty-stem guards — the id fallback, then a defensive "even the fallback sanitised away" return — so a mutation dropping the *first* still produced `fallback.epub` down the dead path, and the criterion would have been green and unproven. The fix put the rule where it belongs (`fallbackStem`: the id, sanitised, or the fixed word `book`), leaving **one** path for one row to reach. The general form is worth keeping: **two guards over one observable is a criterion no single mutation can decide**, and the campaign found this one before the record did.
3. **A case no row could reach, for two different reasons, and it was the case that was wrong.** `testABookThePhoneHoldsNoCopyOfStagesNothing` survived all twenty rows at first: the store it ran against was *empty*, so "an empty shelf" and "a shelf without this book" were the same test — and the two guards (`downloaded(id)` and `fileURL(for:)`) each yield `nil` alone, so no single lie reddened it. It now holds one book and asks for **another** (its payload re-derived through the strict decoder from the fixture's own text), which is the claim the door actually makes; one more row — a door that stops checking whether the phone holds the book at all — reddens it, and its blast radius is exactly the two cases about a book with no file. Third slice in a row where a case had to be re-written at its own subject.
4. **A killed run leaves a staged copy, and the first sweep was in the wrong place.** Run 1's `Share/…epub` was still in the container when run 2 started: the sweep lived in the sheet's dismissal and at the head of the next stage, and an app the OS ends mid-share reaches neither — so a staged 528 MiB book would sit on the phone indefinitely. The store now sweeps at `init`, which is what makes the directory mean what it says, and run 2's empty listing is the reading that proves it. **This one came from reading the probe's own output rather than from a case**: the unit suite was green either way.

### Handed to the owner's own judgement, and the residuals

- **The sheet itself (AC9) is his frame:** whether AirDrop, Mail and Messages appear for the staged EPUB, and what the receiving app shows the file as. `simctl` presents no sheet and taps nothing, so it is stated as his rather than implied.
- **The shelf's own frame is not captured, and the reason is named:** reaching the shelf needs a navigation this build has no seam for (`downloadsRow` is a `NavigationLink`, and the bar's door left the bar in slice 3b's fix). The **detail's** door — the primary one — has its frame; the row's two glyphs are a judgement for his eyes on the device, and the intent is in the code and the records: gold is what the row's tap does (open the book), muted is the share, separate tap targets.
- **Which activities suit which book** (R4): AirDrop and *Save to Files* carry any file; Mail will refuse or bounce the large ones, and Messages gets unreliable well before them — against a library whose measured worst case is 554,110,279 bytes. Not a defect and not measured here: a caveat about the door, carried in the changelog's *Not yet*.
- **The share carries the format the phone holds** — `formats.first`, the contract's own preference, which for this library is an EPUB that Apple Books opens anywhere. A Kindle-format-only book is shared as that file, and a DRM-locked one is no more usable to a recipient than it was to the owner. F1's reversal condition is wanting a format the phone does not hold, which would put the Mac back in the path.
- **The probe profile's final state:** port **8789**, base `http://100.125.135.108:8789`, **13 books**, sort on `title:asc`, and the phone holding two downloads (`ef91875e-…`, the shared book at 660,053 bytes, and `9e9ed0ee-…` from slice 3's runs) **plus a staged share** at `Share/Negotiation Genius - Deepak Malhotra.epub`, left by the last run and swept by the next launch. The owner's packaged app held 8788 throughout and was never touched or signalled.

---

## Built — slice 7 (2026-09-28)

**Shelves on the phone.** Annex: `docs/plans/2026-09-28-slice7-shelves.md`. New: `Musaeum/Features/Detail/ShelfChecklist.swift`, `Tests/MusaeumTests/ShelvesTests.swift`, `docs/evidence/slice7/`. Edited: `ContractModels` (the `Shelf`/`Shelves`/`MembershipResult` models, `ContractBook.shelves`, and `stringsOrEmpty` — invariant 4's one deliberate exception), `MusaeumClient` (three calls, one composed membership request), `LibraryQuery` (the scope, the seventh sort field, the fourth empty state, the placeholder rule), `LibraryScreen` (the probe, `openShelf`/`closeShelf`, the prior-sort memory, the scope control, the notice row), `BookDetailScreen` (the row, the sheet, the toggle), `Probe` (one variable), `scripts/live-probe.sh` (the two actions, the shelf reading, a device default that had gone stale), `ContractDecodeTests` (five cases), `LibrarySortTests` (its contract-vocabulary guard — the case doing its job). **No CD re-opened, no contract change, no Mac-repo slice** — the wire was `../musaeum`'s slice 5, and this slice only reads it.

Gates: `xcodegen generate` then `xcodebuild build` **exit 0**; `xcodebuild test` **exit 0 — 209 cases, 0 failures, 25 suites**, moved from the **191 across 24** this slice started on; the whole move is this slice's own **13 cases in `ShelvesTests`** plus **5 in `ContractDecodeTests`**. Two commits: the annex + the re-vendored fixtures + the one-line staleness fix they exposed, then the feature and the probes.

### The readings

| What a probe run decided | The reading |
| --- | --- |
| `TAG=shelf ACTION=shelf SHELF=2c8e4c18-…`, the Mac up | `shelves count=1 names=To Read`, then the scoped page: `count=2 total=2 sort=shelf_added:desc first=Seed Two \| Seed One` — **the Mac's own default order, mirrored on the phone and sent explicitly** — the same ids in the same order the Mac's own `/api/library?shelf=…` answers. `probe: shelf open id=… count=2 total=2 first=3725db1f-…,2f91b9be-…` |
| the frame (`frame-scoped-grid.png`) | the scope control `▤ To Read` (gold: the list is narrowed), the field reading *Search “To Read”*, the sort at *Date Added to Shelf, Newest First*, footer **2 books** |
| `TAG=shelf-add ACTION=shelf-toggle DETAIL=2ee7b426-… SHELF=…` | `before … shelves=` (empty) → `shelf added … shelves=2c8e4c18-…` → after: on the shelf, `failure=-`; **the Mac's own count 2 → 3**, and its file's `updatedAt` moved |
| `TAG=shelf-remove …` — the same call, the other direction | `before … shelves=2c8e4c18-…` → `shelf removed … shelves=` → after: empty; **the Mac's own count 3 → 2**, file and cache agreeing with the two seeds |
| the detail's frame (`frame-detail-shelves-row.png`) | `Shelves  To Read ›` under Status — the membership as the server answered it |

### Corrections and traps this build paid for

1. **The plan's F5 was wrong, and the build corrected it in place.** The annex said the picker would live *in the title*; the title is the Mac's **wordmark** (the owner's own design, landed 2026-09-27), and `titleRow`'s own comment records that the bar **cannot take a fourth control** — a wider label pushes the sort off it into `•••`. The scope went to the **narrowing row** instead (scope, field, filter — the three narrowings together), and the annex's F5 and Files table were amended to say so rather than left to disagree with the tree. **The general form:** an annex must re-read the two files it names *when it is executed*, not only when it is written — five days was enough for the wordmark to move under it.
2. **The client's own contract guard caught the seventh field before the implementation stated its rule.** `LibrarySortTests.testEveryOptionIsAValueTheContractAccepts` went red the moment `shelf_added` existed; the fix taught the guard the contract's **seven** fields *and their inside-only rule* rather than widening a list, and it is now the case that says what `stored()` refuses and why.
3. **The destination moved again — and this time the repo's own files had moved with it.** `DE0B5601-…` (iPhone 17 Pro / **iOS 26.1** — the id in `AGENTS.md`, the README and the probe script) no longer exists on this machine; the 26.1 runtime is gone and iOS 27.0 devices are back, including `39D29C73-…`, the id this repo's own history named before. `scripts/live-probe.sh`'s default was corrected here. **`AGENTS.md` and the README still name the dead id** — one line each, left for the owner because they are agent-instruction files and the edit was not attempted around the guard.
4. **The re-vendor exposed pre-existing staleness, and it was not shelves.** The fixtures were last vendored before the Mac's app version moved, so `health.version` said `0.1.0` in the goldens while the document has said `0.5.0`; `testHealthDecodes` asserted the stale literal and was the first run's only red line. It now asserts the document's own value — the client's half of a re-vendor.

### Handed to the owner's own judgement, and the residuals

- **The picker menu open, and the checklist sheet itself (AC12's stated half):** `simctl` presents no menu and taps no check. The two frames carry what a run can — the scope as it scopes, and the row as it reads; a *tap* is his.
- **The in-shelf sort label is long, and the frame shows it pressing the wordmark.** *Date Added to Shelf, Newest First* is the Mac's own wording and it stays; what it costs is width in the bar where the wordmark would draw. It does **not** collapse the control (`•••` did not appear — the trap slice 3b's measurement is about). If it reads badly on the device, the cheap fix is a shorter *shelf* label, not a different feature.
- **The capability 404 and R5's live 404 were not exercised live** — no pre-shelves Mac can be built now, and the run's profile holds a shelf that exists. Both are stub-server cases (`ShelvesTests`), stated as the case's reading rather than a run's.
- **Creating, renaming and deleting shelves remain the Mac's** (the document's *Not in this version*): the phone scopes and toggles membership and nothing else.
- **Toggles are refused offline with a sentence, never queued** (F4, taken): the writes are idempotent, so the retry is a second tap. Its reversal condition — shelf edits with the Mac asleep — brings the row-state question with it and is named in `tasks.md`.
- **The probe profile's final state:** `slice5-smoke` at port **8791**, base `http://100.101.133.118:8791`, three books, one shelf (*To Read* — the two seeds, restored after the runs, `updatedAt` moved), the phone's sort back on `title:asc`. The owner's packaged app (8788) was never touched or signalled.

