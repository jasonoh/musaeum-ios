# Slice 6 — Reader polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the reader's fixed header with Apple-Books-style immersive chrome (tap to toggle, `Chapter · %` footer, ✕ and swipe-down exit, contents sheet), then give the page the desktop's typography and Ink/Paper themes.

**Architecture:** Pure rules (`ReaderGestures`, `ReaderTocEntry`, `ReaderFooterLabel`, `ReaderPrefs`, `ReaderPrefsMapping`) each in their own file with an XCTest suite; `ReaderModel` (in `Core/Reader/ReaderHost.swift`) holds the chrome state, the TOC and the prefs; SwiftUI views (`ReaderChrome`, `ContentsSheet`, `TypographySheet`) render them over Readium's `EPUBNavigatorViewController`. Two stages, each green on its own: **6a** (Tasks 1–5) chrome + contents, **6b** (Tasks 6–9) typography.

**Tech Stack:** Swift 6 (strict concurrency complete), SwiftUI, iOS 18, Readium swift-toolkit **3.11.0** (pinned, never patched), XCTest, XcodeGen.

**Spec:** `docs/specs/2026-09-25-reader-polish-design.md` (RP1–RP8, AC1–AC8). Read it before Task 1.

## Global Constraints

- No contract change, no Mac-repo change, no Readium patch, no new dependency (AC8; AGENTS.md invariants 1, 8).
- Local state grows by exactly one `UserDefaults` key, `readerPrefs` (RP3; invariant 7).
- The fraction reported to the Mac is unchanged: `reportProgress` / `settledFraction` / the 2-second `landingFraction` wait are not touched (invariant 3, CD5).
- Failure is a surface, never an alert (CD7).
- One type per file; a pure rule in its own file; `@MainActor` on view models; `async/await` only.
- Run `xcodegen generate` after adding any file, before building.
- Gates, with `DEV=DE0B5601-7874-455E-A965-9AD80567C30E`:
  - `xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build` → exit 0, no warnings in this repo's files
  - `xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test` → exit 0; baseline **136 cases / 16 suites**; reconcile every moved total against the cases added.
  - Single suite: append `-only-testing:MusaeumTests/<SuiteName>` to the test command.
- Markdown prose is not hard-wrapped.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- **A very long chapter title** must truncate and never push the percentage off the footer — `ReaderChrome.progressLabel` keeps `%` in a `.fixedSize()` text (Task 4) and the frame check in Task 5 uses the longest-titled seeded book.
- **Fragment hrefs in the TOC** (`c06.htm#sec2`) must still match the locator's `c06.htm` and a leading `/` must not break the match — pinned in `ReaderTocEntryTests` (Task 2).
- **A tap exactly on a third's boundary, or a zero-width view** during layout must toggle rather than turn a page — pinned in `ReaderGesturesTests` (Task 1).
- **A stored prefs blob from a future version** (unknown theme value, a missing key, a string where a number was) must keep the fields it can and default the rest, not reset everything — pinned in `ReaderPrefsTests` (Task 6).
- **The footer overlapping the last text line** in Readium's bottom inset — no unit test can see it; Task 5's frames are the decider, and a measured overlap is fixed by the footer's bottom padding, recorded in the build section.

---

## Stage 6a — chrome and contents

### Task 1: The gesture rules

**Files:**
- Create: `Musaeum/Core/Reader/ReaderGestures.swift`
- Test: `Tests/MusaeumTests/ReaderGesturesTests.swift`

(The spec's `ReaderTapZone.swift` is named `ReaderGestures.swift` here because it also carries RP2's swipe rule; record the rename in the build section.)

**Interfaces:**
- Produces: `ReaderGestures.Zone` (`.previous | .toggle | .next`), `ReaderGestures.zone(x: CGFloat, width: CGFloat) -> Zone`, `ReaderGestures.closes(startY: CGFloat, dx: CGFloat, dy: CGFloat) -> Bool`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest

@testable import Musaeum

/// Where a tap on the page lands, and which drag closes the book (RP8, RP2).
final class ReaderGesturesTests: XCTestCase {
    func testTheLeftThirdTurnsBack() {
        XCTAssertEqual(ReaderGestures.zone(x: 10, width: 300), .previous)
    }

    func testTheMiddleThirdTogglesTheChrome() {
        XCTAssertEqual(ReaderGestures.zone(x: 150, width: 300), .toggle)
    }

    func testTheRightThirdTurnsForward() {
        XCTAssertEqual(ReaderGestures.zone(x: 290, width: 300), .next)
    }

    /// A boundary belongs to the middle: a tap that could go either way shows the
    /// chrome rather than losing the reader's page.
    func testBothBoundariesToggle() {
        XCTAssertEqual(ReaderGestures.zone(x: 100, width: 300), .toggle)
        XCTAssertEqual(ReaderGestures.zone(x: 200, width: 300), .toggle)
    }

    /// Mid-layout the view can report no width; nothing turns.
    func testAZeroWidthViewToggles() {
        XCTAssertEqual(ReaderGestures.zone(x: 0, width: 0), .toggle)
    }

    func testALongDownwardDragCloses() {
        XCTAssertTrue(ReaderGestures.closes(startY: 200, dx: 10, dy: 120))
    }

