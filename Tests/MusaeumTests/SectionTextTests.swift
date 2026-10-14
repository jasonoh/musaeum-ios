import XCTest

@testable import Musaeum

final class SectionTextTests: XCTestCase {
    private func piece(_ text: String, _ progression: Double? = nil) -> SectionText.Piece {
        SectionText.Piece(text: text, progression: progression)
    }

    func testPiecesAreJoinedWithANewlineAndEmptyOnesDropped() {
        let section = SectionText.make(
            pieces: [piece("One."), piece(""), piece("Two.")], readerProgression: nil, highlight: nil)
        XCTAssertEqual(section.text, "One.\nTwo.")
        XCTAssertFalse(section.truncated)
    }

    func testNothingToExtractIsNilNotAnEmptyString() {
        let section = SectionText.make(pieces: [piece(""), piece("")], readerProgression: 0.5, highlight: "x")
        XCTAssertNil(section.text)
        XCTAssertNil(section.offset)
        XCTAssertEqual(SectionText.make(pieces: [], readerProgression: nil, highlight: nil).text, nil)
    }

    func testTheHighlightIsTheAnchorWhenItIsFound() {
        let section = SectionText.make(
            pieces: [piece("Alpha.", 0), piece("Beta gamma.", 0.5), piece("Delta.", 0.9)],
            readerProgression: 0.9, highlight: "gamma")
        XCTAssertEqual(section.offset, "Alpha.\nBeta ".utf16.count)
    }

    func testTheProgressionPicksThePieceWhenThereIsNoHighlight() {
        let section = SectionText.make(
            pieces: [piece("Alpha.", 0), piece("Beta.", 0.5), piece("Delta.", 0.9)],
            readerProgression: 0.5, highlight: nil)
        XCTAssertEqual(section.offset, "Alpha.\n".utf16.count)
    }

    /// Readium's text and the page can differ in whitespace; a highlight that cannot be found
    /// must fall back to the progression, not lose the offset or crash.
    func testAHighlightThatIsNotInTheTextFallsBackToProgression() {
        let section = SectionText.make(
            pieces: [piece("Alpha.", 0), piece("Beta.", 0.5)], readerProgression: 0.5,
            highlight: "words that are not here")
        XCTAssertEqual(section.offset, "Alpha.\n".utf16.count)
    }

    func testNoHighlightAndNoProgressionIsNoOffset() {
        let section = SectionText.make(pieces: [piece("Alpha.", 0)], readerProgression: nil, highlight: nil)
        XCTAssertNil(section.offset)
    }

    func testPiecesWithoutProgressionNeverAnchor() {
        let section = SectionText.make(
            pieces: [piece("Alpha."), piece("Beta.")], readerProgression: 0.5, highlight: nil)
        XCTAssertNil(section.offset)
    }

    // MARK: the cap, in UTF-16 units

    func testATextAtTheCapIsNotTruncatedAndOneUnitPastItIs() {
        let at = String(repeating: "a", count: SectionText.cap)
        let atSection = SectionText.make(pieces: [piece(at)], readerProgression: nil, highlight: nil)
        XCTAssertEqual(atSection.text?.utf16.count, SectionText.cap)
        XCTAssertFalse(atSection.truncated)

        let past = SectionText.make(pieces: [piece(at + "a")], readerProgression: nil, highlight: nil)
        XCTAssertEqual(past.text?.utf16.count, SectionText.cap)
        XCTAssertTrue(past.truncated)
    }

    /// An emoji is two UTF-16 units. Cutting between them would produce a lone surrogate, and
    /// counting Characters would let a text past the Mac's cap through.
    func testNeverSplitsASurrogatePairAndCountsInUTF16() {
        let body = String(repeating: "a", count: SectionText.cap - 1)
        let section = SectionText.make(pieces: [piece(body + "🙂🙂")], readerProgression: nil, highlight: nil)

        XCTAssertTrue(section.truncated)
        let text = section.text ?? ""
        XCTAssertLessThanOrEqual(text.utf16.count, SectionText.cap)
        // XCTAssertTrue, not XCTAssertEqual: a failing equality on two 200,000-unit strings builds a
        // diff message that can stall the run.
        XCTAssertTrue(text == body, "the emoji did not fit whole, so neither half is sent")
        XCTAssertNotNil(String(text).data(using: .utf8), "the cut text is valid Unicode")
    }

    func testAnEmojiHeavyTextIsCountedInUnitsNotCharacters() {
        // 120,000 emoji is 120,000 Characters but 240,000 UTF-16 units — past the cap
        let section = SectionText.make(
            pieces: [piece(String(repeating: "🙂", count: 120_000))], readerProgression: nil, highlight: nil)
        XCTAssertTrue(section.truncated)
        XCTAssertLessThanOrEqual(section.text?.utf16.count ?? .max, SectionText.cap)
    }

