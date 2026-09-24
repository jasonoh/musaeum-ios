# Slice 4 — sending a book to the Mac (the phone's upload)

**Date:** 2026-09-23
**Slice:** 4 of this repo's own numbering — **4a: the client and the picker**, **4b: the share sheet**. The Mac-side spec calls this *slice 3 of the upload workstream*; the numbering differs because this repo counts its own slices from the reader. It is built **against a landed contract**, not against a plan: the Mac's `POST /api/books` route shipped 2026-09-23 with its document, its goldens and its executable half.
**Annex to:** `docs/specs/2026-09-22-client-v1-design.md` — its CD1–CD8 are closed and this slice adds no CD. The wire it speaks is `../musaeum/docs/rest-api.md` § `## POST /api/books`, which is the **only** description of the upload; the Mac's own record of what the route does, and of what a real client sees on it, is `../musaeum/docs/superpowers/plans/2026-09-23-phone-upload-slice2.md`.
**Read first:** `../musaeum/docs/rest-api.md` → `## POST /api/books` (the parameters, the `201` answer, and every refusal with its word) — then `Musaeum/Core/API/MusaeumClient.swift` (`ClientError`, `mapStatus`, `retryDelay` — the three places this slice must move) — then `Musaeum/Core/Store/SettingsStore.swift` (**the token is a Keychain item**, which is what decides 4b's shape) — then `scripts/live-probe.sh`'s header (the server recipe and the `MUSAEUM_PROBE_*` contract every probe action already uses).

---

## What this slice is

**4a — the client and the picker.** A book chosen from the phone with a Files picker goes to the Mac and appears in the library.

1. **`MusaeumClient.uploadBook(data:format:filename:)`** — `POST /api/books?format=&filename=` with the bytes as the raw body, the bearer token in the header, returning the contract's `import` payload. `sendJSON`, `request(...)` and `check` already do everything but the body.
2. **A `413` that says what it is** — see *The gap this slice opens on* below: today the client would report an oversized book as *the Mac is not answering* **and retry it**, which is the one failure this route can produce that a retry cannot fix.
3. **An entry point and a progress surface** — the library screen's toolbar, a `fileImporter` limited to the formats the contract accepts, and one row that shows what is happening (sending, sent, refused, and *why* in the contract's own words) without pretending the book is in the library before the Mac has said so.
4. **The three refusal classes treated differently, because they are different:** `400` and `413` are this book's problem (say so, offer nothing to retry), `503 busy` and `503 library offline` are worth waiting out (`isRetryable` already knows), and `401` is a credential problem with a place to go and fix it (`SettingsStore`, as the connect screen already does).

**4b — the share sheet.** Book files arrive from Safari, Mail, or Files via the share sheet, which means an extension target. **This is where the slice's one real unknown lives**, and it is not a UI question: see *The forks*.

**What the slice leans on rather than builds** (each verified before this annex was written):

| Already there | Where | What it means here |
| --- | --- | --- |
| The contract's `import` block, in the document's own `json payload=` form | `../musaeum/docs/rest-api.md` (slice 2) | `scripts/vendor-contract-fixtures.sh` extracts **every** `json payload=` block by pattern (an `awk` over the document, not a list of names), so re-running it drops `Tests/Fixtures/contract/import.json` in with no change to the script — invariant 1 holds: the client derives, never restates |
| The token, in the Keychain, with a probe override | `SettingsStore.swift:13`, `:35`, `Probe.token` | A probe run needs no human; an extension needs a *decision* (below) |
| Request composition, strict decoding, status mapping, `Retry-After` parsing | `MusaeumClient.swift:76`, `:259`, `:287`, `:310` | The upload adds a body and a `413`; it invents no plumbing |
| Retry semantics and which errors are worth resending | `ClientError.isRetryable` (`:47`) | `busy`, `libraryOffline` and `unreachable` are retryable; **`413` must not be** |
| A probe harness that can drive the app without a human | `scripts/live-probe.sh`, `Musaeum/Core/Support/Probe.swift:22-67` | A `TAG=upload ACTION=upload MUSAEUM_PROBE_UPLOAD=<path>` action can drive **the upload's own call**; the picker's tap cannot be driven by `simctl` and stays a human frame (AGENTS.md says so) |