    func testAShortDragDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 200, dx: 0, dy: 79))
    }

    func testADiagonalDragDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 200, dx: 70, dy: 120))
    }

    func testAnUpwardDragDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 400, dx: 0, dy: -200))
    }

    /// The top 44 pt belong to Notification Center.
    func testADragFromTheSystemEdgeDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 20, dx: 0, dy: 200))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && xcodebuild … test -only-testing:MusaeumTests/ReaderGesturesTests`
Expected: build FAIL — `cannot find 'ReaderGestures' in scope`.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics

/// The reader's two gesture rules, kept pure so a test can reach them without a
/// view. Readium hands us taps that are not on a link (`didTapAt`); SwiftUI hands
/// us the drag.
enum ReaderGestures {
    enum Zone: Equatable {
        case previous
        case toggle
        case next
    }

    /// Thirds of the page's width (RP8). A boundary is the middle's, and a view
    /// with no width yet toggles rather than turning a page.
    static func zone(x: CGFloat, width: CGFloat) -> Zone {
        guard width > 0 else { return .toggle }
        let third = width / 3
        if x < third { return .previous }
        if x > width - third { return .next }
        return .toggle
    }

    /// How far down a drag must travel to close the book (RP2).
    static let closeTravel: CGFloat = 80
    /// The strip at the top the system keeps for Notification Center.
    static let systemEdge: CGFloat = 44

    /// A predominantly vertical, downward drag of at least `closeTravel`, not
    /// started in the system's edge.
    static func closes(startY: CGFloat, dx: CGFloat, dy: CGFloat) -> Bool {
        startY >= systemEdge && dy >= closeTravel && dy > 2 * abs(dx)
    }
}
```

- [ ] **Step 4: Run to verify it passes** — same command. Expected: 10 cases, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Musaeum/Core/Reader/ReaderGestures.swift Tests/MusaeumTests/ReaderGesturesTests.swift Musaeum.xcodeproj
git commit -m "slice 6a: the reader's tap-zone and close-swipe rules"
```

### Task 2: The contents entries

**Files:**
- Create: `Musaeum/Core/Reader/ReaderTocEntry.swift`
- Test: `Tests/MusaeumTests/ReaderTocEntryTests.swift`

**Interfaces:**
- Consumes: Readium `Link` (`href: String`, `title: String?`, `children: [Link]`).
- Produces: `struct ReaderTocEntry: Identifiable { id: Int; title: String; depth: Int; link: Link }`, `ReaderTocEntry.flatten(_ links: [Link]) -> [ReaderTocEntry]`, `ReaderTocEntry.resource(_ href: String) -> String`, `ReaderTocEntry.current(href: String?, in: [ReaderTocEntry]) -> ReaderTocEntry?`.

The spec's RP7 says "the deepest entry whose href matches". Without reading fragment offsets that is ambiguous when one file holds several entries, so the rule is **the first entry in reading order whose resource matches** — the chapter's own heading, which normally opens its file. Amend RP7's sentence to say so in the Task 5 commit.

- [ ] **Step 1: Write the failing test**

```swift
import ReadiumShared
import XCTest

@testable import Musaeum

final class ReaderTocEntryTests: XCTestCase {
    private let toc = [
        Link(href: "OEBPS/c01.htm", title: "One"),
        Link(
            href: "OEBPS/c02.htm", title: "Two",
            children: [
                Link(href: "OEBPS/c02.htm#a", title: "Two A"),
                Link(href: "OEBPS/c03.htm", title: "Two B"),
            ]
        ),
        Link(href: "OEBPS/c04.htm", title: "  "),
    ]

    func testFlatteningKeepsReadingOrderAndDepth() {
        let entries = ReaderTocEntry.flatten(toc)
        XCTAssertEqual(entries.map(\.title), ["One", "Two", "Two A", "Two B", "Untitled"])
        XCTAssertEqual(entries.map(\.depth), [0, 0, 1, 1, 0])
        XCTAssertEqual(entries.map(\.id), [0, 1, 2, 3, 4])
    }

    func testAFragmentIsNotPartOfTheResource() {
        XCTAssertEqual(ReaderTocEntry.resource("OEBPS/c02.htm#a"), "OEBPS/c02.htm")
    }

    func testALeadingSlashIsNotPartOfTheResource() {
        XCTAssertEqual(ReaderTocEntry.resource("/OEBPS/c02.htm"), "OEBPS/c02.htm")
    }

    /// The first match in reading order — the chapter, not its subsection.
    func testTheCurrentEntryIsTheFirstForItsResource() {
        let entries = ReaderTocEntry.flatten(toc)
        XCTAssertEqual(ReaderTocEntry.current(href: "OEBPS/c02.htm", in: entries)?.title, "Two")
        XCTAssertEqual(ReaderTocEntry.current(href: "/OEBPS/c03.htm#x", in: entries)?.title, "Two B")
    }

