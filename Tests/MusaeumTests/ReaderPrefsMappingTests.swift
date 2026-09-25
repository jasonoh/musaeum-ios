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