**Explicitly not in this slice, each for a stated reason:**

- **Uploading a book that is not a file on disk.** Nothing here reads from the phone's Photos library, from iCloud Drive's *undehydrated* placeholders, or from a URL that has to be downloaded first. A picker that hands back a file the app cannot read is a state to *report*, not one to work around.
- **Multi-file, or a directory.** The contract takes one body per request and answers one book; a batch is a queue the phone owns, and there is no such queue in this slice.
- **Resuming an interrupted upload.** The contract has no `Range` on this route and no idempotency key: a failed upload is a *new* upload, which is safe because a duplicate is answered by policy rather than refused (`add-new`, D3 on the Mac side). Re-trying a 1 GB book from zero on a phone is a cost, not a correctness problem.
- **Editing metadata, covers, or anything else the Mac owns.** The upload creates a row; nothing here changes one.
- **A local library cache.** CD3's line, unchanged: the phone's local state stays settings, the download index, local positions and the report queue. An upload's *progress* is transient state, and it is gone when the app is gone — which is honest about what the Mac does and does not yet know.

## The gap this slice opens on, and it is a real one

**`musaeum`'s slice 2 added a status the iOS client has no case for.** `mapStatus` (`MusaeumClient.swift:292-310`) switches on 400 / 401 / 404 / 416 / 500 / 503, and its `default` is:

```swift
default: throw ClientError.unreachable("unexpected status \(http.statusCode)")
```

`ClientError.unreachable` is documented as *"the Mac is asleep, off the tailnet, or the app is closed"* and **is retryable** (`:47`). So an oversized upload — a correct, deliberate `413 content too large` from a server that is perfectly awake — would be shown to the user as *the Mac is not answering*, and then **retried**, indefinitely, on a file that can never fit. The fix is small and its deciders are cheap: a `case 413: ClientError.tooLarge` beside `rangeNotSatisfiable`, a `.tooLarge` whose `description` is the contract's own sentence, **excluded from `isRetryable`**, and a case that pins both halves — the mapping *and* the non-retryability, because a status mapped correctly and retried anyway is the same bug with a better message.

**This is why the first reading below is a measurement rather than a preference**, and it is also the reason the Mac-side slice wrote its `413` deliberately: the two repos' vocabularies have to move together, and nothing in either suite could see this gap until a client existed. It is recorded here rather than patched in the Mac repo, because invariant 1 puts the client's mapping on this side.

## The forks, each with the alternative it beats and its reversal condition

### F1 — how an upload survives the app going to the background (and what is *not* claimed)

A book over this LAN is seconds to a minute; a book over the tailnet away from home is minutes. iOS gives an app a short window after backgrounding and then suspends it. **The alternatives:** (a) **the default `URLSession`** — the upload runs while the app is in the foreground and, whatever the user does, the *outcome* is a message when they come back, because the request either completed or failed; (b) a **background `URLSession`** with a discretionary task — survives suspension, at the cost of a delegate, a session identifier, a re-attachment path after a relaunch, and a store for what was in flight; (c) refuse to start unless the app is foreground. **Recommendation: (a) for 4a**, and (b) only if the phone's own measurements (R2 below) show a real upload outliving the foreground window. **Reversal condition:** a measurement showing the foreground window ends before a normal book finishes — then (b) is a slice of its own, and (a)'s surface (one row, one message) is exactly the state (b) would need to read.

**What this does not claim:** an upload that the OS kills mid-flight leaves the Mac holding a scratch file that its own stall clock cleans up and no row at all — there is nothing to reconcile on either side. That is a property of the route as landed, and it is stated here so nobody writes a recovery pass for it.

### F2 — what a share extension can reach: a shared container, or a second copy of the token

An extension is a **separate process with its own sandbox**. The token is a Keychain item written by the app (`SettingsStore.swift:13`, `:61`) and `project.yml:59` says explicitly *"no app groups"* today. So 4b has exactly two routes, and the choice is not cosmetic:

- **(a) share the keychain.** The extension reads the same token and uploads in its own process. It needs a keychain **access group** on both targets, and it puts the credential in a second binary — against invariant 10's *"the token appears in one place"*.
- **(b) share a container, and let the app do the sending.** The extension copies the picked file into an **app-group container** and writes a one-line request; the app uploads it on next foreground (or the extension asks the app to open with the file). The extension never holds a credential and never speaks to the Mac.