    func testAnUnlistedResourceHasNoEntry() {
        let entries = ReaderTocEntry.flatten(toc)
        XCTAssertNil(ReaderTocEntry.current(href: "OEBPS/notes.htm", in: entries))
        XCTAssertNil(ReaderTocEntry.current(href: nil, in: entries))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && xcodebuild … test -only-testing:MusaeumTests/ReaderTocEntryTests`
Expected: build FAIL — `cannot find 'ReaderTocEntry' in scope`. **If it fails instead with `no such module 'ReadiumShared'`**, this is the first test to import Readium: stop and hand back with the error (adding the package product to the test target risks duplicate symbols and is a build-settings decision, invariant 9).

- [ ] **Step 3: Implement**

```swift
import ReadiumShared

/// One row of the contents sheet: the book's nested table of contents, flattened
/// into reading order with the depth each entry sat at (RP6).
struct ReaderTocEntry: Identifiable {
    let id: Int
    let title: String
    let depth: Int
    let link: Link

    static func flatten(_ links: [Link]) -> [ReaderTocEntry] {
        var entries: [ReaderTocEntry] = []
        func walk(_ links: [Link], depth: Int) {
            for link in links {
                let trimmed = link.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                entries.append(
                    ReaderTocEntry(
                        id: entries.count,
                        title: trimmed.isEmpty ? "Untitled" : trimmed,
                        depth: depth,
                        link: link
                    )
                )
                walk(link.children, depth: depth + 1)
            }
        }
        walk(links, depth: 0)
        return entries
    }

    /// The file an href names: no fragment, no leading slash.
    static func resource(_ href: String) -> String {
        let file = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return file.hasPrefix("/") ? String(file.dropFirst()) : String(file)
    }

    /// The first entry in reading order whose file is the locator's.
    static func current(href: String?, in entries: [ReaderTocEntry]) -> ReaderTocEntry? {
        guard let href else { return nil }
        let target = resource(href)
        return entries.first { resource($0.link.href) == target }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — Expected: 5 cases, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Musaeum/Core/Reader/ReaderTocEntry.swift Tests/MusaeumTests/ReaderTocEntryTests.swift Musaeum.xcodeproj
git commit -m "slice 6a: flatten the book's contents and find the current entry"
```

### Task 3: The footer label

**Files:**
- Create: `Musaeum/Core/Reader/ReaderFooterLabel.swift`
- Test: `Tests/MusaeumTests/ReaderFooterLabelTests.swift`

**Interfaces:**
- Consumes: `ReaderTocEntry.current(href:in:)` (Task 2).
- Produces: `ReaderFooterLabel.percent(_ progression: Double?) -> String?`, `ReaderFooterLabel.chapter(locatorTitle: String?, href: String?, toc: [ReaderTocEntry]) -> String?`.

- [ ] **Step 1: Write the failing test**

```swift
import ReadiumShared
import XCTest

@testable import Musaeum

final class ReaderFooterLabelTests: XCTestCase {
    private let toc = ReaderTocEntry.flatten([Link(href: "c01.htm", title: "Why Revolution Is Impossible Today")])

    func testThePercentIsRoundedToAWholeNumber() {
        XCTAssertEqual(ReaderFooterLabel.percent(0.164), "16%")
        XCTAssertEqual(ReaderFooterLabel.percent(0.165), "17%")
    }

    /// CD5: before the engine says where it is, the footer says nothing — not 0%.
    func testNoProgressionIsNoPercent() {
        XCTAssertNil(ReaderFooterLabel.percent(nil))
    }

    func testAnOutOfRangeProgressionIsClamped() {
        XCTAssertEqual(ReaderFooterLabel.percent(1.2), "100%")
        XCTAssertEqual(ReaderFooterLabel.percent(-0.1), "0%")
    }

    func testTheLocatorsOwnTitleWins() {
        XCTAssertEqual(ReaderFooterLabel.chapter(locatorTitle: "Chapter 4", href: "c01.htm", toc: toc), "Chapter 4")
    }

    func testTheContentsSupplyAMissingTitle() {
        XCTAssertEqual(
            ReaderFooterLabel.chapter(locatorTitle: nil, href: "c01.htm", toc: toc),
            "Why Revolution Is Impossible Today"
        )
        XCTAssertEqual(
            ReaderFooterLabel.chapter(locatorTitle: "  ", href: "c01.htm", toc: toc),
            "Why Revolution Is Impossible Today"
        )
    }

    func testNeitherIsNoChapter() {
        XCTAssertNil(ReaderFooterLabel.chapter(locatorTitle: nil, href: "notes.htm", toc: toc))
    }
}
```

- [ ] **Step 2: Run to verify it fails** — Expected: `cannot find 'ReaderFooterLabel' in scope`.

- [ ] **Step 3: Implement**

```swift
/// What the footer says (RP7): the chapter, and how far through the book.
enum ReaderFooterLabel {
    static func percent(_ progression: Double?) -> String? {
        guard let progression else { return nil }
        let clamped = min(max(progression, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// The locator's own title, else the contents entry for its file, else none.
    static func chapter(locatorTitle: String?, href: String?, toc: [ReaderTocEntry]) -> String? {
        if let title = locatorTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return ReaderTocEntry.current(href: href, in: toc)?.title
    }
}
```

- [ ] **Step 4: Run to verify it passes** — Expected: 6 cases, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Musaeum/Core/Reader/ReaderFooterLabel.swift Tests/MusaeumTests/ReaderFooterLabelTests.swift Musaeum.xcodeproj
git commit -m "slice 6a: the reader footer's chapter and percent"
```

### Task 4: The model, the chrome and the contents sheet

**Files:**
- Modify: `Musaeum/Core/Reader/ReaderHost.swift` (`PositionRecorder`, `ReaderModel`)
- Create: `Musaeum/Features/Reader/ReaderChrome.swift`
- Create: `Musaeum/Features/Reader/ContentsSheet.swift`
- Modify: `Musaeum/Features/Reader/ReaderScreen.swift`
- Modify: `Musaeum/Core/Support/Probe.swift`, `scripts/live-probe.sh`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces on `ReaderModel`: `var chromeShown: Bool`, `private(set) var toc: [ReaderTocEntry]`, `private(set) var chapterTitle: String?`, `private(set) var currentEntryID: Int?`, `func handleTap(at point: CGPoint)`, `func jump(to entry: ReaderTocEntry) async`. `Probe.reader: String?` (`MUSAEUM_PROBE_READER`). `ReaderChrome(title:chapter:percent:shown:hasContents:onClose:onContents:onTypography:)` where `onTypography: (() -> Void)?` — `nil` in 6a, the Aa button appears in Task 8.

There is no unit test for this task: the rules it wires are already pinned, and what is left is a screen (AGENTS.md: a UI claim needs a live probe). The build is the gate here; Task 5 is the frame.

- [ ] **Step 1: `PositionRecorder` hears taps.** In `ReaderHost.swift`, add to `PositionRecorder`:

```swift
    var onTap: ((CGPoint) -> Void)?

    /// Readium's taps that were not on a link (`VisualNavigatorDelegate`).
    func navigator(_ navigator: any VisualNavigator, didTapAt point: CGPoint) {
        onTap?(point)
    }
```

- [ ] **Step 2: `ReaderModel` holds the chrome and the contents.** Add the stored properties below `requestedFraction`:

```swift
    /// Whether the top bar and bottom strip are up (RP1). Every open starts hidden.
    var chromeShown = false
    /// The book's contents, flattened (RP6); empty when the book has none.
    private(set) var toc: [ReaderTocEntry] = []
    /// The footer's chapter (RP7), `nil` when neither the locator nor the contents name one.
    private(set) var chapterTitle: String?
    /// The contents entry holding the current location, drawn in gold.
    private(set) var currentEntryID: Int?
```

In `load`, immediately after `let publication = try await opener.open(…).get()`:

```swift
            if case let .success(links) = await publication.tableOfContents() {
                toc = ReaderTocEntry.flatten(links)
            }
```

After `recorder.onLocation = { … }`:

```swift
            recorder.onTap = { [weak self] point in
                self?.handleTap(at: point)
            }
```

Add the two methods:

```swift
    /// RP8: edges turn the page (and put the chrome away), the middle toggles it.
    /// `goLeft`/`goRight` rather than backward/forward so a right-to-left book
    /// turns the way the finger expects.
    func handleTap(at point: CGPoint) {
        guard let navigator else { return }
        switch ReaderGestures.zone(x: point.x, width: navigator.view.bounds.width) {
        case .toggle:
            chromeShown.toggle()
        case .previous:
            chromeShown = false
            Task { _ = await navigator.goLeft(options: NavigatorGoOptions(animated: true)) }
        case .next:
            chromeShown = false
            Task { _ = await navigator.goRight(options: NavigatorGoOptions(animated: true)) }
        }
    }

    /// RP6: a contents jump. The next `locationDidChange` records it exactly as a
    /// page turn would, so the jump is reading progress. A dangling href leaves
    /// the page where it was and says so in the log (CD7 — no alert).
    func jump(to entry: ReaderTocEntry) async {
        chromeShown = false
        guard let navigator else { return }
        let landed = await navigator.go(to: entry.link, options: NavigatorGoOptions(animated: false))
        if !landed {
            Probe.log("reader contents jump failed href=\(entry.link.href)")
        }
    }
```

In `record(_:)`, before `landingFraction = fraction`:

```swift
        // A page turn after the first layout puts the chrome away (RP1). The
        // first location is the book opening, which must not hide a chrome the
        // probe or the reader has just raised.
        if landingFraction != nil { chromeShown = false }
        let href = locator.href.string
        chapterTitle = ReaderFooterLabel.chapter(locatorTitle: locator.title, href: href, toc: toc)
        currentEntryID = ReaderTocEntry.current(href: href, in: toc)?.id
```

- [ ] **Step 3: Create `ReaderChrome.swift`**

```swift
import SwiftUI

/// The reader's furniture (RP1): hidden, a faint `Chapter · %` footer; shown, a
/// top bar and a bottom strip. It overlays the page rather than insetting it, so
/// raising it never reflows the text, and its empty middle passes taps through
/// to Readium.
struct ReaderChrome: View {
    let title: String
    let chapter: String?
    let percent: String?
    let shown: Bool
    let hasContents: Bool
    let onClose: () -> Void
    let onContents: () -> Void
    let onTypography: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if shown {
                topBar.transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if shown {
                bottomStrip.transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                progressLabel
                    .padding(.horizontal, 32)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shown)
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Palette.gold)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close book")
            Text(title)
                .font(.display(15))
                .foregroundStyle(Palette.parchment)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if let onTypography {
                Button(action: onTypography) {
                    Text("Aa")
                        .font(.display(17))
                        .foregroundStyle(Palette.gold)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Typography")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .background(Palette.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var bottomStrip: some View {
        HStack(spacing: 12) {
            Button(action: onContents) {
                Label(hasContents ? "Contents" : "No contents in this book", systemImage: "list.bullet")
                    .font(.subheadline)
            }
            .foregroundStyle(hasContents ? Palette.gold : Palette.muted)
            .disabled(!hasContents)
            Spacer(minLength: 8)
            progressLabel
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    /// A long chapter truncates; the percent never does.
    private var progressLabel: some View {
        HStack(spacing: 4) {
            if let chapter {
                Text(chapter).lineLimit(1).truncationMode(.tail)
                if percent != nil { Text("·") }
            }
            if let percent {
                Text(percent).monospacedDigit().fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.muted)
    }
}
```

- [ ] **Step 4: Create `ContentsSheet.swift`**

```swift
import SwiftUI

/// The book's contents (RP6): nested entries indented a step per level, the
/// current one in gold and scrolled into view. A tap jumps and closes.
struct ContentsSheet: View {
    let entries: [ReaderTocEntry]
    let currentID: Int?
    let onSelect: (ReaderTocEntry) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        Text(entry.title)
                            .font(.display(entry.depth == 0 ? 17 : 15))
                            .foregroundStyle(entry.id == currentID ? Palette.gold : Palette.parchment)
                            .padding(.leading, CGFloat(entry.depth) * 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(entry.id)
                    .listRowBackground(Palette.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Palette.surface)
                .onAppear {
                    if let currentID { proxy.scrollTo(currentID, anchor: .center) }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.surface)
    }
}
```

- [ ] **Step 5: Wire `ReaderScreen.swift`.**

Add state: `@State private var showingContents = false`.

Replace the `.ready` case's `ReaderHost(navigator: navigator).ignoresSafeArea(edges: .bottom)` with:

```swift
                    ReaderHost(navigator: navigator)
                        .ignoresSafeArea()
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                                .onEnded { value in
                                    let closes = ReaderGestures.closes(
                                        startY: value.startLocation.y,
                                        dx: value.translation.width,
                                        dy: value.translation.height
                                    )
                                    if closes {
                                        Probe.log("reader closed by swipe")
                                        dismiss()
                                    }
                                }
                        )
```

Delete the `.safeAreaInset(edge: .top) { bar }` modifier and the whole `private var bar: some View { … }` property. After the `ZStack { … }` closing brace, add:

```swift
        .overlay {
            if model.phase == .ready {
                ReaderChrome(
                    title: request.book.title,
                    chapter: model.chapterTitle,
                    percent: ReaderFooterLabel.percent(model.landingFraction),
                    shown: model.chromeShown,
                    hasContents: !model.toc.isEmpty,
                    onClose: { dismiss() },
                    onContents: { showingContents = true },
                    onTypography: nil
                )
            }
        }
        .statusBarHidden(!model.chromeShown)
        .sheet(isPresented: $showingContents) {
            ContentsSheet(entries: model.toc, currentID: model.currentEntryID) { entry in
                showingContents = false
                Task { await model.jump(to: entry) }
            }
        }
```

In `.task`, after `if Probe.action == "write" { … }`, add the probe seam:

```swift
            await applyReaderProbe()
```

and the method:

```swift
    /// The frames `simctl` cannot tap its way to (AC1/AC2/AC7): `MUSAEUM_PROBE_READER`
    /// raises the chrome or opens the contents once the engine has laid out.
    private func applyReaderProbe() async {
        guard let reader = Probe.reader else { return }
        _ = await model.settledFraction(timeout: .seconds(8))
        switch reader {
        case "chrome": model.chromeShown = true
        case "contents": showingContents = true
        default: break
        }
        Probe.log("probe reader=\(reader) chapter=\(model.chapterTitle ?? "nil") toc=\(model.toc.count)")
    }
```

- [ ] **Step 6: The probe variable.** In `Probe.swift`, beside `openDownloads`:

```swift
    /// Which reader surface the run raises once the book has laid out: `chrome`
    /// or `contents` (slice 6a), `typography`, `ink` or `paper` (6b). A tap is the
    /// only other way to any of them.
    static var reader: String? { value("MUSAEUM_PROBE_READER") }
```

In `scripts/live-probe.sh`, add `SIMCTL_CHILD_MUSAEUM_PROBE_READER="${READER:-}" \` after the `…_DOWNLOADS` line, and add to the header's usage block: `#   TAG=chrome READER=chrome BOOK=<id> ./scripts/live-probe.sh   # the reader's raised chrome (slice 6)`.

- [ ] **Step 7: Build and run the whole suite**

Run: `xcodegen generate`, then the build gate and the test gate.
Expected: build exit 0 with no warnings in this repo's files; tests **157 cases** (136 + 10 + 5 + 6), **19 suites**, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add Musaeum scripts/live-probe.sh Musaeum.xcodeproj
git commit -m "slice 6a: immersive reader chrome, footer, contents sheet and swipe to close"
```

### Task 5: 6a live probe, frames and documents

**Files:**
- Create: `docs/evidence/slice6/` (frames)
- Modify: `docs/specs/2026-09-25-reader-polish-design.md` (a `## Built — slice 6a` section, and RP7's matching sentence per Task 2), `README.md`, `AGENTS.md`, `CHANGELOG.md`

- [ ] **Step 1: Bring the probe server up** per `AGENTS.md` → *Gates* (profile `~/.hermes/profiles/dev/cache/scratch/ios-probe`, `env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<profile> npm run dev` in `../musaeum`). If the profile is gone, rebuild it from `scripts/live-probe.sh`'s header. Boot the simulator first: `xcrun simctl bootstatus $DEV -b`.

- [ ] **Step 2: Take the four frames**, with `BOOK=ef91875e-…` (Negotiation Genius, already downloaded) and, for the long-title check, the seeded book with the longest chapter titles:

```bash
TAG=reader-hidden BOOK=<id> ./scripts/live-probe.sh
TAG=reader-chrome READER=chrome BOOK=<id> ./scripts/live-probe.sh
TAG=reader-contents READER=contents BOOK=<id> ./scripts/live-probe.sh
ACTION=write TAG=write BOOK=<id> ./scripts/live-probe.sh     # AC4: the report path is unchanged
```

Copy each frame into `docs/evidence/slice6/` and read each one. Check: AC1 (no top bar, footer in muted text), AC2 (bar and strip shown), AC7 (entries indented, current one gold), the footer clear of the last text line (Review Focus 5 — if it overlaps, raise `.padding(.bottom, 4)` in `ReaderChrome` and re-shoot, recording the value), the probe log's `probe reader=… chapter=… toc=…` line, and the `write` run's readback matching its report.

- [ ] **Step 3: Record what the probe could not decide.** Taps, the swipe (RP2's risk) and the tap-through of the empty middle are **claims for a human frame** — list them in the build section as handed to the owner: "tap middle → chrome; tap edges → page turns; swipe down → closes (or doesn't: then RP2 falls back to ✕ alone)."

- [ ] **Step 4: Documents.** In the spec, add `## Built — slice 6a (2026-09-25)` with gates (build exit, **157 / 19**), the frames, the `ReaderGestures` rename, the RP7 first-match amendment, and the owner's checklist from Step 3. README *What works today*: add a *Slice 6a* paragraph. AGENTS.md *Gates*: expected counts → 157 cases across 19 suites, and the `READER=` probe line. CHANGELOG: one entry.

- [ ] **Step 5: Commit**

```bash
git add docs README.md AGENTS.md CHANGELOG.md
git commit -m "slice 6a: probe frames, build record and documents"
```

**Stop here and hand the Step 3 checklist to the owner.** If the swipe does not close the book on a real tap-through, remove the `.simultaneousGesture` block and `ReaderGestures.closes`'s tests in a follow-up commit before 6b, recording why.

---

## Stage 6b — typography

### Task 6: `ReaderPrefs`

**Files:**
- Create: `Musaeum/Core/Reader/ReaderPrefs.swift`
- Test: `Tests/MusaeumTests/ReaderPrefsTests.swift`

**Interfaces:**
- Produces: `struct ReaderPrefs: Codable, Equatable, Sendable { typeface: Typeface; fontSize: Double; lineHeight: Double; margin: Double; theme: Theme }`, `ReaderPrefs.Typeface` (`.serif | .sans`), `ReaderPrefs.Theme` (`.ink | .paper`), `ReaderPrefs.default`, the ranges `fontSizeRange` / `lineHeightRange` / `marginRange`, `ReaderPrefs.key == "readerPrefs"`, `ReaderPrefs.load(from: UserDefaults) -> ReaderPrefs`, `func save(to: UserDefaults)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest

@testable import Musaeum

/// RP3: the desktop's typography, stored per device, clamped rather than trusted.
final class ReaderPrefsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ReaderPrefsTests")
        defaults.removePersistentDomain(forName: "ReaderPrefsTests")
    }

    private func decode(_ json: String) throws -> ReaderPrefs {
        try JSONDecoder().decode(ReaderPrefs.self, from: Data(json.utf8))
    }

    func testTheDefaultIsTheDesktops() {
        XCTAssertEqual(
            ReaderPrefs.default,
            ReaderPrefs(typeface: .serif, fontSize: 18, lineHeight: 1.6, margin: 48, theme: .ink)
        )
    }

    func testNothingStoredIsTheDefault() {
        XCTAssertEqual(ReaderPrefs.load(from: defaults), .default)
    }

    func testARoundTripKeepsEveryField() {
        let prefs = ReaderPrefs(typeface: .sans, fontSize: 22, lineHeight: 1.9, margin: 96, theme: .paper)
        prefs.save(to: defaults)
        XCTAssertEqual(ReaderPrefs.load(from: defaults), prefs)
    }

    func testOutOfRangeNumbersAreClampedToTheirEdges() throws {
        let prefs = try decode(#"{"typeface":"serif","fontSize":99,"lineHeight":0.5,"margin":-4,"theme":"ink"}"#)
        XCTAssertEqual(prefs.fontSize, 28)
        XCTAssertEqual(prefs.lineHeight, 1.2)
        XCTAssertEqual(prefs.margin, 16)
    }

    /// A future version's value keeps the rest of the reader's choices.
    func testAnUnknownValueDefaultsOnlyItsOwnField() throws {
        let prefs = try decode(#"{"typeface":"mono","fontSize":22,"lineHeight":1.9,"margin":96,"theme":"sepia"}"#)
        XCTAssertEqual(prefs.typeface, .serif)
        XCTAssertEqual(prefs.theme, .ink)
        XCTAssertEqual(prefs.fontSize, 22)
        XCTAssertEqual(prefs.margin, 96)
    }

    func testAMissingOrMistypedFieldDefaultsOnlyItself() throws {
        let prefs = try decode(#"{"typeface":"sans","fontSize":"big"}"#)
        XCTAssertEqual(prefs.typeface, .sans)
        XCTAssertEqual(prefs.fontSize, 18)
        XCTAssertEqual(prefs.lineHeight, 1.6)
    }

    func testUndecodableDataIsTheWholeDefault() {
        defaults.set(Data("not json".utf8), forKey: ReaderPrefs.key)
        XCTAssertEqual(ReaderPrefs.load(from: defaults), .default)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `-only-testing:MusaeumTests/ReaderPrefsTests`. Expected: `cannot find 'ReaderPrefs' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The reader's typography (RP3) — the desktop's `reader.store.ts` prefs, per
/// device. Stored under one `UserDefaults` key and clamped on the way in, like
/// the desktop's `sanitizePrefs`: a field that cannot be read is defaulted on its
/// own, so one bad value never costs the reader the rest of their choices.
struct ReaderPrefs: Codable, Equatable, Sendable {
    enum Typeface: String, Codable, CaseIterable, Sendable {
        case serif
        case sans
    }

    enum Theme: String, Codable, CaseIterable, Sendable {
        case ink
        case paper
    }

    var typeface: Typeface
    var fontSize: Double
    var lineHeight: Double
    var margin: Double
    var theme: Theme

    static let fontSizeRange: ClosedRange<Double> = 12...28
    static let lineHeightRange: ClosedRange<Double> = 1.2...2.2
    static let marginRange: ClosedRange<Double> = 16...160

    static let `default` = ReaderPrefs(typeface: .serif, fontSize: 18, lineHeight: 1.6, margin: 48, theme: .ink)

    static let key = "readerPrefs"

    static func load(from defaults: UserDefaults) -> ReaderPrefs {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(ReaderPrefs.self, from: data)
        else { return .default }
        return prefs
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Field-by-field decoding, in an extension so the memberwise initialiser stays.
extension ReaderPrefs {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ReaderPrefs.default
        typeface = (try? container.decodeIfPresent(String.self, forKey: .typeface))
            .flatMap(Typeface.init(rawValue:)) ?? fallback.typeface
        theme = (try? container.decodeIfPresent(String.self, forKey: .theme))
            .flatMap(Theme.init(rawValue:)) ?? fallback.theme
        fontSize = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .fontSize)) ?? fallback.fontSize,
            to: Self.fontSizeRange
        )
        lineHeight = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .lineHeight)) ?? fallback.lineHeight,
            to: Self.lineHeightRange
        )
        margin = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .margin)) ?? fallback.margin,
            to: Self.marginRange
        )
    }
}
```

- [ ] **Step 4: Run to verify it passes** — Expected: 7 cases, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Musaeum/Core/Reader/ReaderPrefs.swift Tests/MusaeumTests/ReaderPrefsTests.swift Musaeum.xcodeproj
git commit -m "slice 6b: reader prefs, stored per device and clamped on read"
```

