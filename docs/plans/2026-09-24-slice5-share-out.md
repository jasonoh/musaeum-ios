# Slice 5 — sharing a downloaded book out (AirDrop, Mail, Messages)

**Date:** 2026-09-24
**Slice:** 5 — **one stage.** Client-only, against a landed contract: nothing on the wire moves, and `GET /api/books/{id}/file` — the route the phone already downloads through — is the only route involved.
**Annex to:** `docs/specs/2026-09-22-client-v1-design.md` — its CD1–CD8 are closed and this slice adds no CD. **No contract change, no Mac-repo slice, no capability.** The wire is `../musaeum/docs/rest-api.md`, read for the fields this slice names a file after, and for nothing else.
**Read first:** `Musaeum/Core/Store/DownloadStore.swift` (`fileURL(for:)` at `:66`; `adopt` at `:77` and `:84`, where the bytes land and what names them) — then `Musaeum/Features/Detail/BookDetailScreen.swift:163-208` (the action stack the door joins) and `Musaeum/Features/Downloads/DownloadsScreen.swift:52` (the shelf's row) — then `Musaeum/Core/Support/Probe.swift:67` (the upload's seam — the shape this slice's own seam copies) — then `project.yml:70` and `:103` (the two lines that say why this arrow costs nothing, where the other one cost a fork).

---

## What this slice is

A book the phone already holds can leave it: from a book's own screen and from a row on the downloaded shelf, **Share** hands the file to the system share sheet — AirDrop, Mail, Messages, Save to Files, and every other activity that can take an EPUB, MOBI, AZW3 or PDF.

1. **`ShareStaging` — the rule**, with no view and no network in it: what the recipient's file is *called* (`Title - Author.epub`, from the contract's own fields and the extension the downloaded file actually holds), and how the copy is made — a **hard link** where the volume allows it, a copy where it does not, and a **sweep** that leaves the directory holding at most the one file just staged.
2. **A door in two places** — beside *Read* on a book's detail, and on a shelf row. The shelf is the one that decides the feature's own promise, because it is the screen that works with the Mac asleep.
3. **The sheet itself** — `UIActivityViewController`, presented only when the door is used, because staging a 528 MiB book is not something a row's `body` may do.
4. **The seam** — `ACTION=share`, so the staged file, its name, its bytes and where it landed are all readable out of the app's own container. That is the half of this slice `simctl` can decide; the sheet appearing is the half it cannot.

**What this leans on rather than builds** (each verified before this annex was written):

| Already there | Where | What it means here |
| --- | --- | --- |
| **The bytes, already on the phone** | `DownloadStore.swift:49` (`Books/`), `:66` (`fileURL(for:)`) | Nothing is fetched and nothing is converted: the share carries the phone's own copy of what the Mac served — the same file the reader opens |
| The contract's own `title` and `author` | `ContractBook` (`ContractModels.swift:183`, `:184`) | The recipient's file name is derived from the document's own fields, never invented (invariant 1) |
| The format the stored file actually holds | `DownloadedBook.fileName` (`DownloadStore.swift:11`) | The extension is read off the stored name rather than recomposed — the same rule the Mac's own file resolution follows (its invariant 2: nothing resolves by canonical filename) |
| **The id-named local file** | `adopt`'s `"\(book.id).\(format)"` (`:84`) | **This is why staging exists at all**: share the stored file directly and the recipient is handed `540bd9a6-….epub` |
| The door's own state shape, twice over | `ReadingRequest` (`BookDetailScreen.swift:260`) + `@State private var reading` + `.fullScreenCover(item:)` | The same shape one item later: `ShareRequest`, `@State`, `.sheet(item:)` |
| A probe harness that drives the app without a human | `Probe.swift:67`, `MusaeumApp.swift:72` (`runProbeIfAsked`), `scripts/live-probe.sh` | `ACTION=share` drives the **store's own staging call** and reads the result out of the container |
| **No capability, and none needed** | `project.yml:70` (`LSSupportsOpeningDocumentsInPlace: false`), `:103` (*"no app groups"*), `:107` (a free personal team), and **no `.entitlements` file anywhere in the tree** | An outbound share is core UIKit: no second target, no app group, no keychain access group, no provisioning change. **This is slice 4's F2 answered by the other arrow** — the direction that costs nothing, where the inbound one cost a fork |

**Explicitly not in this slice, each for a stated reason:**