**Recommendation: (b).** It keeps the token in one process, it makes the *extension* trivially small (copy a file, write a note), it reuses 4a's whole upload path unchanged, and the backgrounding question (F1) does not arise twice. **The cost, stated:** an app group is an entitlement change on both targets (`project.yml` and an entitlements file), it needs a **paid** team for the App Group capability on a device — the simulator is fine — and the user sees the upload start when the app comes back rather than instantly. **Reversal condition:** the owner wants the share to *finish* without opening the app, which is (a) plus a keychain access group and its own reading.

### F3 — what the phone does with the id it just created

The `201` carries the book, so the phone knows it immediately; what it does **not** know is whether its own library list (a page fetched before the upload) still describes the library. **The alternatives:** (a) insert the returned book into the in-memory list, so it appears at once; (b) re-fetch the first page and let the sort decide where it belongs; (c) show the message and leave the list alone until the user pulls to refresh. **Recommendation: (b), and only for the page the user is looking at** — the Mac's own sort keys decide a book's place (`title`/`author`), and (a) would put a new book where the *client's* idea of the order says, which is the drift invariant 1 exists to prevent. **Reversal condition:** a re-fetch that visibly loses the user's scroll position or their search — then (a) with the row marked *just added*, and the order corrected on the next fetch.

### F4 — the picker's formats

The contract accepts the formats whose extension it is given (`format=epub`, `format=pdf`, …) and refuses a body whose name disagrees with the declared format. **Recommendation:** the picker offers exactly the formats `GET /api/library`'s books hold — `epub`, `mobi`, `azw3`, `pdf` — as a UTI list in one place, and the declared `format` is derived from the file's own extension rather than asked of the user. **Reversal condition:** a format the Mac accepts and the picker cannot offer, which would be a `format` the document names and the UTIs do not.

## Readings this slice must settle itself, each with the alternative it beats

### R1 — whether `URLSession` can send a 528 MiB file without the app holding it in memory

The largest EPUB in the owner's library is **528 MiB** (the Mac's own census, carried in the phone-upload spec). `Data(contentsOf:)` on that is a jetsam. **The instrument:** an `uploadTask(with:fromFile:)` against the isolated profile with the Mac's own `413` cap as the backstop, measuring the app's resident footprint while a large file goes out — `xcrun simctl spawn <dev> log`/`footprint`, or the probe's own log line. **The alternative it beats:** building the body in memory, which works on the simulator with a small book and dies on the phone with a real one. **What it must also answer:** whether `httpBody` with a `Data` body (the shape `ReadingReporter` uses for its small JSON) is *quietly* an in-memory upload — it is, and the upload must use `fromFile:`.

### R2 — what an upload from *this phone* costs, and therefore whether F1's (a) is enough

The Mac measured the wire's other direction (a 320 MiB stream, worst inter-chunk gap **99.7 ms**, hence the 30 s stall clock) — and that harness could not produce the phone's own path, which its own annex says explicitly. **The instrument:** the probe uploading a real book from the simulator to the Mac on this LAN, timing it, and then the same over the tailnet with the Mac's Wi-Fi off (a DERP relay), which is the slow case the user will actually hit away from home. **What it decides:** whether the foreground window is enough (F1), and whether the progress surface needs a rate or only a spinner. **The alternative it beats:** assuming the download measurement (528 MiB in 25.64 s) transfers to the upload direction, which nothing has measured.

### R3 — whether a `413` arriving mid-body is readable by `URLSession` at all

The Mac's slice 2 proved this for a raw socket with its own assertion (`sent < declared / 4`): a client still writing its bytes **does** read the refusal. `URLSession` is a different client: it may report the answer as a completed task, or as an error whose `userInfo` carries a reset. **The instrument:** the probe uploading a file past the cap (the cap is a seam on the Mac's side, so a small file can exercise it) and logging *what `URLSession` gave back*. **What it decides:** whether the app can say *"the Mac refused this because it is too large"* or is reduced to *"the upload failed"* — the difference between a fixable refusal and a mystery, and exactly the class of thing a green unit suite cannot see.