### Task 7: The mapping to Readium

**Files:**
- Create: `Musaeum/Core/Reader/ReaderPrefsMapping.swift`
- Test: `Tests/MusaeumTests/ReaderPrefsMappingTests.swift`

**Interfaces:**
- Consumes: `ReaderPrefs` (Task 6).
- Produces: `ReaderPrefsMapping.epubPreferences(_ prefs: ReaderPrefs) -> EPUBPreferences`, `ReaderPrefsMapping.fontScale(points: Double) -> Double`, `ReaderPrefsMapping.marginScale(_ margin: Double) -> Double`.

- [ ] **Step 1: Write the failing test**

```swift
import ReadiumNavigator
import XCTest

@testable import Musaeum

/// RP4: the desktop's prefs, spoken in Readium's units.
final class ReaderPrefsMappingTests: XCTestCase {
    func testTheDesktopsDefaultSizeIsReadiumsBase() {
        XCTAssertEqual(ReaderPrefsMapping.fontScale(points: 18), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ReaderPrefsMapping.fontScale(points: 12), 0.6667, accuracy: 1e-4)
        XCTAssertEqual(ReaderPrefsMapping.fontScale(points: 28), 1.5556, accuracy: 1e-4)
    }

    func testTheSpacingRangeLandsInsideReadiums() {
        XCTAssertEqual(ReaderPrefsMapping.marginScale(16), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ReaderPrefsMapping.marginScale(160), 3.0, accuracy: 1e-9)
        XCTAssertEqual(ReaderPrefsMapping.marginScale(48), 1.0556, accuracy: 1e-4)
    }

    func testInkIsTheDesktopsInkRow() {
        let epub = ReaderPrefsMapping.epubPreferences(.default)
        XCTAssertEqual(epub.backgroundColor, Color(hex: "#14110d"))
        XCTAssertEqual(epub.textColor, Color(hex: "#e9e1d2"))
        XCTAssertEqual(epub.theme, .dark)
    }

    func testPaperIsTheDesktopsPaperRow() {
        var prefs = ReaderPrefs.default
        prefs.theme = .paper
        let epub = ReaderPrefsMapping.epubPreferences(prefs)
        XCTAssertEqual(epub.backgroundColor, Color(hex: "#f3ece0"))
        XCTAssertEqual(epub.textColor, Color(hex: "#241f18"))
        XCTAssertEqual(epub.theme, .light)
    }

    /// Without this the book's own CSS wins — the bold-sans heading (RP4).
    func testPublisherStylesAreOff() {
        XCTAssertEqual(ReaderPrefsMapping.epubPreferences(.default).publisherStyles, false)
    }

    func testTheTypefaceIsReadiumsGenericFamily() {
        XCTAssertEqual(ReaderPrefsMapping.epubPreferences(.default).fontFamily, .serif)
        var prefs = ReaderPrefs.default
        prefs.typeface = .sans
        XCTAssertEqual(ReaderPrefsMapping.epubPreferences(prefs).fontFamily, .sansSerif)
    }

    func testLineHeightPassesThrough() {
        XCTAssertEqual(ReaderPrefsMapping.epubPreferences(.default).lineHeight, 1.6)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — Expected: `cannot find 'ReaderPrefsMapping' in scope`.

- [ ] **Step 3: Implement**

```swift
import ReadiumNavigator