- **Sharing a book the phone does not hold.** No fetch-then-share, no *download it for you first*. The door is simply absent when there is no local file. A door that downloads before it can share is a different feature with a different failure surface, and it would make the shelf's own promise (this works with the Mac asleep) conditional.
- **Choosing the format.** The share carries the file the phone holds — `formats.first`, the contract's own preference order, which for this library is an EPUB. The wire would serve the other three, and re-fetching one would put the Mac back in the path.
- **Multi-select, and a batch.** One book, one door, one sheet. (Slice 4's *batch* deferral, unchanged.)
- **Anything inside the sheet's list.** No `UIActivityItemSource` supplying a subject line, no excluded activities, no *share a link* variant. The system's list is the list.
- **Metadata, cover, or reading state travelling with the book.** The recipient gets the book file and nothing of this library's record of it. Deliberate: a shared artifact stays a book, which is also what keeps the share free of any decision about whose data it is.
- **A local library cache.** CD3's inventory is untouched — a staged copy is transient by construction, is swept, and is not a store.

## The forks, each with the alternative it beats and its reversal condition

### F1 — what the share carries: the phone's own copy, or a re-fetch of a chosen format

- **(a) the phone's own downloaded file.** No request, no wait, no format question; it works with the Mac asleep, asleep being the state the shelf exists for.
- **(b) ask the Mac for a named format** (`GET /api/books/{id}/file?format=pdf`) so the sheet can offer *share as PDF* for a book the phone holds as EPUB.

**Recommendation: (a).** It keeps the door's availability identical to the shelf's (both work offline), it makes the shared bytes the same bytes the reader opened — so there is nothing to explain when a recipient's rendering differs — and it decides the format question the only way this client can honestly decide it: the file it has. **Reversal condition:** wanting to share a format the phone does not hold, which is (b) plus a decision about what the door does when the Mac is asleep.

### F2 — the name the recipient sees

The stored file is `<book id>.<format>`. Three options, and the third is the one that looks like doing nothing:

- **(a) share the stored file as-is** — `540bd9a6-9d3f-4c1e-….epub`. Zero code, and the recipient has a file they cannot identify in any list, on any device, forever.
- **(b) the library's own canonical filename** — which the phone **does not have**: the wire carries no path (invariant 2), and a canonical name is a thing the Mac's filesystem knows.
- **(c) `Title - Author.ext`, staged** — from `title` and `author`, which the contract does carry.

**Recommendation: (c), staged into a scratch directory under the app's own container.** The stored file keeps its own name (nothing is renamed), the staged copy is what leaves, and the name is derived from the document rather than invented. **Reversal condition:** a name that a recipient cannot use — the case that would force it is a real one and is handled by rule rather than by reverting: an empty title falls back to the id, and a name that would be *hidden* (a leading `.`) is made visible (see AC2).

### F3 — `ShareLink`, or the activity controller behind a door

- **(a) `ShareLink(item: url)`** — one line, the system's sheet, iOS 16+. **The catch is *when* the file must exist:** a file URL is resolved when the transfer runs, so the staged copy has to be on disk *before* the sheet is built — which, with `ShareLink`, means when the row renders. A 528 MiB book would then be copied by scrolling, and the fallback path makes that a real copy.
- **(b) an explicit Button that stages, then presents `UIActivityViewController`** through a `UIViewControllerRepresentable`, dismissed by setting the item back to `nil`.

**Recommendation: (b).** It puts staging on the *act* rather than on the row, it makes the call site visible and loggable (which is what lets the probe drive the app's own path), and it matches the idiom already in the tree (`@State private var reading` + a presentation modifier on the same screen). **Stated cost:** ~25 lines of representable and a presentation hop that `ShareLink` would have hidden. **Reversal condition:** a future multi-select, where the loop over rows would want the lazy export a custom `Transferable` gives — which is the same property (staging at transfer time) reached from the other side.

### F4 — where the doors are, and what stays absent

**Recommendation: two doors, one of them per-book.** The detail screen gets a **Share** button directly under *Read* — the place a reader already is when they decide a book is worth sending to someone. The shelf gets a trailing share glyph on each row, drawn in `Palette.muted` so the two trailing glyphs stay distinguishable (gold = *read*, muted = *share*), and separated from the read target so neither is a mis-tap. **Both are absent when `fileURL(for:)` is `nil`** — the same condition that already decides whether the row offers *Read* or *Download*. **Reversal condition:** the shelf's two-glyph row reading as one control, which would move the door into a swipe action or a context menu — both of which need a human to verify, which is why they are not the first shape.

## Readings this slice must settle itself, each with the alternative it beats

### R1 — what the sheet actually offers for a staged EPUB

**This one is a human frame and is named as one.** `simctl` can launch an app and take a frame; it can present no sheet and tap nothing in one. So "AirDrop, Mail and Messages appear for this file" is the owner's reading, taken on his own phone, and the annex says so rather than implying a probe covered it. **What is decided here instead:** that a file exists at a path, under a name, with the right bytes — which is the whole of the app's own half. **The alternative it beats:** asserting the sheet's contents, which nothing in this repo can see. (Slice 4's AC9 is the same class, one arrow earlier.)

### R2 — whether a hard link works in the app's own container, and whether the fallback is reachable

The staged directory (`Application Support/Musaeum/Share/`) and the books directory share a volume, so linking *should* work — and "should" is what this reading replaces. **The instrument:** a unit case comparing the source's and the staged file's `fileResourceIdentifierKey` (equal ⇒ one file, two names), and a second case that drives `stage`'s **linker seam** with a closure that throws, asserting the fallback's bytes are identical and its identifier differs. **The alternative it beats:** assuming `linkItem` succeeded, in which case the fallback is dead code that a 528 MiB book's share would discover in production rather than in a case.

### R3 — what a recipient sees for the awkward names

A title is arbitrary text: it can hold `/`, `:`, a newline, a leading `.`, 300 characters, or nothing at all after trimming. **The instrument:** unit cases on the rule, one per character class, each naming what the character would otherwise do (a `/` splits the path; a leading `.` hides the file wherever it lands; an empty stem makes the name the extension alone). **What is *not* decided here:** how any particular receiving app renders it — that is the owner's frame (R1).

### R4 — whether a share of the largest book is viable at all

The library's measured worst case is **554,110,279 bytes (528 MiB)**, and Mail and Messages carry their own ceilings that are not this app's to know. **What is stated rather than measured:** AirDrop and *Save to Files* carry any file; Mail will refuse or bounce the large ones; Messages gets unreliable well before them. That is a caveat about which activities suit which book, not a defect to fix, and it is the owner's own reading to make on a real recipient. **The alternative it beats:** pretending one door is equally good for a 1 MB novel and a 528 MiB scan.

## Files

| File | What |
| --- | --- |
| `Musaeum/Core/Store/ShareStaging.swift` (new) | the rule: the name, the link-or-copy decision with its linker seam, the sweep, and `Staged` (the url **and** whether it was linked) |
| `Musaeum/Features/Shared/ShareSheet.swift` (new) | `ShareRequest` and the `UIActivityViewController` representable — the sheet's own presentation, and the only new directory this slice adds (`project.yml` globs `Musaeum/`, so it is in the target at the next generate) |
| `Musaeum/Core/Store/DownloadStore.swift` (edited) | `stagedForSharing(_:)` (the record's own composition of the rule) and `sweepStaging()` — the store answers "what file would leave", and knows nothing about a sheet. **And a sweep at `init`** (added during the build): a share the OS kills never reaches the sheet's dismissal, so the next launch is the only place that can clear what it left |
| `Musaeum/Features/Detail/BookDetailScreen.swift` (edited) | the door under *Read*, and the refusal text when staging fails |
| `Musaeum/Features/Downloads/DownloadsScreen.swift` (edited) | the trailing share glyph on a row, muted, with its own tap target |
| `Musaeum/Core/Support/Probe.swift` (edited) | `share` joins the actions the seam documents; and `MUSAEUM_PROBE_DETAIL` (added during the build) opens a book's detail, which is the only way a frame can hold the door |
| `Musaeum/App/MusaeumApp.swift` (edited) | `ACTION=share` in `runProbeIfAsked` — the store's own call, then the line that reports name, bytes, equality and directory |
| `Musaeum/Features/Library/LibraryScreen.swift` (edited) | the one condition that acts on `MUSAEUM_PROBE_DETAIL` (added during the build) |
| `scripts/live-probe.sh` (edited) | the share run, the detail run, the container listing that shows what a run left, and the warning a tag that names an action it was not passed now prints |
| `Tests/MusaeumTests/ShareStagingTests.swift` (new) | the name (eight classes), the link, the forced fallback, the sweep, the launch sweep, the absent-file case, and the store's composition |

**Nine files, one stage** (the annex drew eight; the ninth is `LibraryScreen`, which carries the detail seam the frame needed) — inside the house's ~10-file bound, and the ~10th file is the probe script rather than a second target.

## What must not move

- **`LSSupportsOpeningDocumentsInPlace: false`** (`project.yml:70`) — it is what makes Files, Safari and Mail *copy* into `Documents/Inbox` for the inbound hand-off (slice 4b). An outbound feature must not flip it, and `UIFileSharingEnabled` is not an alternative: the books live in `Application Support/Musaeum/Books/`, not `Documents/`, so that key would expose nothing while changing what iOS does with an incoming file.
- **The stored file's own name.** `<id>.<format>` is what the store looks up by (invariant 2 of this repo: the local name is this app's business, and a canonical name would be this client inventing one). The staged copy is a *second* name in a scratch directory; nothing is renamed, and no share path reads a name to find a file.
- **CD3's inventory.** No new durable state: the staged copy is transient, is swept, and is never the source of truth for anything.
- **The contract**, `apiVersion` at 1, and the ten routes the client already speaks. Nothing here reads a field the document does not name.
- **The token's single home, and the reader.** No extension, no second process, no second binary (invariant 10); no file in `Features/Reader/` changes, and the report queue is untouched.

## Acceptance criteria, each with its decider

| AC | Decided by |
| --- | --- |
| 1 | The staged name is `Title - Author.ext`, from the contract's `title`/`author` and the stored file's own extension — including the no-author case (`Title.ext`) — unit cases on the rule |
| 2 | The name is safe to hand to a filesystem and a recipient: `/`, `:`, a newline and a control character are removed; a leading `.` is made visible; a title that trims to nothing falls back to the book id; a long title is truncated by **UTF-8 bytes**, not characters — one unit case per class, each naming what it prevents |
| 3 | **The staged file is the stored download's bytes** — a unit case comparing content, and the probe's own line (`share staged … same=1`) reading the app's container |
| 4 | **A hard link where the volume allows it, a copy where it does not** — a unit case comparing `fileResourceIdentifierKey` with the source, and a second that drives the linker seam with a throwing closure and asserts identical bytes with a *different* identifier |
| 5 | **Nothing is staged until the door is used, and a stage leaves at most one file** — unit cases against a temporary root, and the probe's container listing |
| 6 | A book with no local file stages nothing, and the door is absent — a unit case on the store's own method, plus the two views' shared condition |
| 7 | **Staging needs no Mac** — a live probe run with no listener on the port stages the copy and logs it; no client appears in the path at all |
| 8 | **No capability was added** — the tree holds no `.entitlements` file, `LSSupportsOpeningDocumentsInPlace` is still `false`, no target was added, and the generated project is unchanged by the slice — decided by the diff and by `xcodegen generate` |
| 9 | **A human frame** for what `simctl` cannot drive: the sheet appearing with AirDrop, Mail and Messages on it, and the name the receiving app shows |

## Verification plan

Gates, run from this repo: `xcodegen generate` **first** (a file added since the last generate is not in the target, and a green total that has not moved is not evidence), then `xcodebuild build` and `xcodebuild test` on `id=DE0B5601-7874-455E-A965-9AD80567C30E` (the destination is an `id`, never a name), reporting the **per-suite** count rather than the total. The tree this slice starts from is **117 cases across 15 suites, 0 failures** (measured 2026-09-24 before any edit), so the move is this slice's own cases and nothing else.

Then `../musaeum/scripts/api-smoke.sh --profile <the probe profile>` — it should still read **70 passed, 0 failed**, and if it does not, that is a finding about the slice (it changes no route).

Then a mutation campaign over this slice's deciders (`scripts/swift-campaign.py`, the log into `docs/evidence/slice5/`), one mutant per half of any paired assertion — AC2 and AC4 are the archetypes: **one row for the character class, one for the link.**

Then the live probe: `TAG=share ACTION=share BOOK=<id>` with the Mac up (the run downloads, then stages) and **the same run with no listener on the port** (the run falls back to the phone's own copy, then stages) — the second is the one that decides AC7. **`TAG=` is a label, not a switch** — measured: the first attempt at this run passed the tag alone, reported four ordinary lines and no `share` line at all, and decided nothing while looking green, which is why the script now warns when a tag names an action it was not passed. The frames and the log lines go to `docs/evidence/slice5/`, and the naming/bytes reading is the last `share staged …` line, which is a log line and not a frame on purpose: a screenshot of a staging directory is not a decider of an arrangement, and the line is.

Not in the gates: AC9, which is a tap on a real device and is stated as the owner's.

## Start here

```bash
cd ../musaeum-ios
git log --oneline -3
xcodegen generate
DEV=DE0B5601-7874-455E-A965-9AD80567C30E
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test
TAG=share ACTION=share BOOK=<book id> ./scripts/live-probe.sh
```

Read, in order: `Musaeum/Core/Store/DownloadStore.swift` — what a download is and what names it, which is the whole reason F2 exists; `Musaeum/Features/Detail/BookDetailScreen.swift:163-208` — the action stack the door joins, and the one condition that decides whether it appears; `Musaeum/Features/Downloads/DownloadsScreen.swift:51-82` — the shelf row, whose two-glyph shape F4 argues about; `Musaeum/Core/Support/Probe.swift:61-77` — the seam's existing actions, one of which this slice copies; `project.yml:41-70` — the document types and the `LSSupportsOpeningDocumentsInPlace` line that must not move.

**The Mac side is not involved and must not be touched.** No route changes, no fixture re-derivation (`scripts/vendor-contract-fixtures.sh` is unaffected: this slice names a file after fields the vendored fixtures already hold), and the probe profile's server is used only as the thing that *fills* the phone's shelf — a share run with the Mac stopped is a decider, not a degraded case.
