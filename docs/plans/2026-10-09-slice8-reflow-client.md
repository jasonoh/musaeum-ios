# Slice 8 — a PDF-only book reads on the phone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the Mac says a book is `reflow.available`, the phone asks for `format=reflow`, polls the Mac's pass to its end, saves the EPUB it gets as `{id}.epub`, and opens it through the existing `EPUBNavigatorViewController` — with no engine change.

**Architecture:** The contract is the Mac's and already landed (`../musaeum-macos/docs/rest-api.md`, `#### format=reflow`, merged to the Mac's `main` 2026-10-09). This slice is the client half: a `Reflow` member on `ContractBook`, a pure `DownloadPlan` rule deciding which file to ask for, a polling `downloadReflow` on `MusaeumClient`, and a detail-screen model that shows the pass's progress. `DownloadStore.adopt` is untouched: it already names the local file `{id}.{format}`, and the format passed for a reflow is `epub` (invariant 2 — the file's name is this app's business).

**Tech Stack:** Swift 6, SwiftUI, XCTest, `URLProtocol` stub (`Tests/MusaeumTests/StubURLProtocol.swift`), XcodeGen.

**Spec:** the Mac's `docs/superpowers/specs/2026-10-07-pdf-reflow-reader-design.md` (D1, D8, D10, slice 4 row), its plan `docs/superpowers/plans/2026-10-09-pdf-reflow-slice-4.md` (Owner decisions + `What the phone inherits`), and this repo's `docs/specs/2026-09-22-client-v1-design.md` (CD1–CD8). The wire is `../musaeum-macos/docs/rest-api.md` — never restated here (invariant 1).

## Global Constraints

- Invariant 1: models and fixtures derive from the Mac's document; run `MUSAEUM_DOC=/Users/oh/Projects/musaeum-macos/docs/rest-api.md scripts/vendor-contract-fixtures.sh` (this machine's Mac checkout is `../musaeum-macos`, not `../musaeum`). Nothing here hand-writes a payload the document owns.
- Invariant 2: the wire carries no path; the local file is `{id}.epub` for a reflow, built by `DownloadStore.adopt(... format: "epub")`.
- Invariant 3: the fraction is the only position that travels — the reader reports `percent` of the reflowed EPUB; nothing new.
- Invariant 4: every always-present member throws when missing. **One deliberate exception, ruled below:** `reflow` (the second after `shelves`).
- Invariant 5: the server is never a dependency; 202, 422, 404, 503 are ordinary states with a surface, never a crash or a dialog nobody can act on. Reading a downloaded book works with all of them true.
- Invariant 6: `503 busy` is retried honouring `Retry-After`; a poll is not a fan-out — one request in flight per book, at most one reflow download at a time per detail screen.
- Invariant 10: no token in a log or error message.
- Conventions: Swift 6 language mode, `@MainActor` view models, async/await, one type per file, a pure rule in its own file, networking only through `MusaeumClient`, markdown prose not hard-wrapped.
- Gates: `xcodegen generate` first; build and test per `AGENTS.md` (destination by `id`, `DEVELOPER_DIR` exported). Baseline before this slice: **191 cases, 0 failures, 24 suites** — verify on the untouched tree first and report the real number; reconcile a moved total against the cases added.

## Rulings (recorded, to be confirmed by the owner)

1. **`reflow` is read tolerantly — `ContractBook.reflow` is `Reflow(available: false)` when the key is absent or `null`.** Why: every download stores the server's payload verbatim and decodes it through the strict decoder on each open (`DownloadedBook.book()`); every payload stored before this slice lacks `reflow`, and a required read would make every existing download fail to open — the same failure `shelves` hit and the same exception (`StrictObject.stringsOrEmpty`). A *present* `reflow` is still strict: a malformed value throws. Cost if wrong: a Mac that forgot the member reads as "no reflow", i.e. today's behaviour.
2. **Eligibility trusts the payload, not the formats.** `DownloadPlan` reads `reflow.available`; it does not re-derive "PDF and no EPUB" from `formats` (the Mac's rule is the server's own, as `preferredFormat` already trusts the server's order).
3. **The poll's deadline is 25 minutes** (the Mac's pass deadline is 20; the extra five cover queueing), after which the transfer fails with a sentence, not a hang. The poll honours `Retry-After` on 202 clamped to 1–10 s and defaults to 2 s.
4. **A 422 is terminal for this attempt** and shows the Mac's own `reason`; the phone does not retry automatically (the Mac remembers a refusal for 60 s and the user can tap again). The ~10 % image-only books stay unreadable on the phone — accepted for v1 (Mac spec open question 4).