/// `ReaderPrefs` in Readium's units (RP4). Pure, so the test pins every number.
/// This file imports no SwiftUI: `Color` here is Readium's.
enum ReaderPrefsMapping {
    /// The desktop's authored page rows (`src/lib/theme/reader-palette.ts`).
    static let inkBackground = "#14110d"
    static let inkText = "#e9e1d2"
    static let paperBackground = "#f3ece0"
    static let paperText = "#241f18"

    /// Readium's `fontSize` is a multiplier on its base; the desktop's default 18
    /// is that base.
    static func fontScale(points: Double) -> Double {
        points / 18
    }

    /// The desktop's 16–160 onto Readium's `pageMargins` multiplier, 0.5–3.0. The
    /// endpoints are a first reading; a live frame confirms or moves them, and this
    /// function and its test move together.
    static func marginScale(_ margin: Double) -> Double {
        let span = ReaderPrefs.marginRange.upperBound - ReaderPrefs.marginRange.lowerBound
        return 0.5 + (margin - ReaderPrefs.marginRange.lowerBound) / span * 2.5
    }

    static func epubPreferences(_ prefs: ReaderPrefs) -> EPUBPreferences {
        let ink = prefs.theme == .ink
        return EPUBPreferences(
            backgroundColor: Color(hex: ink ? inkBackground : paperBackground),
            fontFamily: prefs.typeface == .serif ? .serif : .sansSerif,
            fontSize: fontScale(points: prefs.fontSize),
            lineHeight: prefs.lineHeight,
            pageMargins: marginScale(prefs.margin),
            publisherStyles: false,
            textColor: Color(hex: ink ? inkText : paperText),
            theme: ink ? .dark : .light
        )
    }
}
```

(`EPUBPreferences`'s initialiser takes its arguments in declaration order — `backgroundColor, …, fontFamily, fontSize, …, lineHeight, …, pageMargins, …, publisherStyles, …, textColor, …, theme` — so this order compiles; do not reorder.)

- [ ] **Step 4: Run to verify it passes** — Expected: 7 cases, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Musaeum/Core/Reader/ReaderPrefsMapping.swift Tests/MusaeumTests/ReaderPrefsMappingTests.swift Musaeum.xcodeproj
git commit -m "slice 6b: map reader prefs onto Readium's EPUB preferences"
```

