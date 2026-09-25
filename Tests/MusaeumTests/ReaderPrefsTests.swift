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
