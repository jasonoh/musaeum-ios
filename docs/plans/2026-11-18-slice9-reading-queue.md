# Slice 9 — a reading queue, moved from the phone

**Date:** 2026-11-18
**Slice:** 9 in this repo — the reading-queue workstream's **slice 4**, the phone. The wire is live: the Mac's slices 1–3 are on its `main` (`32919f9`) and this client is written against its document.
**Annex to:** `docs/specs/2026-09-22-client-v1-design.md`, settling the client half of the Mac design's **D7** (`../musaeum-macos/docs/superpowers/specs/2026-11-18-reading-queue-design.md`). The contract is `../musaeum-macos/docs/rest-api.md` — its `GET /api/shelves` entry, the `GET /api/library` `sort`/`shelf` rows, and `PUT /api/shelves/{id}/books/{bookId}/position`. **Nothing here restates the contract** (invariant 1) and nothing re-opens a CD.
**Read first:** `AGENTS.md` (all twelve invariants); the contract's three sections above; `../musaeum-macos/docs/invariants/shelves.md` → *Queues*; the Mac design's D7 (the phone), D8 (the older build) and AC15/AC16; `../musaeum-macos/scripts/api-smoke.sh`'s *reading queue* section — a working pair of the exact two calls this slice makes (and it confirms a queue opens with **no** `sort` param).

---

## What this slice is

1. **A queue opens in the Mac's order.** `openShelf` stops sending `sort=shelf_added&dir=desc` inside a queue — that explicit sort is `LibraryScreen.swift:419`, and it is exactly why the installed build showed a queue in *Date Added to Shelf* order (the Mac design's *Why*, last sentence). A queue opens sending **no sort at all**, so the contract's own default (`shelf_position` ascending) applies. A manual shelf keeps the explicit `shelf_added desc` slice 7a decided.
2. **A long-press surface exists, and inside a queue it offers two items:** **Move to Top** and **Move to End**, each one `PUT /api/shelves/{id}/books/{bookId}/position` with `{"to":"top"|"bottom"}`.
3. **The list re-queries after a move through `start()`** — the existing shelf re-query rule (the same door a sort, a filter or a keystroke takes), so the scope is kept and the on-screen list stays until the Mac's own new page lands.
4. **Against a Mac that lacks the route the menu is absent**, not disabled: a `404` on the move is read as *this Mac has no Move* — the contract's own sentence — and the menu withdraws for the rest of the session (a pull re-probes).