### R4 — how long a picked file stays readable

A `fileImporter` hands back a URL whose access is **security-scoped**: readable while the scope is open, and the scope is easiest to keep while the callback is still running. **The instrument:** a reading of what happens when the copied file is *not* taken immediately — the scope closed, the app relaunched, the picker's URL stored and used later. **The alternative it beats:** holding the security-scoped URL for the duration of a minutes-long upload, which works in the happy path and fails on the phone when the user switches apps. **Recommended shape, decided by the reading rather than assumed:** copy into the app's own container first, upload from there, delete on completion — which is also what makes R1's `fromFile:` possible.

## Files

| Stage | File | What |
| --- | --- | --- |
| 4a | `Musaeum/Core/API/MusaeumClient.swift` (edited) | `uploadBook(...)` — the body, the query, the bearer header; and **`413` in `mapStatus`** plus `.tooLarge` in `ClientError`, excluded from `isRetryable` |
| 4a | `Musaeum/Core/API/ContractModels.swift` (edited) | the `import` payload type, derived from the document's block — strictly decoded, invariant 4 |
| 4a | `Musaeum/Core/Store/UploadModel.swift` (new) | the upload's own state machine: idle → copying → sending → sent/refused, with the refusal's word and whether it is retryable. `@Observable`, `@MainActor`, no view in it |
| 4a | `Musaeum/Features/Library/LibraryScreen.swift` (edited) | the toolbar entry point and the one row that reports the outcome |
| 4a | `Musaeum/Features/Library/UploadSheet.swift` (new) | the picker, the file it holds, the progress, and the message — the only place a `fileImporter` appears |
| 4a | `Musaeum/Core/Support/Probe.swift` (edited) | `MUSAEUM_PROBE_UPLOAD` — the path a probe run sends, so R1–R3 are runnable without a human |
| 4a | `Tests/MusaeumTests/UploadTests.swift` (new) | the composed request (method, path, query, body bytes, header), the `413` mapping **and** its non-retryability, the strict decode of the vendored `import` fixture, and the three refusal classes |
| 4a | `Tests/MusaeumTests/ClientTests.swift` (edited) | the one place the request itself is asserted; the upload's belongs beside `testLibraryRequestCarriesSearchSortAndDirection` |
| 4a | `scripts/live-probe.sh` (edited) | `ACTION=upload` + `MUSAEUM_PROBE_UPLOAD`, and the frames/numbers it writes into `docs/evidence/slice4/` |
| 4b | `project.yml`, `Musaeum/Musaeum.entitlements` (edited) | the extension target and the app group F2(b) needs |
| 4b | `MusaeumShare/ShareViewController.swift` (new) | copy the picked file into the shared container, write the note, done |
| 4b | `MusaeumShare/Info.plist` (new) | the `NSExtension` activation rule (file URLs, the four formats) |
| 4b | `Musaeum/Core/Store/UploadInbox.swift` (new) | the app's side of the hand-off: what the extension left, when to send it |
| 4b | `Tests/MusaeumTests/UploadInboxTests.swift` (new) | what a hand-off looks like from both sides, including one that is a directory, one that is a stale note, and one whose file is gone |

**8 files for 4a, 5 for 4b** — two stages because the house bound is ~10 and 4b's shape (a second target, an entitlement, a hand-off with two sides) is not a continuation of 4a's. Stage 4a alone is a usable feature: a book picked in the app reaches the Mac.

## What must not move

- **Invariant 1's line.** Nothing here restates the contract: the `import` model and its fixtures come from `../musaeum/docs/rest-api.md` by script. A field the app needs and the document does not name is a slice in the **Mac** repo.
- **CD3's inventory.** No new durable state. An upload in flight is memory, and the *result* is the Mac's row.
- **The token's single home.** Whatever F2 decides, the credential stays in one process (invariant 10).
- **The reader, the download store, positions and the report queue.** No file in `Features/Reader/` or the report path changes; the report queue's own ordering (D6) is untouched by an upload that has nothing to report.
- **`apiVersion`** at 1, and the ten routes the client already speaks.

## Acceptance criteria, each with its decider

