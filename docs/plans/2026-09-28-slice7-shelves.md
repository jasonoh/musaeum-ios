# Slice 7 — shelves on the phone

**Date:** 2026-09-28
**Slice:** 7 — **two stages**, client-only, against a landed contract. **7a — the read path:** the two new payloads, the client's three calls, the capability probe, the picker in the library header, and the scope itself. **7b — the write path:** the detail's *Shelves* checklist, its toggles, and the failure surface. Nothing on the wire moves: `../musaeum`'s slice 5 put it there (plan `../musaeum/docs/superpowers/plans/2026-09-28-bookshelves-slice5.md`), `apiVersion` stayed **1**, and every route this slice reads or writes was in the document before it started.
**Annex to:** `docs/specs/2026-09-22-client-v1-design.md` — its CD1–CD8 are closed and this slice adds no CD. Written against `../musaeum/docs/superpowers/specs/2026-09-27-bookshelves-design.md` **D10** (the wire) and **D11** (this slice's own map), and against `../musaeum/docs/rest-api.md`, which is the only description of what travels. **D11 is carried out here rather than re-decided** — its Core/API, Library, Detail and Fixtures bullets are the file plan below, with the readings it left open settled in *The forks*.
**Read first:** `Musaeum/Core/API/ContractModels.swift` (`StrictObject` at `:42`, and the always-present doctrine at `:10-15` — the one exception below bends it deliberately) — then `Musaeum/Core/API/LibraryQuery.swift` (what a sort is; what a query carries) — then `Musaeum/Features/Library/LibraryScreen.swift` (the model's request composition and generation guard from `:13`; the header from `:664`; the sort menu at `:738`) — then `Musaeum/Features/Detail/BookDetailScreen.swift` (the action stack the checklist joins, and the state shape a sheet takes) — then `Tests/MusaeumTests/LibraryQueryTests.swift` (the stub-server idiom every request-shape case here copies) and `Tests/MusaeumTests/ContractDecodeTests.swift` (the golden-decode idiom).

---

## What this slice is

**7a.** The library screen gains a **shelf scope**. A control in the header lists the shelves the Mac reports — *All Books* first, then each shelf with its own count — and choosing one narrows the list to that shelf: the same treatment the search and the filters already get, riding on **every** page (`LibraryQuery`'s own lesson, 3.3), with the Mac's own default inside a shelf: **Date Added to Shelf, newest first**, sent explicitly rather than left to the server's default (`wireDirection`'s own doctrine). Leaving restores the sort the reader had. Search and filters keep working inside the scope; the search field names it (`Search “To Read”`), which is the Mac's own copy.

**7b.** A book's detail gains a **Shelves** row opening a checklist: every shelf, the book's membership checked, and a tap that is exactly one `PUT` or `DELETE` on the membership path. The answer is the server's own `book`, and the row refreshes from it — never a local guess. A failure surfaces the error's own sentence and leaves the checklist as it was; a retry is safe because the Mac's writes are idempotent (D10: an existing member keeps its `added_at`; removing a non-member is a 200).

**The capability gate (D11, the Mac's D10).** The phone probes `GET /api/shelves` once per library load. **200** → the picker and the checklist exist. **404** → they do not; every other route this app speaks works against a pre-shelves Mac exactly as before. **Unreachable** → *unknown*, and unknown is not absent: the UI keeps whatever it last showed rather than claiming a shelf feature is missing — the same distinction `Reading.percent`'s `null` draws one level down.

**What this leans on rather than builds** (each verified before this annex was written):

| Already there | Where | What it means here |
| --- | --- | --- |
| **The landed wire** | `../musaeum/docs/rest-api.md`; the Mac plan's *Built — slice 5* | `GET /api/shelves`; `?shelf=` on `/api/library` and its facets; `shelves` on every book payload; the membership `PUT`/`DELETE`. Read, never re-derived (invariant 1) |
| The vendored goldens | `scripts/vendor-contract-fixtures.sh`; `Tests/Fixtures/contract/` | Re-vendored 2026-09-28: the four book-carrying fixtures gained `shelves`, `shelves.json` and `membership.json` are new. **This re-vendor is this slice's first commit** — it is what makes the fixtures the document's current text |
| **The strict reader, and its one exception** | `ContractModels.swift:42-86` | `StrictObject` throws on an absent key — which is why `shelves` is read through a new `stringsOrEmpty`: a pre-shelves Mac omits the member, and a required read would take the whole library down over a field the reader never sees. D11 names this as the deliberate exception; it is documented at the call site |
| The query that must carry the narrowing | `LibraryQuery.swift:140`; `MusaeumClient.library(...)` at `MusaeumClient.swift:162` | `shelf` joins `sort`, `text` and `filters` inside `LibraryQuery`, so a page two cannot forget it — the failure 3.3 was written to prevent |
| The Mac's own sort vocabulary and labels | `../musaeum/src/types/book.types.ts:219-221`; `Toolbar.tsx:33-39` | *Date Added to Shelf, Newest First* / *…, Oldest First*, and `shelf_added`'s natural direction is **desc** (`book.types.ts:249`). The phone mirrors these strings and this rule, the way `LibrarySort` already mirrors the other eight |
| The stub-server test idiom | `LibraryQueryTests.swift` (and the `nonisolated` note at `:10-16`) | Every request-shape case here is one of these: what the request carried, read off `StubURLProtocol.requests` |
| The detail's action stack and sheet shape | `BookDetailScreen.swift:168-231` (actions), `:130-135` (`.sheet(item:)`) | The *Shelves* row joins the stack; the checklist is a sheet item, the shape `ShareRequest` already uses |
| The probe seam | `Probe.swift`; `scripts/live-probe.sh` | Two new actions, so the scope and a toggle are drivable without a tap |

**Explicitly not in this slice, each for a stated reason:**

- **Creating, renaming or deleting a shelf.** The document's *Not in this version* names all three; a phone that composed those bodies would be a client inventing routes. The Mac remains the only place a shelf is made.
- **Smart shelves.** The route answers `kind: "manual"` only; the phone decodes `kind` and does not branch on it, so a future kind appears without a client change and nothing here pretends to know what one would mean.
- **Dropping books into the current scope as a batch, and multi-select membership.** Slice 4's batch deferral, unchanged; each toggle is one book's membership and says so.
- **A queue for toggles made while the Mac is unreachable.** D11 left this open and 7b settles it: **refuse, with a surface** (F4).
- **A shelf's own screen.** The scope *is* the library narrowed — D7's rule one device over — so there is nothing to push.
- **A local cache of shelves.** CD3's inventory is untouched: the shelves list is fetched state and request state, never stored. The scope does not survive a relaunch (the search's own rule), and the persisted sort never becomes `shelf_added` (F2).

## The forks, each with the alternative it beats and its reversal condition

### F1 — how the scope rides the request: inside `LibraryQuery`, or beside it

- **(a) `LibraryQuery` gains `shelf: Shelf?`.** It answers the same question the sort, the term and the filters answer — *what is this screen asking the Mac for* — and the model's one composition path then cannot forget it.
- **(b) a property on the model, appended to the request at the call site.**

**Recommendation: (a).** It is the file's own written reason for `filters` living there ("a second property on the model would be a second thing a `request` could forget, and forgetting it is the failure 3.3 names"), and it makes `LibraryEmptyState.of` able to read the scope without a second argument. **Reversal condition:** none foreseen; a scope is a narrowing like the others.

### F2 — the sort when a shelf opens: mirror the Mac, or keep the reader's sort

- **(a) mirror the Mac** (AC18/D8): entering a shelf switches to *Date Added to Shelf, Newest First*; *Date Added to Shelf* appears in the sort menu only inside a shelf; leaving restores the prior sort; the persisted sort is never `shelf_added`.
- **(b) keep whatever sort was on** and let the server order by it inside the shelf.

**Recommendation: (a).** The Mac made this decision for a reason a case can state: *Date Added to Shelf* outside a shelf is **meaningless** (`Toolbar.tsx:33`), and a reader entering their shelf wants the newest addition first, not their last global preference — while the sort the reader chose for *All Books* is a real preference that leaving restores. Both halves are unit decisions. **Reversal condition:** the owner preferring a remembered per-shelf sort, which would need the scope to persist, which CD3's inventory currently refuses.

### F3 — the capability probe's states: two or three

- **(a) three states** — `shelvesSupported: Bool?`: `true` (200), `false` (404), `nil` (not asked yet / could not ask). The picker draws only on `true`.
- **(b) a boolean**, with unreachable folded into "no".

**Recommendation: (a).** (b) is the failure `Reading.percent`'s doctrine exists to stop: a Mac that is asleep would read as a Mac without shelves, and the moment it woke the control would appear — a UI that lies about a capability it never asked about. `nil` draws nothing either, but it *means* something different, and the model can say which. **Reversal condition:** none; the third state costs one optional.

### F4 — a toggle while the Mac cannot take it: refuse, or queue

- **(a) refuse with a surface** — the error's own sentence under the checklist, the row un-toggled, the retry a second tap. The writes are idempotent, so the retry is safe, and the reader is looking at a screen that says what happened.
- **(b) a `ReportQueue`-style replay** — the reading-report pattern, sending later.

**Recommendation: (a).** The report queue exists because a *position* is precious, has one writer, and its clock ordering already answers the conflict question; a membership toggle has none of that — it has a person looking at a checklist, and a queued toggle would need an answer for what the row shows until it lands (checked? unchecked? both are wrong). **Reversal condition:** the owner wanting shelf edits from the sofa with the Mac asleep, which would bring the row-state question and be its own design.

### F5 — where the picker lives: the narrowing row (**amended during the build, 2026-09-28**)

**The recommendation below was written against a tree five days older than the one it was executed on, and the build corrected it.** It said the title becomes the menu (*All Books ▾*). Executing it found two things the write-up had not looked at: the title is the **Mac's wordmark** (the owner's own design, landed 2026-09-27), and `titleRow`'s own comment records a measurement — the bar **cannot take a fourth control**, because a wider label pushes the sort off it into `•••`, which is exactly what slice 3b's fix un-did.

- **(a) the scope joins the narrowing row** — the search row, before the field: scope, field, filter, the three narrowings together on the same 44 pt capsule, the scope's own label gold when the screen is narrowed, like the filter's count. **Chosen; the frame is `docs/evidence/slice7/frame-scoped-grid.png`.**
- **(b) the title becomes a menu.** Rejected: it would overwrite the wordmark, and the wordmark is not this slice's to replace.
- **(c) a fourth control in the bar.** Rejected on the recorded measurement, not on taste.

**Reversal condition:** the owner finding the scope undiscoverable in the narrowing row — the same class of judgement the store door's own move carried (`docs/evidence/toolbar-alignment/`).

### F6 — a toggle's answer: the returned book, or an optimistic check

- **(a) the returned `book`** (D10: both writes answer `200 { "book": … }` in the detail shape) replaces the model's `phase`; the row refreshes from it.
- **(b) flip the check optimistically**, reconcile on failure.

**Recommendation: (a).** The checklist is a small sheet over a fast route; the server's answer carries the row's real state (including `added_at` semantics the client deliberately does not model), and (b) would be this client inventing a state it then has to unwind — with the extra edge that a *stale* Mac answer (a shelf deleted elsewhere) would leave a check standing for nothing. **Reversal condition:** measurable latency making the toggle feel dead, in which case a per-row spinner is the cheaper fix than optimism.

## Readings this slice must settle itself, each with the alternative it beats

### R1 — where *leave the shelf* lives, and what the menu calls it

D11 says the picker is *All Books ▾ → shelves*. **Chosen: the menu's first row is *All Books*, which is both the label the title shows when no shelf is open and the way back.** It mirrors the Mac's *Library* control (AC17) with the phone's own word for the same place, and it means the menu has no separate *Leave* affordance to learn. **The alternative it beats:** a checkmark on the open shelf and no dedicated exit, which reads fine until the open shelf scrolls out of memory — the same trap the Mac's slice 2 recorded.

### R2 — the empty-shelf screen's sentence

The Mac's rule (settled with the owner 2026-09-28) is that an empty shelf's copy names a route that **works from where the reader is standing** — the Mac's says *drag them onto this shelf in the sidebar, or right-click a book*, which is a sentence this phone may not copy because neither gesture exists here. **Chosen: *No books on “To Read” yet.* with a second line naming the phone's own working route: *Open a book and use Shelves to put it here.*** It is a fourth `LibraryEmptyState` case (`.shelfIsEmpty`), because the three existing sentences would each be a lie over an empty shelf — the exact class of lie slice 3b fixed on the Mac. **The alternative it beats:** reusing *noFilterMatches*, which would blame filters that are not on.

### R3 — whether the search field names the scope

The Mac's is `Search “To Read”`. **Chosen: mirror it, curly quotes and all** — the phone already mirrors the Mac's sort labels and filter vocabulary verbatim, and a scoped search that does not say it is scoped is the sort of half-sentence the placeholder exists to prevent. **The alternative it beats:** leaving the stock placeholder, which is honest only until the reader forgets which scope they are in — which is precisely when the field is read.

### R4 — what the picker shows beside each name

**Chosen: the contract's own `count`.** It is what the Mac's sidebar shows (AC16) and it is the *scope's* size, which is what choosing a name is choosing between. **The alternative it beats:** no numbers, which makes the menu a list of names the reader has to open to size up — and the count is already in the payload, so the alternative is also the only one that needs work. **What is deliberately not shown anywhere:** `updatedAt` (decoded for completeness, drawn nowhere — no screen asks *when was this shelf last touched*).

### R5 — what a shelf deleted on the Mac does to an open scope

The Mac's own answer is *“That shelf no longer exists”* and a sidebar refresh; the phone cannot quote it, because the contract's 404 is **uniformly reason-free** by design (`ClientError.notFound`'s whole point is that a client cannot map what the Mac holds). **Chosen: a 404 while scoped leaves the scope (back to All Books, the prior sort restored) and surfaces one line of the phone's own: *That shelf is gone from the Mac.*** The list underneath refetches unscoped. **The alternative it beats:** staying scoped and showing an error page, which strands the reader in a scope that can never fill — and re-entering it from the picker, which refreshes on each load, is the natural way to learn the shelf is gone.

## Files

| File | What |
| --- | --- |
| `Tests/Fixtures/contract/*.json` (re-vendored) | the four updated goldens and the two new ones — **already re-vendored 2026-09-28**; this slice's first commit |
| `Musaeum/Core/API/ContractModels.swift` (edited) | `stringsOrEmpty` (the one documented exception); `Shelf`; `Shelves` (the `{ "shelves": … }` envelope); `MembershipResult` (`{ "book": … }`); `shelves: [String]` on `ContractBook` |
| `Musaeum/Core/API/MusaeumClient.swift` (edited) | `shelves()`, `addToShelf(shelfId:bookId:)`, `removeFromShelf(shelfId:bookId:)` — the membership request composed by one `membershipRequest(base:token:shelfId:bookId:adding:)` so a case reads its method and path |
| `Musaeum/Core/API/LibraryQuery.swift` (edited) | `shelf: Shelf?`; `LibrarySort.Field.shelfAdded` with the Mac's two labels; `options(inShelf:)`; `stored`'s guard against a persisted `shelf_added`; `LibraryEmptyState.shelfIsEmpty` |
| `Musaeum/Features/Library/LibraryScreen.swift` (edited) | the model's shelves state, probe, `openShelf`/`closeShelf` and the prior-sort memory; **the scope control in the narrowing row (F5, amended)**; the scoped placeholder; the notice row and the 404 exit path |
| `Musaeum/Features/Detail/ShelfChecklist.swift` (new) | the sheet: rows, checks, one toggle in flight, the failure line — `ShareSheet.swift`'s own precedent for a sheet living in its own file |
| `Musaeum/Features/Detail/BookDetailScreen.swift` (edited) | the *Shelves* row, the sheet item, and the toggle call into the model |
| `Musaeum/Core/Support/Probe.swift` (edited) | `ACTION=shelf` (open the scope, log `total` and the first ids, close) and `ACTION=shelf-toggle BOOK= SHELF=` (drive the model's own toggle, log membership before/after) |
| `Tests/MusaeumTests/ContractDecodeTests.swift` (edited) | the two new goldens decode; `shelves` absent → `[]` and `null` → `[]`; every other member still throws when absent |
| `Tests/MusaeumTests/ShelvesTests.swift` (new) | the request-shape and model cases, in `LibraryQueryTests`' idiom: the scope on every page, the default sort, the restore, the capability states, the toggle's method/path, the returned book, the failure surface |

**Ten files, two stages** — 7a carries the first six and 7b the last four (with `ShelvesTests` grown across both). Inside the house's ~10-file bound; `project.yml` is untouched because it globs `Musaeum/`.

## What must not move

- **The contract, `apiVersion` at 1, and the ten routes the client already speaks.** This slice adds three calls over routes that already existed; it reads no field the document does not name, and composes no body — the membership writes have no body at all.
- **CD3's inventory.** No new durable state: the scope is request state, the shelves list is fetched on load, the checklist holds nothing, and no position or membership is cached. A relaunch is unshelved, like a relaunch is unsearched.
- **Invariant 4, with exactly one exception**, named at the call site: `shelves` absent reads as `[]`. Every other member still throws when absent, and `shelves: null` — which the contract never sends — reads as `[]` rather than `nil`, because both spellings mean *this Mac reports no shelves*.
- **Invariant 12's chrome.** The title becomes a menu in place: same type, same padding, same measured band. No control is added, so `headerHeight` and the recede rule move for no reason and are re-measured only if they do.
- **The token's single home (invariant 10) and the reader.** No file in `Features/Reader/` changes; the report queue and the upload path are untouched.

## Acceptance criteria, each with its decider

The Mac spec's slice 6 has two criteria (AC34, AC35 there); this table is their decomposition, in this repo's own numbering.

| AC | Decided by |
| --- | --- |
| 1 | **Shelves appear only against a server whose `/api/shelves` answers 200** (Mac AC34): 404 → the picker and the checklist row are absent; unreachable → unknown, and nothing claims absence — stub-server cases over the three states (`ShelvesTests`) |
| 2 | The `shelves` and `membership` goldens decode strictly, and the re-vendored book fixtures' `shelves` member decodes (`ContractDecodeTests`) |
| 3 | **`shelves` is the one member whose absence is not a refusal** — absent → `[]`, `null` → `[]`, and the existing absent-refusal list is unchanged (`ContractDecodeTests`) |
| 4 | A chosen shelf rides **every** request that carries the narrowing: page one, page two, a search's pages, and the facets call — a stub-server case reading `shelf` off every recorded request, and a case that the term and the filters are unchanged beside it (`ShelvesTests`) |
| 5 | Inside a shelf the sort is `shelf_added`/`desc` by default and is sent explicitly; leaving restores the sort that was on; the persisted key is never `shelf_added` (`ShelvesTests`, over `LibraryModel`) |
| 6 | The sort menu offers the two *Date Added to Shelf* pairs only inside a shelf, and `stored()` refuses a persisted one (a case per half — `ShelvesTests`) |
| 7 | An empty shelf draws its own screen and sentence, never *the Mac reports no books* or *these filters matched none* (`LibraryEmptyState.of` cases) |
| 8 | The search field names the scope, in the Mac's own copy (`ShelvesTests`, over the placeholder rule) |
| 9 | A toggle is exactly one `PUT` (adding) or one `DELETE` (removing) on `api/shelves/{id}/books/{bookId}`, no body — cases reading method and path off `StubURLProtocol.requests` (`ShelvesTests`) |
| 10 | The checklist refreshes from the returned book, not from a local flip — a stub whose answer's `shelves` differs from the request's expectation (`ShelvesTests`) |
| 11 | A failed toggle surfaces the error's own sentence, leaves the checklist as it was, and is retryable — cases for 503 `library offline` and for unreachable (`ShelvesTests`) |
| 12 | **Scoping, the default sort, and the checklist work against a live Mac, and a toggle made on the phone appears in the Mac's sidebar** (Mac AC35): the probe run over the Mac's own profile — the scope's `total` equal to the shelf's `count`, the first ids those the Mac's `shelf_added` order yields, and a toggle read back on both sides. **The frames that need a tap are the owner's**, named as such: the picker open, the checklist open, a check changing under a finger |

## Verification plan

Gates, run from this repo: `xcodegen generate` **first** (a file added since the last generate is not in the target, and a green total that has not moved is not evidence), then `xcodebuild build` and `xcodebuild test`, reporting the **per-suite** counts rather than the total.

**The destination has moved, verified 2026-09-28:** `DE0B5601-…` (iPhone 17 Pro / iOS 26.1 — the id in `AGENTS.md` and the README) **no longer exists**; this machine's runtimes are 18.3.1 and 27.0, and the gates ran green on `39D29C73-B2DD-4041-8ECD-46923376D0F9` (iPhone 18 Pro / iOS 27.0) — the id this repo's history already names. Until those two files are corrected they are stale, and the correction is a one-line edit each.

**The tree this slice starts from: 191 cases across 24 suites, 0 failures** (measured 2026-09-28, after the re-vendor and one one-line fix it exposed — `testHealthDecodes` asserted `version == "0.1.0"` while the document has said `0.5.0` since the fixtures were last vendored; the assertion now reads the document's own value, and that fix plus the fixtures are this slice's first commit). Every stage ends green, and each stage's move is its own cases: reconcile the per-suite count against the cases the stage added.

Then, with the Mac up: `../musaeum/scripts/api-smoke.sh` against the same profile must stay **92 passed, 0 failed** — this slice changes no route, so a move there is a finding. Then the live probe (R-below): the Mac runs on the scratch profile the Mac plan's *Built — slice 5* describes (`rest_api_port` 8791, the two seed books, one shelf of two), with its base and token written into the probe profile the client reads (`$ROOT/base.txt`, `$ROOT/token.txt` — the script refuses to guess either, and it is right to). `TAG=shelf ACTION=shelf SHELF=<id>` drives 7a; `TAG=shelf-tag ACTION=shelf-toggle BOOK=<id> SHELF=<id>` drives 7b; both log lines go to `docs/evidence/slice7/`.

**What the probe cannot do, stated rather than implied:** it drives the models' own calls — `simctl` can present no menu and tap no check. The picker's appearance, the checklist's sheet and a check moving under a finger are **human frames**, and AC12 carries only the half the instrument can decide: the requests the app composed, the pages they returned, and a membership read back on the Mac (`shelves.json` and the sidebar).

## Start here

```bash
cd ../musaeum-ios
git log --oneline -3
xcodegen generate
DEV=39D29C73-B2DD-4041-8ECD-46923376D0F9   # iPhone 18 Pro / iOS 27.0 — see the note above
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test
../musaeum/scripts/api-smoke.sh --profile <the Mac probe profile>
TAG=shelf ACTION=shelf SHELF=<id> ./scripts/live-probe.sh
```

**The Mac side is not involved and must not be touched.** No route changes, no document edits — the fixtures re-vendor *from* the document and change nothing in it. The Mac app is the thing the slice reads and writes against, and its plan (`../musaeum/docs/superpowers/plans/2026-09-28-bookshelves-slice5.md`) is where its own record lives.
