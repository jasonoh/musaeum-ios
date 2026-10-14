# Ask — the live pass (2026-10-14)

What a simulator run against a real Mac said about the Ask sheet, with the stub's own log as the reading of what reached the model. The Mac half is `POST /api/ai/ask` (`../musaeum-macos/docs/rest-api.md`).

## Setup

- This repo: branch `phone-ask-ios`, on `79eb7a5` plus the fixes described under *A defect the pass found* and *The final-review fix wave* (the frames `ask-weak`, `ask-weak-at-060` and `ask-badutf8` were taken after the second; the others before it).
- The Mac: `../musaeum-macos` at `1483988`, clean tree, run as `env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<probe profile> npm run dev` on the isolated probe profile (`rest_api_port` 8789, bound to the tailnet address). The owner's packaged app (port 8788) was never touched.
- The stand-in model: `scripts/ask-stub.mjs` on `127.0.0.1:8799`; the profile's `app_config` carries `ai_base_url = http://127.0.0.1:8799/v1` and `ai_model = stub` (the real keys are `ai_base_url`, `ai_model`, `ai_api_key`, from `electron/main/services/ai.ts`). The stub recognises the probe by the Mac's own system message (`RECALL: <yes|no>` in `shared/ask/ask-context.ts`) and replies in what `shared/ask/recall.ts` `parseProbe` reads.
- The books: **synthetic**, from `make-test-book.py` (numbered paragraphs so a paragraph's true position is a lookup; generated text, not taken from any book). *The Ledger of Small Hours* has five chapters of 30,100 / 16,077 / 60,072 / 22,047 / 12,439 UTF-16 units. The second book (the Mac's ISBN hydration retitled it *The three voices of poetry*) has one 230,245-unit chapter, for the cap.
- Simulator `6CF68F43-7AFB-4651-A166-20F112210DA0` (iPhone 18 Pro, iOS 27.0). Each frame is `xcrun simctl io screenshot` after the run's own wait; `*.probe.txt` is the run's output, `*.stub-check.txt` is the stub log summarised (per request: whether it was the probe, whether the section's paragraph markers or the `BEGIN SECTION TEXT` block appear, and whether the bearer token appears anywhere in the log). The bearer token is in no file here.

## The runs

| Run | Frame | What it shows | Decides |
| --- | --- | --- | --- |
| `ask-weak` (`STUB_RECALL=weak`) | `ask-weak.png` | Sheet over chapter 1: the gold notice *The model couldn't place this book — sending the passage for this session*, the question, the canned answer, the Mac's disclosure line *Sends: title, author, section "Chapter 1: The Quay", position (0%), your question, this section's text around where you are → http://127.0.0.1:8799/v1 · stub — this section's text truncated at 6000 characters*, shown whole over three lines (retaken after the wrap fix; the earlier frame cut it after two lines and lost the endpoint), *Local — nothing leaves your Mac.*, the passage toggle on. Log: `ask verdict=weak`. Stub: the probe request has **no section text**; the ask request carries 13 paragraphs (1–13). | AC20: pass (the Mac's line, whole, before any send). AC21: **partial** — observed live: a weak verdict puts the passage rung and its notice on the sheet and the passage in the ask request; unit-tested only: the override switch (it cannot lower a weak verdict, it can add the passage on a strong one), a highlight travelling verbatim, and incremental rendering of the stream (a frame taken after a wait cannot show it) |
| `ask-weak-at-060` | `ask-weak-at-060.png` | Same, reader at 60% (chapter 3, offset 44,771). Stub: the ask request's text opens in the tail of paragraph 90 and runs paragraphs 91–102, i.e. **text around the reader's position**, not the start of the section. The disclosure line wraps to four lines and the input stays on screen (retaken after the wrap fix). | AC21 (passage around the position): pass; the rest of AC21 as above |
| `ask-unknown` (`STUB_RECALL=unknown`) | `ask-unknown.png` | Grey notice *Unverified — answers about this book are reconstructed, not recalled.*, the disclosure line has no passage member, the toggle is off. Stub: **neither request contains section text**. | AC22: **partial** — observed live: the unverified notice, and no section text reaching the model at the pointer rung; unit-tested only: the override adding the passage on demand |
| `ask-badutf8` (a book whose second chapter is Latin-1 bytes, not UTF-8) | `ask-badutf8.png` | The reader is on chapter 1 (`One`); the sheet probes, answers and draws normally, and the app sits at 0% CPU after the run. Log: `units=94` — the section is the first chapter's own text, ended where Readium's parse of the *next* resource failed. This is the resource that made `content.sequence()` spin; the iterator is driven directly now (see below). A run on the pre-fix code was **not** taken, so this shows the fixed code completing, not the old code hanging. | the extraction cannot hang on an unparsable next resource: pass (live); the hang itself: reasoned from Readium's source |
| `ask-strong` (`STUB_RECALL=strong`, opening = *Needle ember tide copper weather orchard lattice anchor tide umbrella timber*) | `ask-strong.png` | No notice at all; disclosure is pointer-only. Log: `ask verdict=strong`. Stub: no section text in either request. | pointer-only on a strong verdict: pass |
| `ask-off` (the profile with `ai_model` deleted) | `ask-off.png` | *Ask is not available* with the Mac's own reason *No model set — add one in Settings (it has to exist on the endpoint).*; the book's page is drawn behind, unaffected. Stub: no request. | AC25 (off): pass |
| `ask-old` (a 15-line proxy on :8790 that drops `ai` from `/api/health`) | `ask-old.png` | *This Mac's Musaeum is too old to answer questions — update it.* No crash; page drawn. | the too-old state: pass |
| `ask-offline` (the Mac stopped) | `ask-offline.png` | The downloaded book reads; *Ask is not available — the Mac is not answering — Could not connect to the server.* | AC25 (offline): pass |
| `ask-cap` (the 230,245-unit book) | `ask-cap.png` | Log: `ask offset=0 units=200000 truncated=true` — cut to exactly the cap, and **the Mac accepted it** (the ask answered, no 400). | AC26(b) cap path: pass |
| `pos-*` (twelve positions) | `pos-005.png` … `pos-10.png` | The reader opened at fractions 0.05 … 1.0 (the Mac row set, no local position), the sheet over the lower half, the top of the page readable. The measurement below, on a **synthetic** book (paragraphs of 400–1,000 units). | AC26(a): measured on a synthetic book only — **the real-book reading AC26 asks for is still open** |

In every stub log the bearer token appears in no request (the stub never receives it; it is the phone's header to the Mac) and **in no file in this directory**. The `authorization` field of each logged request reads `absent`: the Mac sends no key to the stub (none is configured).

## A defect the pass found, and fixed

The first Ask frames were an **empty sheet** (the first `ask-weak` run's frame, not kept because the re-run overwrote it: a blank rounded surface with no title and no spinner, and no request reaching the stub). Cause: the reader screen presented the sheet with `.sheet(isPresented:)` and an `if let askSession` inside it. The session is created in the same turn that raises the sheet; the sheet's content was built once, with the session still `nil`, and was not rebuilt. A debug log in the closure read `session=nil`, once. It would have bitten a real tap in the same way on the first open (the second open would have worked, because the session then exists). The fix is `.sheet(item:)` over the session (`ReaderScreen.shownAsk`, with `AskSession: Identifiable`); the conversation is still held by `askSession`, so it survives closing the sheet. Not unit-testable (no view in the suite); decided by every frame above.

## The two measurements (AC26)

**(a) The offset mapping**, ten positions in one book (`offsets.tsv` has the table; frames `pos-*.png`). For each, the page's first visible words were read off the frame, found in the section text reconstructed from the generator (heading, then paragraphs, joined by one newline, UTF-16 units), and compared with the offset the phone logged as `ask offset=`. Error = phone − true:

| fraction | section | phone | true | error |
| --- | --- | --- | --- | --- |
| 0.05 | ch1 | 6645 | 6964 | -319 |
| 0.15 | ch1 | 20607 | 21339 | -732 |
| 0.25 | ch2 | 3955 | 3955 | 0 |
| 0.40 | ch3 | 10503 | 9805 | +698 |
| 0.50 | ch3 | 27913 | 27014 | +899 |
| 0.60 | ch3 | 44771 | 44158 | +613 |
| 0.72 | ch4 | 2296 | 2607 | -311 |
| 0.85 | ch4 | 17709 | 18455 | -746 |
| 0.95 | ch5 | 6712 | 7031 | -319 |
| 0.99 | ch5 | 11666 | 11298 | +368 |

The largest error is **899 UTF-16 units, the mean absolute error 501**, against the Mac window's 1,000-unit lead — about 100 units of margin, so thin. Every phone offset is the start of a text element: the anchor is element-granular, so the error is bounded by roughly one paragraph (this book's run 400–1,000 units) plus the page's own start. **That bound is the test book's, not a property of the mapping:** a book of long paragraphs would exceed 1,000 and is not measured here (`tasks.md`). Also: the phone's logged `units=` for all five chapters equals the generator's own count to the unit (30,100 / 16,077 / 60,072 / 22,047 / 12,439), so the Readium extraction sees exactly the XHTML's text (headings included) and the UTF-16 accounting holds for chapter 2's emoji.

**The Task 6 finding — element progression never reaches 1 — was not observed.** 0.99, 0.998 and 1.0 all resolved to offset 11,666 (the same page: the book's last page starts before its last text element), so no `ask offset=nil` appeared. The risk remains reasoned, not measured: a reader whose page starts inside the final element would get `nil`.

**(b) The cap.** Method: the phone's own logged `units=` per section (each chapter was opened at least once). *The Ledger of Small Hours*: **0 of 5** sections exceed 200,000 units (largest 60,072). A real library was not counted (the probe profile holds no real book and the owner's library is out of bounds). The deliberately oversized 230,245-unit section was cut to exactly 200,000 with `truncated=true` and accepted by the Mac.

## Other readings

- **Does dropping the stream after `done` leave the connection closed?** With the app still running after an answered ask (`READER=ask ASK=…`), `lsof -nP -iTCP:8789` listed **no connection in any state** to the Mac, so nothing was left open on the phone's side. This does not isolate *who* closed it (the Mac ends its response after `done`); the unit tests cover the phone's stop-at-terminal. The stub's own `closed` events (each right after `finished`, `sent == of`) show the Mac reads the model's stream to `[DONE]` and releases it.
- **A text selection surviving the tap that raises the chrome** — a tap; `simctl` cannot, so it is a human-frame claim and is not claimed.

## Not verified

A real model (the stub's answer is canned); a real tap on **Ask**, on Send, or on a *Go to* link; a selection surviving the chrome-raising tap; a backgrounded app ending its stream; the 10-second body clock on a 200,000-character section over a slow link (the contract refuses it as a 400 indistinguishable from a malformed one, and the client has no handling — `tasks.md`); the disclosure line at other detents and Dynamic Type sizes (it wraps whole in the medium detent, photographed after the fix).

## The final-review fix wave

- **The extraction cannot spin.** `ReaderModel+Ask.swift` drove `content.sequence()`, whose iterator swallows any error and calls itself again; a resource whose parse fails (here: not valid UTF-8, in the current resource or the next one read to find the section's end) fails identically on every retry, so `askContext()` never returned and `probing` stayed true. It now drives `content.iterator()` directly, and a throw ends the section with the pieces so far. Verified live by `ask-badutf8` (completes, `units=94`).
- **The disclosure line is whole.** The line was cut after two lines in the first frames, so it was not the Mac's sentence *verbatim*. It now wraps fully (`fixedSize` vertical, no line limit); `ask-weak.png` and `ask-weak-at-060.png` were retaken and read: the whole line, endpoint and model included, is on screen over three and four lines, the input still visible. The `pos-*` frames were not retaken (their subject is the page text; their disclosure line is still the cut one).
- **Local/Remote follows the disclosure.** The line used the capability read once at first open; it now reads the latest disclosure's `isLocal`/`host` (`AskEndpointLine`, with three unit cases) and falls back to the capability only before one arrives. Unit-tested only: the live stub is always local, so a switch to a remote endpoint mid-session was not photographed.
- **Ask log lines only when a probe is driving.** `Probe.log` writes `Documents/probe.log`; the Ask lines now go through `Probe.isActive`, so a normal run writes nothing about a conversation to disk (AC24). Reasoned from the code and covered by the build; no live run in a non-probe launch was taken.
- **A `503 busy` probe is not a verdict.** It leaves the verdict nil so the next open probes again (a new unit case); `unreachable` stays `unknown`.