    func testAnOffsetPastTheCutBecomesNilBecauseThatTextWasNotSent() {
        let filler = String(repeating: "a", count: SectionText.cap)
        let section = SectionText.make(
            pieces: [piece(filler), piece("target text here", 0.9)], readerProgression: 0.9, highlight: "target")
        XCTAssertTrue(section.truncated)
        XCTAssertNil(section.offset)
    }

    func testAnOffsetInsideTheKeptTextSurvivesTruncation() {
        let filler = String(repeating: "a", count: SectionText.cap)
        let section = SectionText.make(
            pieces: [piece("target text", 0), piece(filler)], readerProgression: nil, highlight: "target")
        XCTAssertTrue(section.truncated)
        XCTAssertEqual(section.offset, 0)
    }

    func testTheOffsetIsInUTF16UnitsAfterAnEmoji() {
        let section = SectionText.make(
            pieces: [piece("🙂 hello world")], readerProgression: nil, highlight: "world")
        XCTAssertEqual(section.offset, "🙂 hello ".utf16.count)
    }

    // MARK: the cut, at its edge

    func testAnOffsetExactlyAtTheCutIsNilAndOneUnitBeforeItSurvives() {
        // "a" × (cap-1), "\n", then the anchor: the anchor starts at unit `cap`, the first unit not sent.
        let atCut = SectionText.make(
            pieces: [piece(String(repeating: "a", count: SectionText.cap - 1)), piece("target text")],
            readerProgression: nil, highlight: "target")
        XCTAssertTrue(atCut.truncated)
        XCTAssertNil(atCut.offset, "unit \(SectionText.cap) is not in the text that was sent")

        // One unit earlier the anchor is the last unit kept ("t" at cap-1).
        let before = SectionText.make(
            pieces: [piece(String(repeating: "a", count: SectionText.cap - 2)), piece("target text")],
            readerProgression: nil, highlight: "target")
        XCTAssertTrue(before.truncated)
        XCTAssertEqual(before.offset, SectionText.cap - 1)
    }

    func testAnOffsetAfterAnEmojiPastTheCutIsStillNilInUTF16Units() {
        // 99,999 emoji fill 199,998 units; the anchor follows at unit 199,999 (inside) and the text
        // runs on. The anchor "x" sits in the kept text; "y", 4 units later, would not.
        let lead = String(repeating: "🙂", count: 99_999)
        let kept = SectionText.make(
            pieces: [piece(lead + "x" + String(repeating: "z", count: 10))], readerProgression: nil,
            highlight: "x")
        XCTAssertEqual(kept.offset, 199_998)
        let past = SectionText.make(
            pieces: [piece(lead + "zzz" + "y" + String(repeating: "z", count: 10))], readerProgression: nil,
            highlight: "y")
        XCTAssertTrue(past.truncated)
        XCTAssertNil(past.offset)
    }

    // MARK: the highlight

    func testTheHighlightIsTrimmedAndTheFirstOccurrenceWins() {
        let section = SectionText.make(
            pieces: [piece("one gamma two gamma")], readerProgression: nil, highlight: "  gamma\n")
        XCTAssertEqual(section.offset, "one ".utf16.count)
    }

    func testAWhitespaceOnlyHighlightFallsBackToProgression() {
        let section = SectionText.make(
            pieces: [piece("Alpha.", 0), piece("Beta.", 0.5)], readerProgression: 0.5, highlight: " \n ")
        XCTAssertEqual(section.offset, "Alpha.\n".utf16.count)
    }

    /// Foundation's `range(of:)` compares by canonical equivalence, so a highlight typed decomposed
    /// still anchors in composed text, and the offset is the text's own UTF-16 distance.
    func testACanonicallyEquivalentHighlightStillAnchors() {
        let composed = "Caf\u{00E9} society"
        let decomposed = "Cafe\u{0301} society"
        let section = SectionText.make(
            pieces: [piece("🙂 " + composed)], readerProgression: nil, highlight: decomposed)
        XCTAssertEqual(section.offset, "🙂 ".utf16.count)
    }

    func testTheHighlightIsCaseSensitiveSoADifferingCaseFallsBackToProgression() {
        let section = SectionText.make(
            pieces: [piece("Alpha.", 0), piece("Beta gamma.", 0.5)], readerProgression: 0.5, highlight: "GAMMA")
        XCTAssertEqual(section.offset, "Alpha.\n".utf16.count)
    }
}