### Task 8: The typography sheet, wired

**Files:**
- Create: `Musaeum/Features/Reader/TypographySheet.swift`
- Modify: `Musaeum/Core/Reader/ReaderHost.swift`, `Musaeum/Features/Reader/ReaderScreen.swift`

**Interfaces:**
- Consumes: Tasks 6–7; `ReaderChrome.onTypography` (Task 4).
- Produces on `ReaderModel`: `private(set) var prefs: ReaderPrefs`, `func apply(_ prefs: ReaderPrefs)`. `TypographySheet(prefs: Binding<ReaderPrefs>)`.

- [ ] **Step 1: `ReaderModel` owns the prefs.** In `ReaderHost.swift`:

Add `private let defaults: UserDefaults` and `private(set) var prefs: ReaderPrefs`, and change `init(book:)` to:

```swift
    init(book: ContractBook, defaults: UserDefaults = .standard) {
        self.book = book
        self.defaults = defaults
        prefs = ReaderPrefs.load(from: defaults)
    }
```

Replace the `readingPreferences` property (and its doc comment) with:

```swift
    /// The page's typography (RP3/RP4): the reader's stored prefs, in Readium's
    /// units. Readium's own stylesheet is the base; this is the one place the
    /// desktop's page reaches it.
    private var readingPreferences: EPUBPreferences {
        ReaderPrefsMapping.epubPreferences(prefs)
    }

    /// A change in the sheet: stored, then restyled in place — nothing re-opens.
    func apply(_ newPrefs: ReaderPrefs) {
        guard newPrefs != prefs else { return }
        prefs = newPrefs
        newPrefs.save(to: defaults)
        navigator?.submitPreferences(readingPreferences)
    }
```