## Review Focus

1. **A 202 is never adopted as a book.** `download(id:format:)` treats every 2xx as success; routing a reflow through it would save the 202's JSON body as `{id}.epub`. The reflow has its own method and a test that a 202 body never reaches `adopt`.
2. **A pre-reflow stored payload still opens.** A `DownloadedBook` whose payload has no `reflow` key decodes (`available == false`); a payload with a malformed `reflow` throws.
3. **Cancellation:** leaving the detail screen mid-pass cancels the poll (no orphan loop hammering the Mac); the Mac's pass keeps running and the next open joins it.
4. **The library of 1,798 PDF books:** the `reflow` member must not change any existing fixture-driven decode; `formats.first` stays the choice for every book with `reflow.available == false`.
5. **Offline mid-poll** (`503 library offline`, unreachable): the transfer fails with the existing sentence, the book is not half-adopted, a retry starts cleanly.

---

## File Structure

- Modify `Musaeum/Core/API/ContractModels.swift` — `Reflow`, `ContractBook.reflow`, `StrictObject.objectOrDefault`-style tolerant read (one helper), `ReflowProgress`, `CannotReflowPayload`.
- Create `Musaeum/Core/Store/DownloadPlan.swift` — the pure rule.
- Modify `Musaeum/Core/API/MusaeumClient.swift` — `ClientError.cannotReflow`, `downloadReflow`, the 422 mapping.
- Modify `Musaeum/Features/Detail/BookDetailScreen.swift` — `Transfer.preparing`, the plan, the progress line.
- Vendored: `Tests/Fixtures/contract/*.json` (regenerated by the script).
- Tests: `Tests/MusaeumTests/ContractDecodeTests.swift` (modify), `Tests/MusaeumTests/DownloadPlanTests.swift` (create), `Tests/MusaeumTests/ReflowDownloadTests.swift` (create), `Tests/MusaeumTests/ReflowDetailModelTests.swift` (create).
- Docs: `tasks.md`, `AGENTS.md` (gate counts), `CHANGELOG.md`, `docs/what-works-today.md`.

