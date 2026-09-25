# Reader polish — immersive chrome, typography, contents (slice 6)

**Status:** design approved in conversation 2026-09-25; this document awaits the owner's review before a plan is written.

## Why

The owner, reading *Capitalism and the Death Drive* on the phone (2026-09-25): the reader "is not as elegant as the desktop currently", and the persistent header carrying the title and the reading percentage "should be more elegantly handled — the percentage possibly in the footer instead, and some better way to display/hide the header and exit the book."

The measured cause is `Core/Reader/ReaderHost.swift`'s `readingPreferences`: `EPUBPreferences(theme: .dark)` and nothing else. The page is Readium's stock dark theme — Times on pure black, almost no side margin, and the book's own CSS winning (the chapter heading drew in bold sans). The top bar in `Features/Reader/ReaderScreen.swift` is a fixed `safeAreaInset` that never hides.

## Scope

In: an immersive page with tap-to-toggle chrome; the percentage in a footer; a clean exit; a typography sheet carrying the desktop's controls; a table of contents.

Out, deliberately: search inside the book (its own follow-up slice); a progress scrubber (the footer's percentage carries position; revived if jumping by fraction is wanted and the contents sheet is not enough); an `Auto` page theme (the phone has no theme system — revived with one, or as "follow iOS appearance" if the owner asks); PDF (still the deferred item in `tasks.md`); any contract change — none is needed, and none is made.

## Decisions

### RP1 — Apple Books chrome model

The page is full-bleed and the chrome starts **hidden**. A tap in the middle third of the page toggles it; a tap in the left or right third turns the page back or forward. Any page turn hides the chrome.

- **Hidden:** only a faint footer — `Chapter title · 16%`, caption size, `Palette.muted`, centred above the home indicator. No top bar.
- **Shown:** a top bar (✕ at leading, the book title in `Font.display` centred and truncated, `Aa` at trailing) and a bottom strip (`☰ Contents` at leading, the same `Chapter · %` label at trailing), both on `Palette.surface` with the existing hairline, sliding in from their edges.
- Shown/hidden is one piece of view state; it is not persisted — every open starts hidden.

### RP2 — the exit

✕ in the shown top bar closes the reader. A **downward swipe** on the page (vertical travel ≥ 80 pt, predominantly vertical, not starting in the top 44 pt so Notification Center keeps its edge) also closes it. Both go through the existing `.onDisappear` → `reportProgress(door: "closed")` path; the upward sync is untouched.

**Risk, stated:** Readium's paginated web view may consume the vertical pan. If a live run shows the swipe does not reach our recogniser without patching Readium (invariant 8 forbids that), the swipe is dropped and ✕ alone is the exit — the design stays whole without it. The finding is recorded in the build section either way.

### RP3 — typography is the desktop's, per device

`ReaderPrefs` (new, `Core/Reader/ReaderPrefs.swift`) is a plain value type mirroring the desktop's `src/stores/reader.store.ts`:

| Field | Values | Default |
|---|---|---|
| `typeface` | `serif` · `sans` | `serif` |
| `fontSize` | 12–28 pt, step 1 | 18 |
| `lineHeight` | 1.2–2.2, step 0.1 | 1.6 |
| `margin` | 16–160, step 8 (labelled **Spacing**, as on the desktop) | 48 |
| `theme` | `ink` · `paper` | `ink` |

Persisted under one `UserDefaults` key as JSON, per device like the desktop's per-machine prefs. On read it is **clamped, not trusted**: an out-of-range number returns to its range, an unknown enum value to its default, undecodable data to the whole default — the desktop's `sanitizePrefs`. This extends CD3's local-state inventory by exactly that one key, inside *settings*; it is not a library cache (invariant 7).

### RP4 — the mapping to Readium is a pure function

`ReaderPrefs → EPUBPreferences` (its own file, `ReaderPrefsMapping.swift`) sets:

- `publisherStyles: false`, so our typography wins over the book's CSS (the bold-sans heading).
- `fontFamily`: serif → `FontFamily.serif`, sans → `FontFamily.sansSerif` (Readium 3.11's own constants).
- `fontSize` as Readium's multiplier (supported `0.1…5.0`, `1.0` = its base): `points / 18`, so the desktop's default 18 is Readium's `1.0` and the 12–28 range is `0.667…1.556`. The test pins both ends.
- `lineHeight` passed through (1.2–2.2 is inside Readium's range).
- `pageMargins` (Readium's multiplier, supported `0.0…4.0`, `1.0` = its default): linear from the desktop's 16–160 onto `0.5…3.0`, so 48 → `1.056`. The endpoints are a first reading, confirmed or adjusted against a live frame and recorded in the build section — the rule and its test move together.
- `backgroundColor` / `textColor` from the desktop's authored page rows in `src/lib/theme/reader-palette.ts`: **Ink** `#14110d` / `#e9e1d2`, **Paper** `#f3ece0` / `#241f18`. `theme` is set to Readium's `.dark` for Ink and `.light` for Paper so its own chrome-dependent defaults agree.

A change in the sheet updates `ReaderPrefs`, persists it, and calls `navigator.submitPreferences(_:)` — the page restyles in place and nothing re-opens.

### RP5 — the typography sheet

`Features/Reader/TypographySheet.swift`: a `.sheet` at the `.medium` detent so the page stays visible while it is adjusted (the desktop popover's own reason). Rows: Typeface (segmented), Size (stepper with A−/A+ glyphs), Line height (slider), Spacing (slider), Page (segmented Ink / Paper). Opened by `Aa`. The surface colour is `Palette.surface` regardless of page theme, like the rest of the app.

### RP6 — the contents sheet

`Features/Reader/ContentsSheet.swift`: `publication.tableOfContents()`, loaded once when the book opens and held on `ReaderModel`. Nested entries are indented one step per level; the entry containing the current location is drawn in `Palette.gold` and scrolled into view. A tap calls `navigator.go(to:)` and closes the sheet; the next `locationDidChange` updates the footer and the local position exactly as a page turn does — a jump is reading progress, as on the desktop.

### RP7 — the footer label

A pure rule (`ReaderFooterLabel.swift`): given the current locator and the TOC, the chapter title is `locator.title`, else the title of the deepest TOC entry whose href matches the locator's, else none; the percentage is `totalProgression` rounded to a whole percent. With a title: `Chapter · 16%`; without: `16%`; before the engine has said where it is: nothing (CD5 — `nil` is not `0`). Fed from the `locationDidChange` locator `record(_:)` already receives; no timer. The 2-second `landingFraction` wait is untouched — the sync path relies on it.

### RP8 — the tap rule is pure

`ReaderTapZone.swift`: `zone(x:width:) → .previous | .toggle | .next`, thirds of the width, boundaries belonging to `.toggle`. Wired through Readium's `VisualNavigatorDelegate.navigator(_:didTapAt:)` on the existing `PositionRecorder`. `.previous` / `.next` call `goLeft` / `goRight` (so a right-to-left book turns the right way). A tap on a link inside the book is Readium's and never reaches the rule.

## Failure

Per CD7, failure is a surface, not a dialog:

- A book with no contents: ☰ is disabled and labelled *No contents in this book*, rather than opening an empty sheet.
- A `go(to:)` that fails (a dangling href): the sheet closes, the page stays where it was, and `Probe.log` records it.
- A locator with no title and no matching entry: the footer is the percentage alone.
- Corrupt stored prefs: clamped to defaults (RP3); never a crash.

## Acceptance criteria

- **AC1** The reader opens with no top bar; the footer shows `Chapter · %` (or `%`) in `Palette.muted`.
- **AC2** A middle tap shows the top bar and bottom strip; another hides them; a page turn hides them.
- **AC3** Edge taps turn pages back and forward.
- **AC4** ✕ closes the reader and the Mac receives the report (`TAG=write` probe line, unchanged path). The swipe closes it too, or the build section records why it was dropped (RP2).
- **AC5** The typography sheet restyles the open page live for every control; the choice survives closing the book and relaunching the app.
- **AC6** With default prefs the page is serif, 18, 1.6, Ink colours, with visible side margins, and the book's own heading font no longer overrides ours.
- **AC7** The contents sheet lists the book's entries, highlights the current one, and a tap lands on that chapter; the footer's title follows.
- **AC8** No contract change, no Mac-repo change, no Readium patch, no new dependency.

## Testing

Unit (`Tests/MusaeumTests/`), each a pure rule reachable without a view:

- `ReaderPrefsTests` — defaults, clamping of every field, unknown enum, undecodable data, `UserDefaults` round trip.
- `ReaderPrefsMappingTests` — each theme's colours, `publisherStyles` off, font family per typeface, size and margin conversions pinned.
- `ReaderTapZoneTests` — each third, both boundaries, zero width.
- `ReaderFooterLabelTests` — locator title, TOC fallback, neither, `nil` progression, rounding.

The unit suite cannot see a screen, so AC1, AC2, AC5, AC6 and AC7 are claims for **frames**: simulator screenshots of hidden chrome, shown chrome, each sheet, and Ink vs Paper, committed under `docs/evidence/slice6/`. Taps and swipes are claims for a **human frame** (`simctl` drives neither); the owner judges the elegance, which is the point of the slice.

## Staging

The honest file count runs past the house's ~10-file bound (4 new rule files, 3 new views, 2 changed, 4 test files, plus the evidence and document updates), so the plan builds it in two stages, each green on its own:

- **6a — chrome and contents:** RP1, RP2, RP6, RP7, RP8. The page keeps Readium's stock theme for this stage.
- **6b — typography:** RP3, RP4, RP5.

## Files

New: `Core/Reader/ReaderPrefs.swift`, `Core/Reader/ReaderPrefsMapping.swift`, `Core/Reader/ReaderTapZone.swift`, `Core/Reader/ReaderFooterLabel.swift`, `Features/Reader/ReaderChrome.swift`, `Features/Reader/TypographySheet.swift`, `Features/Reader/ContentsSheet.swift`, and the four test files above.

Changed: `Features/Reader/ReaderScreen.swift` (the fixed `bar` and `safeAreaInset` give way to `ReaderChrome`; sheets and the swipe attach here), `Core/Reader/ReaderHost.swift` (`readingPreferences` reads `ReaderPrefs`; the TOC and the current locator are held on `ReaderModel`; `PositionRecorder` gains `didTapAt`). Then `README.md`'s *What works today*, `AGENTS.md`'s expected test counts, and `CHANGELOG.md`.