- [ ] **Step 2: Create `TypographySheet.swift`**

```swift
import SwiftUI

/// The desktop's typography popover, as a half-height sheet so the page stays
/// visible while it changes (RP5). Every change restyles the open page live.
struct TypographySheet: View {
    @Binding var prefs: ReaderPrefs

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            row("Typeface") {
                Picker("Typeface", selection: $prefs.typeface) {
                    Text("Serif").tag(ReaderPrefs.Typeface.serif)
                    Text("Sans").tag(ReaderPrefs.Typeface.sans)
                }
                .pickerStyle(.segmented)
            }
            row("Size") {
                HStack {
                    Button("A−") { prefs.fontSize = max(prefs.fontSize - 1, ReaderPrefs.fontSizeRange.lowerBound) }
                        .font(.display(14))
                    Spacer()
                    Text("\(Int(prefs.fontSize))").monospacedDigit().foregroundStyle(Palette.parchment)
                    Spacer()
                    Button("A+") { prefs.fontSize = min(prefs.fontSize + 1, ReaderPrefs.fontSizeRange.upperBound) }
                        .font(.display(20))
                }
                .foregroundStyle(Palette.gold)
            }
            row("Line height") {
                Slider(value: $prefs.lineHeight, in: ReaderPrefs.lineHeightRange, step: 0.1)
            }
            row("Spacing") {
                Slider(value: $prefs.margin, in: ReaderPrefs.marginRange, step: 8)
            }
            row("Page") {
                Picker("Page", selection: $prefs.theme) {
                    Text("Ink").tag(ReaderPrefs.Theme.ink)
                    Text("Paper").tag(ReaderPrefs.Theme.paper)
                }
                .pickerStyle(.segmented)
            }
        }
        .tint(Palette.gold)
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium])
        .presentationBackground(Palette.surface)
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(Palette.muted)
            content()
        }
    }
}
```