| AC | Decided by |
| --- | --- |
| 1 | a composed `POST /api/books?format=epub&filename=…` carries the bearer header and the file's bytes — asserted on the `URLRequest` `URLProtocol` sees, **and** on the body being a file the session reads (`fromFile:`), not `httpBody` |
| 2 | `413` maps to `.tooLarge` with its own description, **and is not retryable** — two assertions in one case, because a good message on a retried request is the same bug |
| 3 | the `import` payload decodes from the **vendored fixture** (the document's own block), strictly — a missing key throws, an explicit `null` is `nil` (invariant 4) |
| 4 | `503 busy` is retried honouring `Retry-After` and `400`/`413` are not retried at all — the same case shape the cover pipeline already uses |
| 5 | a picker holding a file whose extension and declared format disagree still sends the format the *document* names for that extension |
| 6 | the outcome row says which class of refusal it was, in the contract's words, and never claims the book is in the library before the `201` — decided at the model, not the view |
| 7 | a probe run uploads a real book end to end against the isolated profile and the Mac then serves it by id — the live instrument |
| 8 | (4b) a file shared from Files reaches the app's own upload path with no credential in the extension — asserted on the extension's own source (no `MusaeumClient`, no token read) plus the hand-off test |
| 9 | **a human frame** for the two claims `simctl` cannot drive: the picker opening and a book being chosen; and, in 4b, the sheet appearing in the share sheet |

## Verification plan

Gates, run from this repo: `xcodegen generate` first (a file added since the last generate is not in the target — and a green total that has not moved is not evidence), then `xcodebuild build` and `xcodebuild test` on `id=DE0B5601-7874-455E-A965-9AD80567C30E` (the destination is an `id`, never a name), reporting the **per-suite** count rather than the total. Then `../musaeum/scripts/api-smoke.sh --profile <the probe profile>` (it needs a profile or `MUSAEUM_USER_DATA`; it exits rather than defaulting to the real one) — expected **70 passed, 0 failed** on the landed Mac slice, which is the number the Mac's own annex records. Then a mutation campaign over this slice's deciders (`scripts/mutation-campaign.py` from the `musaeum-slice-workflow` skill; the log goes to `docs/evidence/slice4/`), one mutant per half of any paired assertion — AC2 is the archetype here: **one row for the mapping, one for the retryability.**

Not in the gates: anything needing a tap (AC9), and a device run (the simulator is the instrument both earlier slices used).

## Start here

```bash
cd ../musaeum && git log --oneline -3 && npm test        # expect 1408 in 59 files
cd ../musaeum-ios && git log --oneline -3
scripts/vendor-contract-fixtures.sh                      # gains Tests/Fixtures/contract/import.json
xcodegen generate
DEV=DE0B5601-7874-455E-A965-9AD80567C30E
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test
```

Read, in order: `../musaeum/docs/rest-api.md` § `## POST /api/books` — **the route as landed**, with every refusal and its word, and the only description of the wire this slice has; `../musaeum/docs/superpowers/plans/2026-09-23-phone-upload-slice2.md` — what a *socket-level* client sees, including that a `413` is read by a client still sending, which is R3's hypothesis; `Musaeum/Core/API/MusaeumClient.swift:287-325` — `mapStatus` and the missing `413`, which is this slice's first fix; `Musaeum/Core/Store/SettingsStore.swift` — the Keychain item that decides 4b's fork; then `scripts/live-probe.sh`'s header for the server recipe the probe needs.

**The Mac side is landed and is not to be re-derived:** `POST /api/books?format=&filename=` with the raw bytes as its body; `201` with the `import` payload (the row **pre-hydration**, so `seriesName` may be null); `400` for a missing `format`/`filename` or an empty body; **`413 content too large`** past 1 GiB, answered while the sender is still sending; `503 busy` with `Retry-After: 1` when two byte transfers are in flight; `503 library offline` with `Retry-After: 5`; `401` with `WWW-Authenticate`; a uniform `404` for every other method on the path; and a duplicate answered by policy — a **second book**, with the match named in the payload, not a refusal. **The `duplicate` object's `existingAuthor` is `null` when the matched book holds no author** — the wire really sends `null` rather than a placeholder, so decode it as optional or a no-author collision costs the whole `201` body; `existingBookId`, `existingTitle` and `matchType` are always present.