`DownloadStore.swift` is **unchanged** (the Mac plan's file list named it; reading it shows `adopt` already takes the format).

---

### Task 1: The member, the plan, and the fixtures

**Files:**
- Modify: `Musaeum/Core/API/ContractModels.swift`
- Create: `Musaeum/Core/Store/DownloadPlan.swift`
- Modify: `Tests/MusaeumTests/ContractDecodeTests.swift`
- Create: `Tests/MusaeumTests/DownloadPlanTests.swift`
- Vendored: `Tests/Fixtures/contract/*.json`

**Interfaces:**
- Produces: `struct Reflow: Decodable, Equatable, Hashable, Sendable { let available: Bool }`; `ContractBook.reflow: Reflow`; `enum DownloadPlan: Equatable, Sendable { case reflow; case format(String); static func of(_ book: ContractBook) -> DownloadPlan? }` (`nil` when the book has neither `reflow.available` nor any format); `struct ReflowProgress: Decodable, Equatable, Sendable { let phase: String; let completed: Int; let total: Int }`; `struct CannotReflowPayload: Decodable, Equatable, Sendable { let error: String; let reason: String }`.

- [ ] **Step 1: Vendor the fixtures.** Run `MUSAEUM_DOC=/Users/oh/Projects/musaeum-macos/docs/rest-api.md scripts/vendor-contract-fixtures.sh`. Expected: the nine payloads re-vendored; `git diff --stat Tests/Fixtures` shows `book.json`, `library.json`, `membership.json`, `reading.json`, `import.json` gaining a `reflow` member and nothing else. If anything else moved, stop and report.

- [ ] **Step 2: Write the failing tests** in `ContractDecodeTests.swift` (follow that file's fixture helper and style):

```swift
func testBookFixtureCarriesReflow() throws {
    let book = try JSONDecoder().decode(ContractBook.self, from: fixture("book"))
    XCTAssertEqual(book.reflow, Reflow(available: false))
}

/// **Every payload stored before this slice lacks the key**, and downloads decode their stored payload on every open.
func testAPayloadWithoutReflowStillDecodesAsNotAvailable() throws {
    var object = try JSONSerialization.jsonObject(with: fixture("book")) as! [String: Any]
    object.removeValue(forKey: "reflow")
    let data = try JSONSerialization.data(withJSONObject: object)
    XCTAssertEqual(try JSONDecoder().decode(ContractBook.self, from: data).reflow.available, false)
    object["reflow"] = NSNull()
    let nulled = try JSONSerialization.data(withJSONObject: object)
    XCTAssertEqual(try JSONDecoder().decode(ContractBook.self, from: nulled).reflow.available, false)
}

func testAPresentButMalformedReflowThrows() throws {
    var object = try JSONSerialization.jsonObject(with: fixture("book")) as! [String: Any]
    object["reflow"] = ["available": "yes"]
    let data = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try JSONDecoder().decode(ContractBook.self, from: data))
    object["reflow"] = [String: Any]()
    let empty = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try JSONDecoder().decode(ContractBook.self, from: empty))
}
```

`DownloadPlanTests.swift`: build `ContractBook` values by decoding the `book` fixture with `formats` and `reflow` overridden through `JSONSerialization` (a small private helper `book(formats:[String], reflow: Bool)`), then assert: `reflow=true, formats=["pdf"]` → `.reflow`; `reflow=true, formats=["mobi","pdf"]` (order as the wire gives it) → `.reflow`; `reflow=false, formats=["epub","pdf"]` → `.format("epub")`; `reflow=false, formats=["pdf"]` → `.format("pdf")` (the status quo for an image-only book the Mac says it cannot reflow? no — `available` is eligibility, so this is the pre-slice Mac case); `reflow=false, formats=[]` → `nil`.

- [ ] **Step 3: Run to see them fail.** `xcodegen generate`, then the test command from `AGENTS.md` filtered to the two suites (`-only-testing:MusaeumTests/ContractDecodeTests -only-testing:MusaeumTests/DownloadPlanTests`). Expected: build error / failures (symbols missing).

- [ ] **Step 4: Implement.** In `ContractModels.swift`, next to `stringsOrEmpty`, add a documented sibling (name it `objectOrDefault`) with the same comment form as `stringsOrEmpty`, naming `reflow` as the second deliberate exception and why (stored payloads):

```swift
    /// **The second deliberate exception to the always-present rule (invariant 4).**
    /// `reflow` is absent from every payload a download stored before slice 8, and a download decodes its
    /// stored payload on every open — a required read would make each of them unopenable. Absent and `null`
    /// read as the default; a *present* member is still strict.
    func objectOrDefault<T: Decodable>(_ key: String, default fallback: T, as: T.Type = T.self) throws -> T {
        let codingKey = AnyCodingKey(key)
        guard container.contains(codingKey) else { return fallback }
        if (try? container.decodeNil(forKey: codingKey)) == true { return fallback }
        return try value(key, as: T.self)
    }
```

Add `struct Reflow` (decoded with `StrictObject(... path: "book.reflow")`, `available = try o.bool("available")`, with an `init(available:)` memberwise for tests/default), `let reflow: Reflow` on `ContractBook` read as `try o.objectOrDefault("reflow", default: Reflow(available: false))`, and the two payload structs (`ReflowProgress` via `StrictObject` path `"reflow progress"`, `CannotReflowPayload` path `"cannot reflow"`). Create `DownloadPlan.swift`:

```swift
/// Which file the phone asks the Mac for. **One rule, trusting the Mac's own** (`reflow.available`, which the
/// server derives as "a PDF and no EPUB"): the phone does not re-derive it from `formats`, as it does not
/// re-derive `formats`' preference order.
enum DownloadPlan: Equatable, Sendable {
    case reflow
    case format(String)

    static func of(_ book: ContractBook) -> DownloadPlan? {
        if book.reflow.available { return .reflow }
        return book.preferredFormat.map(DownloadPlan.format)
    }
}
```

- [ ] **Step 5: Run the two suites** — expect PASS — then the whole test command: the total moves by exactly the cases added and nothing else fails.

- [ ] **Step 6: Commit** (`git add` the named files only; the vendored fixtures included):

```bash
git commit -m "feat(contract): the reflow member, and the plan that reads it

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The polling download

**Files:**
- Modify: `Musaeum/Core/API/MusaeumClient.swift`
- Create: `Tests/MusaeumTests/ReflowDownloadTests.swift`

**Interfaces:**
- Consumes: `ReflowProgress`, `CannotReflowPayload` (Task 1); `fileRequest(id:format:)`, `session`, `mapStatus`, `retryAfter`, `ClientError.isRetryable` (existing).
- Produces: `ClientError.cannotReflow(String)` (description: `"the Mac could not make a readable copy of this PDF — \(reason)"`); `func downloadReflow(id: String, deadline: Duration = .seconds(25 * 60), pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, onProgress: @MainActor @Sendable (ReflowProgress) -> Void) async throws -> (file: URL, bytes: Int)`.

Behaviour (the contract's table, `#### format=reflow`): ask `fileRequest(id:, format: "reflow")` with `session.download(for:)`; **200** → return the temporary file and its size; **202** → decode the temp file's body as `ReflowProgress` (a body that does not decode is still a 202: report `ReflowProgress(phase: "start", completed: 0, total: 0)`), call `onProgress`, `pause` for `Retry-After` clamped to 1…10 s (default 2), and ask again; **422** → decode `CannotReflowPayload` and throw `.cannotReflow(reason)` (a body that does not decode throws `.cannotReflow("the Mac gave no reason")`); **every other status** goes through the existing `mapStatus` (404 → `.notFound`, 503 offline/busy as today — a retryable `busy` honours `Retry-After` up to the existing 2 retries, `libraryOffline` is thrown); a thrown transport error becomes `.unreachable` exactly as `download` does; `CancellationError` propagates untouched; when `deadline` of cumulative `pause` time is exhausted throw `.unreachable("the Mac did not finish preparing this book in time")`. The deadline counts *requested pauses*, not wall time, so tests can run it with an instant `pause`.

- [ ] **Step 1: Write the failing tests** in `ReflowDownloadTests.swift` using `StubURLProtocol.configure` with a counter-driven handler (pattern: `ClientTests.client(_:)`):
  - `testPollsThroughTwo202sThenReturnsTheBytes`: responses 202 `{"phase":"layout","completed":12,"total":24}` (header `Retry-After: 2`), 202 `{"phase":"layout","completed":24,"total":24}`, then 200 with body `PK…` bytes; assert the returned file contains those exact bytes, `onProgress` saw `[12/24, 24/24]` in order, the request path/query was `/api/books/<id>/file?format=reflow` every time with the bearer token, and `pause` was asked for 2 s twice (instant stub).
  - `testA202BodyIsNeverReturnedAsTheFile` (Review Focus 1): after 202,200 the returned file's bytes are the 200's, never the JSON.
  - `testA422ThrowsCannotReflowWithTheMacsReason`: 422 `{"error":"cannot reflow","reason":"no page carries a text layer"}` → `.cannotReflow("no page carries a text layer")`; a 422 with an empty body → `.cannotReflow("the Mac gave no reason")`; exactly one request was made (no automatic retry).
  - `testStatusesOutsideTheReflowTableKeepTheirOrdinaryMeaning`: 404 → `.notFound`; 503 `{"error":"library offline"}` + `Retry-After: 5` → `.libraryOffline(retryAfter: 5)`; 401 → `.unauthorized`.
  - `testRetryAfterIsClampedAndDefaulted`: `Retry-After: 3600` → pause of 10 s; `0` → 1 s; absent → 2 s.
  - `testTheDeadlineEndsAStuckPass`: a handler that answers 202 forever with `pause` recording requested durations → throws `.unreachable` once cumulative pauses reach the deadline, and makes a bounded number of requests (assert `<= deadline/pause + 1`).
  - `testCancellationStopsThePoll`: run in a `Task`, cancel after the first 202 with a `pause` that suspends on `Task.sleep` — the call throws `CancellationError` and no further request is made after cancel.

Run → FAIL (symbols missing).

- [ ] **Step 2: Implement** `downloadReflow` and the `cannotReflow` case (extend `description`, and leave `isRetryable` false for it — find the switch and make the exhaustive case explicit, not a `default`). Reuse `mapStatus` for the rest; do not touch `download(id:format:)`. Keep the temp-file handling the same as `download` (the caller owns the returned file; a 202/422 temp file is read then discarded with `try? FileManager.default.removeItem`).

- [ ] **Step 3: Run the suite** → PASS; whole test command green with the total reconciled.

- [ ] **Step 4: Commit** `feat(client): downloadReflow — poll the Mac's pass to its end`.

---

### Task 3: The detail screen

**Files:**
- Modify: `Musaeum/Features/Detail/BookDetailScreen.swift`
- Create: `Tests/MusaeumTests/ReflowDetailModelTests.swift`

**Interfaces:**
- Consumes: `DownloadPlan.of`, `MusaeumClient.downloadReflow`, `ClientError.cannotReflow`, `DownloadStore.adopt`.
- Produces: `BookDetailModel.Transfer.preparing(ReflowProgress?)` (the case sits between `.working` and `.done`; `ReflowProgress` is `Equatable`); the model's `download(_:)` branching on the plan; a UI line `"Preparing a readable copy… 12 of 24 pages"` (`"Preparing a readable copy…"` while `total == 0`), the existing disabled state and spinner treating `.preparing` like `.working`.

Behaviour: `download(_ book:)` — `guard let plan = DownloadPlan.of(book)` else the existing "holds no format" failure. `.format(let f)` → today's code path, byte for byte. `.reflow` → `transfer = .preparing(nil)`; fetch `bookData` first (as today); `downloadReflow(id:, onProgress: { transfer = .preparing($0) })`; cover thumb as today; `downloads.adopt(temporaryFile:payload:book:format: "epub", cover:)`; `transfer = .done`. On `ClientError` → `.failed(error.description)` (the `cannotReflow` description is the surface for a 422); on cancellation → `transfer = .idle` and nothing adopted; **nothing is adopted unless the 200's file arrived** (Review Focus 5). Add `Probe.log` lines in the style of the existing ones (`reflow downloaded book=… bytes=… pages=…`), never the token.

- [ ] **Step 1: Write the failing tests** in `ReflowDetailModelTests.swift` (`@MainActor`, `DownloadStore(root: <temp dir>)`, `StubURLProtocol`-backed client; stub `GET /api/books/<id>` → the `book` fixture body edited to `formats:["pdf"]`, `reflow.available:true`; `GET …/file?format=reflow` → 202, 200 with fake bytes; `GET …/cover?size=thumb` → 404 is fine):
  - `testAReflowDownloadIsAdoptedAsAnEpub`: after `await model.download(book)`: `model.transfer == .done`, `downloads.fileURL(for: id)?.lastPathComponent == "\(id).epub"`, the stored bytes equal the 200's, `downloads.downloaded(id)?.fileName` ends `.epub`, and the stored payload decodes with `reflow.available == true`.
  - `testProgressIsVisibleWhileThePassRuns`: record `model.transfer` from inside the stub's second request (or via an `onProgress` spy) and assert `.preparing(ReflowProgress(phase:"layout", completed:12, total:24))` was observed.
  - `testARefusedBookIsNotAdoptedAndSaysWhy`: 422 → `transfer == .failed(<description containing the Mac's reason>)`, `downloads.isDownloaded(id) == false`, the staging dir untouched (no stray file in `Books`).
  - `testAnOrdinaryBookStillDownloadsItsFirstFormat`: `reflow.available:false, formats:["epub","pdf"]` → one request with `format=epub`, none with `reflow`.
  - `testTheMacDroppingMidPassAdoptsNothing`: 202 then 503 `library offline` → `.failed`, nothing adopted, and a second `download` after the stub flips to 200 succeeds (clean retry).

Run → FAIL.

- [ ] **Step 2: Implement** per the behaviour above. Keep `BookDetailModel` additions small; if the screen's button label needs the format name, show nothing new (`PDF` stays the format chip — the book *is* a PDF; the button reads `"Download to this phone"` as today, and a PDF-only book's line under the title is unchanged). Add the progress text beside the existing `ProgressView` branch (line ~286) and keep `.disabled(model.transfer == .working)` extended to `.preparing`.

- [ ] **Step 3: Run the new suite** → PASS; whole test command green; `xcodebuild build` exit 0 with no new warnings in this repo's files.

- [ ] **Step 4: Commit** `feat(detail): a PDF-only book downloads as a reflowed EPUB, with the pass's progress`.

---

### Task 4: The record and the live reading

**Files:**
- Modify: `tasks.md` (the "PDF in the reader" revival entry: this slice is the answer for reflowable PDFs; the image-only ~10 % and the original-PDF view stay open), `AGENTS.md` (the expected gate counts: new total and suite count, the Mac smoke count if it moved), `CHANGELOG.md`, `docs/what-works-today.md`, and the Mac-side pointers are the Mac repo's, not this slice's.
- Evidence: `docs/evidence/slice8/README.md` — the live readings (below), numbers quoted, not described.

- [ ] **Step 1: Re-run the full gates** (`xcodegen generate`, build exit 0, test exit 0) and record the per-suite counts: the total must equal the baseline plus the cases Tasks 1–3 added (state the arithmetic).
- [ ] **Step 2: The live reading, against a real Mac on an isolated profile** (the recipe is the header of `scripts/live-probe.sh`; the Mac side is `../musaeum-macos`, started with `env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<profile> npm run dev`, REST API enabled, a PDF-only text book in the scratch library — a 4-page text PDF suffices; the Mac's `scripts/api-smoke.sh` should be run first and its reflow section green). Drive `xcrun simctl` as far as it goes: configure the app, launch with `MUSAEUM_PROBE_DETAIL=<book id>`, and record (a) the detail's frame, (b) the Mac log's 202… 200 sequence, (c) `Books/<id>.epub` present in the app container with the right size and `PK` magic, (d) `downloads.json` carrying the payload with `reflow.available == true`. **A tap or a page turn is a claim for a human frame** — say so in the evidence rather than claiming it; the opening of the EPUB in the reader and a reported fraction are the owner's to confirm, and the README lists exactly those two for him.
- [ ] **Step 3:** Update the four documents with the numbers from Steps 1–2, no hard-wrapped prose, no claim the evidence does not carry.
- [ ] **Step 4: Commit** `docs: slice 8 — a PDF-only book reads on the phone, and what was measured`.

---

## Self-review

- **Spec coverage:** D8's phone clause (`reflow.available` → download `reflow`, save as `{id}.epub`) ✔ Tasks 1–3; "open through the existing navigator, no engine change" ✔ (the file is an EPUB named `.epub`; the reader is untouched); "report the fraction" ✔ unchanged path — claimed for a human frame in Task 4; the 202/422 vocabulary ✔ Task 2; stored-payload compatibility ✔ Task 1 ruling.
- **Placeholders:** none; the two helper names the tests need (`book(formats:reflow:)`, the model/stub plumbing) are described by their contents and follow the neighbouring suites' helpers.
- **Types:** `ReflowProgress` is defined in Task 1 and consumed in Tasks 2–3; `Transfer.preparing(ReflowProgress?)` carries it; `DownloadPlan.of` returns `DownloadPlan?`, matching Task 3's guard.