- [ ] **Step 3: Wire `ReaderScreen.swift`.** Add `@State private var showingTypography = false`. In the `ReaderChrome(…)` call, change `onTypography: nil` to `onTypography: { showingTypography = true }`. After the contents `.sheet`, add:

```swift
        .sheet(isPresented: $showingTypography) {
            TypographySheet(
                prefs: Binding(get: { model.prefs }, set: { model.apply($0) })
            )
        }
```

In `applyReaderProbe`'s `switch`, add:

```swift
        case "typography": showingTypography = true
        case "ink", "paper":
            var prefs = model.prefs
            prefs.theme = reader == "ink" ? .ink : .paper
            model.apply(prefs)
```

- [ ] **Step 4: Build and run the whole suite.** Expected: build exit 0, no warnings; tests **171 cases** (157 + 7 + 7), **21 suites**, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Musaeum Musaeum.xcodeproj
git commit -m "slice 6b: typography sheet restyles the page live"
```

### Task 9: 6b frames and documents

**Files:** `docs/evidence/slice6/`, the spec, `README.md`, `AGENTS.md`, `CHANGELOG.md`.

- [ ] **Step 1: Frames**, same server and book as Task 5:

```bash
TAG=page-ink READER=ink BOOK=<id> ./scripts/live-probe.sh
TAG=page-paper READER=paper BOOK=<id> ./scripts/live-probe.sh
TAG=typography READER=typography BOOK=<id> ./scripts/live-probe.sh
TAG=page-ink READER=ink BOOK=<id> ./scripts/live-probe.sh     # last: leaves the stored theme at the default
```

Read each frame. Check AC6 (serif, Ink colours, visible side margins, the book's heading no longer in its own sans) and AC5 (the sheet over a visible page; Paper restyled). **Compare the Ink frame's side margin with the desktop reader at default Spacing**; if it reads clearly narrower or wider, adjust `marginScale`'s `0.5`/`2.5` constants and the three `testTheSpacingRangeLandsInsideReadiums` expectations together, re-run the suite, re-shoot, and record the final constants.

- [ ] **Step 2: Handed to the owner:** live restyling as each control moves, and that the choice survives closing the book and relaunching (AC5) — taps, so a human frame.

- [ ] **Step 3: Documents.** Spec: `## Built — slice 6b (2026-09-25)` with gates (**171 / 21**), frames, the margin constants as measured, and the owner's checklist. README: a *Slice 6b* paragraph. AGENTS.md: expected counts → 171 cases across 21 suites; add `readerPrefs` to the local-state description wherever CD3's inventory is restated. CHANGELOG: one entry.

- [ ] **Step 4: Commit**

```bash
git add docs README.md AGENTS.md CHANGELOG.md
git commit -m "slice 6b: probe frames, build record and documents"
```