**Not this slice, by decision, not by omission:** drag-to-reorder on the phone (the Mac design's non-goal — "revived by wanting finer placement on the phone — a slice of its own"); creating, renaming or deleting a queue (the Mac's, the document's *Not in this version*); any per-book position (the rank is the page order); any change to `kind`'s decoding (invariant 4's three exceptions stay exactly three).

---

## F1 — the long-press surface: `.contextMenu` on the card (**chosen**)

**The choice.** The grid cell gains a SwiftUI `.contextMenu`: a press-and-hold on a book's cover inside a queue offers *Move to Top* and *Move to End*. Outside a queue, and against a Mac that has answered `404` to a move, **no `.contextMenu` is attached at all** — the modifier is inside an `if`, so there is no empty menu to open.

**Why.** This client has no per-book long-press surface today (`grep -rn contextMenu Musaeum` → nothing; the only menus are the sort picker at `LibraryScreen.swift:1045` and the scope picker at `:1105`), so the slice has to build one — and the brief's words *are* the description of a context menu. iOS's own idiom for "hold this item, act on it" is exactly this modifier, it needs no navigation, no state and no new screen, and it composes with the existing `Button { detail = book }` at `:1594` without touching what a tap does. It is also the phone's nearest analogue of the Mac's own surface for this operation, which is a right-click on a book card.

**The alternative it beat (a).** A menu *inside* `BookDetailScreen` — the shelf checklist's pattern. It is already a place with actions, and it would have needed no new surface at all. It lost because it puts two taps and a navigation in front of an operation whose whole point is a quick re-order *of the list you are looking at*: you would tap the book, push a screen, move it, come back, and re-find your place. The Mac offers this on the card for the same reason.

**The alternative it beat (b).** A sheet from the card. It lost on weight: a sheet for two buttons is a screen the reader must dismiss, and it would need its own model, its own failure sentence and its own probe seam.

**Reversal condition.** The owner reports that a hold is not discoverable (nothing on the screen says a book can be held). The cheap answer then is not a new surface but an affordance on the card — a glyph drawn in the corner of a card **inside a queue only** — which is a view change inside this same rule; a *menu* is what would have to be re-decided, and it would be re-decided as (a).

**Known limit, stated here so it is not discovered later.** A `.contextMenu` is a system presentation: `simctl` can neither hold a card nor photograph the popup. The menu's *content* and the *effect* of its items are decidable by a probe run through the app's own door; **the menu opening is the owner's frame**, like every other sheet in this repo's records.

---

## Readings this slice settles itself

Each is a reading the approved spec left to the builder (its D7 and *Left to the builder*), with the alternative it beats and the condition that would reverse it.

### R1 — how "the queue's own order" is encoded: **`sort` becomes optional, and `nil` is the Mac's order** (chosen)

`LibraryQuery.sort` (`LibraryQuery.swift:200`) becomes `LibrarySort?`. `nil` means **"this scope's own order — do not send a sort"**, and it is reachable in exactly one place: opening a queue (`ShelfScope.openingSort(for:)`). Every other path — a chosen sort, a manual shelf, the persisted *All Books* order — is non-`nil`, so `MusaeumClient.library(sort:direction:)`'s existing optional parameters (`MusaeumClient.swift:174-175`, which already omit a `nil`) are the whole wire change: `request(offset:)` at `:283` passes `query.sort?.wireField`.

- **Why.** The Mac's queue order is `shelf_position`, which this client deliberately does not own: it is not in `LibrarySort.Field`, it would have to be refused as a restored persisted sort (`stored()` at `LibraryQuery.swift:165` guards `shelf_added` for the same reason), and nothing may ever *send* it outside a shelf. Sending nothing is the only encoding that cannot get that wrong: the absence of a sort is not a value this client could persist, mis-send, or decode.
- **The alternative it beat.** Teach `LibrarySort` an eighth field, `.shelfPosition`, with the label `Queue Order`, and let the phone send `sort=shelf_position&dir=asc`. That is honest to the wire and needs no optional — but it makes the phone the author of an order the Mac owns, it needs a second inside-only guard in `stored()`, and a queue then opens by sending a sort that means "the order the Mac keeps anyway". Rejected on the same principle as `wireDirection`'s (`LibraryQuery.swift:51-55`): a request whose meaning is the server's default is a request that can drift from it.
- **Reversal condition.** A Mac build that orders a queue by something *other* than its position and does not default to it — then the phone must ask explicitly, and `.shelfPosition` becomes a field.

### R2 — the sort menu inside a queue: **Queue Order first, then the library's own eight, then the two shelf pairs**

The menu (`LibraryScreen.swift:1045`) keeps one picker and gains a first row, **Queue Order**, tagged `nil`. Choosing it returns the scope to the Mac's own order; choosing anything else sends that sort explicitly, exactly as today. The bar's label is `model?.query.sort?.barLabel ?? "Queue Order"` — the same words the Mac's own label map uses for `shelf_position` (`../musaeum-macos/src/types/book.types.ts:328`), so the two apps name one order one way.

- **Why the library sorts are offered at all.** The Mac's own sort control inside a queue also offers them (its D5), and a reader who wants *Title A–Z* of the queue is asking a question the wire answers. Refusing the menu a row the Mac has would be this client inventing a restriction.
- **What does not change.** A sort chosen inside a queue is still **never persisted as the library's sort** — that guard is `LibraryScreen.swift:317` (`if query.shelf == nil`), and it is already true; this slice adds the case that decides it, because AC15's follow-on names it and no case in this repo currently pins it *inside a shelf*.

### R3 — the items' words: **Move to Top / Move to End**, though the Mac's menu says *Move to Bottom*

D7 and AC16 both say *End*, and the brief repeats it, so that is the phone's word. The Mac's own context menu says **Move to Bottom** for the same operation. The divergence is one word for one order, is the spec's, and is recorded here rather than silently harmonised: a phone row that read *Bottom* would be following the Mac and breaking the criterion that names it.

### R4 — how the route's absence is learned: **from the route's own `404`, not from an up-front probe**

The menu is offered when the open scope is a queue **and** the Mac has not answered `404` to a move in this session. A `404` sets `QueueMoveRoute.unavailable` and the menu withdraws; a successful `200` sets `.available`; a fresh `GET /api/shelves` that reports any queue resets it to `.unknown` — because the wire's `kind` and the route landed in **one** Mac slice, so a Mac that serves a queue serves the route, and the reset is what makes a withdrawal self-healing after a pull.

- **Why not an up-front probe.** The only request that distinguishes the route's presence from a resource's absence is a move with a deliberately malformed body (`400` where the route exists, `404` where it does not, nothing written either way — the contract's refusal order makes that true). That is a write-shaped request on every queue open, for a case no shipped build can be in: the discriminating state is *a Mac with queues and no route*, and the wire has never shipped that.
- **A `404` from a book that has **left the queue** (the contract's step 5) is indistinguishable on the wire from a missing route, so such a race reads as *this Mac can't move* and withdraws the menu until the next pull re-probes.** The alternative — reading the book's own `shelves` ids to tell a non-member from a missing route — narrows it but cannot close it (the payload can be stale by the same race), and it buys a rule that is wrong in the other direction when the two disagree. Accepted, one sentence in the record.
- **A `404` from a *deleted shelf* is the third reading of the same code, and the build does not take it on trust (added during the review, 2026-11-18).** The contract answers an unknown shelf on this route with the same uniform 404, so the move's 404 path also **re-reads the scope through `start()`**: if the queue has been deleted, the existing scoped-404 rule leaves it and replaces the sentence with *“Up Next” is gone from the Mac.*; if it has not, the list is simply read again and the route sentence stands. The plan had not named this case and would have stranded the reader on a dead queue under a sentence about the Mac.
- **Reversal condition.** Any Mac build that carries queues and not this route — then the up-front probe becomes necessary and gets built.

### R5 — what a failed move says: **one sentence in the scope's own notice row** (CD7)

`LibraryModel.scopeNotice` is already the surface for *what the scope needs to say* (`:53`, drawn in the chrome band). A move that fails for any reason other than the missing route puts the error's own sentence there; a missing route puts **one plain sentence** there and withdraws the menu:

- refused: `Couldn't move that book — <the Mac's own sentence>` (the `ClientError.description` every other surface uses);
- route absent: `This Mac can't move books in a queue.`

- **Why.** CD7 — failure is a surface, not a dialog. And a menu that silently withdraws after a tap is a worse surface than a sentence: the reader acted and the screen changed with nothing saying why.
- **The alternative it beat.** A per-item disabled state, or a toast. Disabled contradicts the brief and the contract (*absent, not disabled*); a toast is a surface this app does not have and would introduce for one line.

### R6 — the re-query after a move: **`start()`, so the grid rebuilds at its top**

The move's refresh is `await start()` — the same funnel a sort, a filter or a keystroke takes, which keeps the scope (`query.shelf` untouched), keeps the on-screen list until the new page lands (`isRefreshing`, `:74`), and lands as a new list keyed by `landed` (`:200`), which puts the grid back at its top.

- **Why not a bespoke reload.** The grid's identity is `model.landed` (`:1572`) precisely so a landed page is a *new* list whose cells re-ask their covers; a second reload path would either duplicate that discipline or lose it.
- **Consequence to state, not to fix here.** *Move to End* leaves the reader looking at the top of the queue, not at the book they moved. That is what every re-query does today, and the two items are the ends — but it is a real wrinkle, so it is written down. **Deferred, revived** by the owner reporting the jump: the fix is a `scrollTo` on the moved book through the existing `ScrollViewReader` at `:1561`, which needs a target the model can name after a landing and is its own small change.

---

## Files

| File | What it carries |
| --- | --- |
| `Musaeum/Core/Library/ShelfScope.swift` **(new, ~60 lines)** | The pure rules, so a case reaches them without a view: `QueueMoveRoute` (`.unknown/.available/.unavailable`), `ShelfMoveEdge` (`top`/`bottom`, with its wire value), `ShelfScope.isQueue(_:)`, `ShelfScope.openingSort(for:)` (nil for a queue, `shelf_added desc` otherwise) and `ShelfScope.offersMove(in:route:)`. |
| `Musaeum/Core/API/LibraryQuery.swift` | `sort` becomes `LibrarySort?` (R1). **As built, `LibrarySort.options(inShelf:)` is untouched** — the queue's *Queue Order* row is a menu row whose tag is `nil`, so it is not a sort and does not enter this list. `stored()` untouched. |
| `Musaeum/Core/API/MusaeumClient.swift` | `moveRequest(base:token:shelfId:bookId:to:)` — composed where a case can read method, path and body — and `moveInShelf(shelfId:bookId:to:)` answering the `{ "book": … }` payload the membership routes already decode (`MembershipResult`). Nothing else moves: `library(sort:direction:)` is already optional. |
| `Musaeum/Features/Library/LibraryScreen.swift` | `openShelf` via `ShelfScope.openingSort` (`:415`); `request(offset:)` sending `query.sort?` (`:283`); the page log line's `sort=` reading `shelf-default` when nil (`:211`); `sortMenu`'s `nil` row and label (`:1045`, `:1057`); `moveRoute` + `move(_:to:)` on the model, with R5's sentences; the cell's conditional `.contextMenu` (`:1594`); the probe seam's `shelf-move` action (`:1347`). |
| `Musaeum/Core/Support/Probe.swift` | Two variables: `moveBookID` (`MUSAEUM_PROBE_MOVE_BOOK`) and `moveTo` (`MUSAEUM_PROBE_TO`). Its own variables, not `OPEN`: opening a book would cover the very list the move is read on. |
| `scripts/live-probe.sh` | `ACTION=shelf-move` with `MOVE_BOOK=` and `TO=`; and, under the existing `SHELF=` block, the Mac's **own queue order** (`select book_id … order by position`) beside the phone's `first=`. |
| `scripts/stub-old-mac.py` **(new, ~80 lines)** | The instrument for AC16's absence half: a server that serves health, one library page and a shelf list **carrying a queue**, and answers `404` to the position path — a Mac that has queues and not the route, which is the only state the 404 reading exists for. |
| `Tests/MusaeumTests/QueueMoveTests.swift` **(new, ~9 cases)** | The move request's shape and body; a 200 followed by a scoped re-query with no `sort` and the new order showing; a 404 withdrawing the menu and saying so; a 400/503 saying the Mac's own words and leaving the route available; a queue opening with no sort and a manual shelf with `shelf_added:desc`; a sort chosen inside a queue never persisted; `ShelfScope`'s four rules. |
| `Tests/MusaeumTests/ShelvesTests.swift` | Reconciled, not weakened: the re-vendored golden now carries **two** shelves, so the helper at `:51` and the assertion at `:115` learn the queue's id, and the queue is the second row. |
| `Tests/MusaeumTests/ContractDecodeTests.swift` | `:197`'s `count == 1` becomes 2, and a case says what the second row is: `kind == "queue"` decodes, strictly, into the same `Shelf`. |
| `Tests/MusaeumTests/LibrarySortTests.swift` | **As built: only the optional sort.** The plan gave it the `nil` row to learn; the build kept **Queue Order** out of `LibrarySort.options` (it is a menu row, not a sort), so the contract-vocabulary guard stays exact and this file changes only where `query.sort?` forced it — plus two assertions naming what `nil` and an unasked sort each mean. |
| `Tests/Fixtures/contract/shelves.json` | Re-vendored (`MUSAEUM_DOC=../musaeum-macos/docs/rest-api.md scripts/vendor-contract-fixtures.sh`). Measured today: it moves **only** this file, by +7 lines — the queue entry the document has carried since the Mac's slice 3, which this repo's copy predates. |

**Honest count: 12 code/test/instrument files** — five app files (one new), four test files (one new), the two scripts and the fixture. **Three of the twelve are reconciliations the re-vendored golden forces, not new surface**, and the brief's *around ten* is about the slice's own code; this is 6 new/edited app+script files and 4 test files. Docs are the annex, this repo's record, `tasks.md`, `CHANGELOG.md` and `docs/evidence/reading-queue/`.

---

## What must not move

- **No contract change and no Mac-repo edit** (invariant 1; the wire is landed).
- **`kind` stays a plain `String`** (`ContractModels.swift:443`), and invariant 4's three exceptions stay exactly three — this slice adds no tolerant reader.
- **`apiVersion` stays 1**, and no route is added: one route is *consumed*.
- **`LibrarySort.stored()`'s guard is unchanged** — it still refuses a stored `shelf_added`, and `nil` is never stored (the persisted key is outside a shelf only).
- **The manual shelf's behaviour is byte-identical**: `sort=shelf_added&dir=desc`, sent explicitly (slice 7a's own reading).
- **The tap's meaning**: a card still opens the book's detail. The context menu is an addition, not a replacement.
- **The header's recede rule, the cover box, the download store, the reader** — untouched.

---

## Acceptance criteria, each with its decider

Slice 9's own criteria are the client half of the Mac design's **AC16** and the follow-on of **AC15**; the numbering below is this annex's.

| AC | Criterion | Decided by |
| --- | --- | --- |
| 9.1 | **A queue opens sending no `sort` and no `dir`**, and the list shows the Mac's own order | `QueueMoveTests` — the stub records the scoped request and asserts `sort` and `dir` are **absent** from its query, and the page it serves lands in the order served. **Live:** `ACTION=shelf SHELF=q-1` reads `sort=shelf-default` and `first=Charlie \| Alpha \| Bravo` — the Mac's `shelf_books.position` order (0,1,2) |
| 9.2 | **A manual shelf still opens on `shelf_added desc`, sent explicitly** | `QueueMoveTests` — the same recorder, the manual path: `sort=shelf_added`, `dir=desc` present |
| 9.3 | **Inside a queue the Move items exist and work**: `{"to":"top"}`/`{"to":"bottom"}` reach the route, and the list shows the new order with the scope kept | `QueueMoveTests` — the move request's method, path and body (key set exactly `["to"]`), then the re-query is the *same* scoped query with no sort. **Live:** `ACTION=shelf-move SHELF=q-1 MOVE_BOOK=b2 TO=top` reads `first=Bravo \| Charlie \| Alpha`, and the script's own `shelf_books` read agrees; `TO=bottom` puts it back |
| 9.4 | **A sort chosen inside a queue is not persisted as the library's** (AC15's follow-on) | `QueueMoveTests` — a `persistSort` spy: open a queue, choose `title:asc`, close; the spy recorded **nothing**, and the bar returns to the prior sort |
| 9.5 | **The sort menu offers Queue Order first inside a queue and not outside one** | the **rule** by `QueueMoveTests` (a queue opens with `sort == nil`; a manual shelf with `shelf_added desc`), and the menu's row list by `ShelfScope.openingSort` — the row's own tag **is** that value. A menu's rows are a frame's business (`simctl` opens none), so the row as drawn joins the popup in the owner's frame |
| 9.6 | **Against a Mac that answers 404 to the move, the menu is absent — not disabled — and says so once** | `QueueMoveTests` (a 404 sets `.unavailable`; `ShelfScope.offersMove` then returns false; `scopeNotice` names it) **and live:** `ACTION=shelf-move` against `scripts/stub-old-mac.py` reads `move-menu=offered` → `shelf move … 404` → `move-menu=absent`, with the frame showing the queue unchanged |
| 9.7 | **A move refused for any other reason says the Mac's sentence and leaves the menu in place** | `QueueMoveTests` — a 503: `scopeNotice` carries the error's description, the menu stays offered, the list is not re-queried, and a second attempt is a second call. The `400` (a manual shelf) is decided by the guard that **stops it being composed at all** — `testAMoveOutsideAQueueIsNeverAttempted` asserts no request was made, so the contract's 400 is never heard |
| 9.8 | **The wire carries no position and nothing new on the book payload** | `ContractDecodeTests` unchanged in this respect, plus the vendored goldens: `git diff Tests/Fixtures/contract/` after re-vendoring touches **only** `shelves.json`, additively |

---

## Verification plan

1. **Gates first:** `xcodegen generate`, then build and test per `AGENTS.md`. Baseline on the committed tree **338 cases / 36 suites** (measured 2026-10-14); this slice's own cases are the number the total must move by, reconciled per suite — and read the per-suite line, because a file written after `xcodegen generate` is not in the target while the gate reads green.
2. **Mutation-check the new criteria** with the repo's own runner (one mutant per criterion that has a test decider, each named with its anchor and the suite that must redden), and read *which case* went red rather than only how many.
3. **Live probes** against the scratch profile already on this machine (`~/.hermes/profiles/dev/cache/scratch/s3pass`, port **8799**, `127.0.0.1` — three books, queue `q-1` ordered `b3,b1,b2`, manual shelf `s-1`): the control, the two legs, and the stub run. **The owner's packaged app holds 8788/8789 and is never touched or signalled.**
4. **Restore what the runs moved:** the two legs are each other's inverse; the run that ends the pair leaves `q-1` as `b3,b1,b2`, read back from `shelves.json` *and* `shelf_books`.
5. **Evidence committed** under `docs/evidence/reading-queue/`: the run logs, the frames, the stub's own log, and what no run decided (the popup itself — a human hold).

## Start here

```bash
cd ~/Projects/musaeum-ios
git log --oneline -3          # 4477e9a at the annex's writing
git status --short            # must be empty but for this annex and the re-vendored fixture
xcodegen generate
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=6CF68F43-7AFB-4651-A166-20F112210DA0" -derivedDataPath ./DD test   # 338 / 36 on the untouched tree
```

Then, in order: `Musaeum/Core/Library/ShelfScope.swift`, `Musaeum/Core/API/LibraryQuery.swift`, `Musaeum/Core/API/MusaeumClient.swift`, `Musaeum/Features/Library/LibraryScreen.swift`, then the tests and the probes.

---

## Built — 2026-11-18

Landed as this plan wrote it, with four deviations recorded where they happened (the `LibrarySortTests` row above states the largest: **Queue Order** is a menu row, not a sort, so the contract-vocabulary guard did not have to learn an exception). The record — gates, the 11-row campaign with the cases each mutant reddened, the four probe readings and what is handed to the owner — is *Built — slice 9* in `docs/specs/2026-09-22-client-v1-design.md`; the readings themselves are `docs/evidence/reading-queue/`.

**Gates on this tree:** `xcodebuild build` exit 0; `xcodebuild test` exit 0 — **347 cases, 0 failures, 37 suites** (from 338 / 36; the move is this slice's own 9 cases). **Campaign: 11 mutations, 11 killed, every row restored sha256-identical**; and after the review pass, **a twelfth row** (a successful move leaving the previous failure's sentence standing) killed by exactly the case that names it. **Probes:** a queue open reads `sort=shelf-default` and the Mac's order; `Move to Top` and `Move to End` on one book are each other's inverse and the queue ends where it began; and against a Mac that 404s the route the menu reads *offered → absent* with one sentence on screen.

**Two things the review changed:** a successful move now clears the sentence an earlier failure left (a real defect it found, fixed with two assertions and a mutation row of its own), and the bar no longer says *Queue Order* before a model exists (found by the review and already fixed in flight; no case can decide it, so it is recorded rather than claimed).

