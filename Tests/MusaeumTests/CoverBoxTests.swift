import SwiftUI
import XCTest

@testable import Musaeum

/// The cover box: **a cover is bounded by its cell, never by its own artwork.**
///
/// The grid asks a cell for a width and leaves the height free, so whatever the
/// cover view reports for that proposal *is* the row's height. The first spelling
/// of `CoverImage` put a 2:3 ratio on a `Group` whose child was
/// `Image.resizable().aspectRatio(contentMode: .fill)`: the ratio modifier fits the
/// **proposal** to the ratio, it does not clamp what the child then reports, so the
/// box grew to the artwork's own shape. Measured by these cases against that tree
/// (2026-09-23), a cell proposed 114 pt returned 114 × 171 for a 2:3 jacket,
/// **114 × 228** for a 1:2 one and **256.7 × 171** for a 3:2 one — rows of unequal
/// height, landscape covers overlapping the cells beside them. The fix moves the
/// geometry onto a child with no intrinsic size (`Palette.raised`) and the artwork
/// into an `overlay`, whose reported size cannot move its parent.
///
/// The rule is the Mac's own (`src/components/library/BookCard.tsx`:
/// `aspect-[2/3] w-full overflow-hidden` over an `object-cover` image), and the same
/// box is wanted at all three places this view is drawn. A case here reads a
/// **size**, not pixels: that the box follows the cell is decidable in the suite;
/// that the artwork is *cropped into* it rather than bleeding over it is what the
/// live frames decide (`docs/evidence/cover-box/`).
@MainActor
final class CoverBoxTests: XCTestCase {
    /// A JPEG of the given pixel size — the shape a Mac-side `cover_thumb.jpg`
    /// actually arrives in (200 px wide, whatever height the artwork has).
    private func imageData(width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    /// What the cover reports for `width` with the height free — the proposal a
    /// `VStack` inside a grid cell receives, which is the one the defect lived in.
    /// `sizeThatFits(in:)` runs the hosting controller's own SwiftUI layout pass,
    /// so this measures the generated layout instead of reading modifiers back.
    private func box(width: CGFloat, data: Data?) -> CGSize {
        let host = UIHostingController(
            rootView: VStack(alignment: .leading) { CoverImage(data: data, cornerRadius: 6) }
        )
        return host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }

    /// Three columns on the owner's phone: 402 pt less the grid's 16 pt padding
    /// each side and two 14 pt gaps.
    private let columnWidth: CGFloat = 114

    /// The box's rule: the cell's width, and 3/2 of it tall.
    func testTheBoxIsTheCellWidthAndThreeHalvesTall() {
        let size = box(width: columnWidth, data: imageData(width: 200, height: 300))
        XCTAssertEqual(size.width, columnWidth, accuracy: 0.5)
        XCTAssertEqual(size.height, columnWidth * 3 / 2, accuracy: 0.5)
    }

    /// **The defect this file exists for**: a jacket whose artwork is landscape
    /// still occupies a portrait cell — the shape a Mac-side cover takes whenever
    /// the artwork is a wide one, and the row in the owner's own screenshot.
    func testALandscapeCoverOccupiesTheSameBoxAsAPortraitOne() {
        let portrait = box(width: columnWidth, data: imageData(width: 200, height: 300))
        let landscape = box(width: columnWidth, data: imageData(width: 300, height: 200))
        XCTAssertEqual(landscape.width, portrait.width, accuracy: 0.5)
        XCTAssertEqual(landscape.height, portrait.height, accuracy: 0.5)
        XCTAssertEqual(landscape.height, columnWidth * 3 / 2, accuracy: 0.5)
    }

    /// A jacket taller than the box (1:2) is bounded the same way — that one rode
    /// down over its own title — and so is a book the server has no cover for.
    /// **The placeholder must be the box too**, or a row jumps the instant an image
    /// of a different shape arrives where it was.
    func testATallCoverAndAMissingCoverGetTheSameBox() {
        let tall = box(width: columnWidth, data: imageData(width: 100, height: 200))
        let missing = box(width: columnWidth, data: nil)
        XCTAssertEqual(tall, missing)
        XCTAssertEqual(missing.width, columnWidth, accuracy: 0.5)
        XCTAssertEqual(missing.height, columnWidth * 3 / 2, accuracy: 0.5)
    }

    /// The box is proportional: a narrower cell — four columns, or a smaller phone —
    /// gets a shorter cover, not the same one.
    func testTheBoxFollowsTheCellWidth() {
        let wide = box(width: 126, data: nil)
        let narrow = box(width: 90, data: nil)
        XCTAssertEqual(wide.width, 126, accuracy: 0.5)
        XCTAssertEqual(wide.height, 189, accuracy: 0.5)
        XCTAssertEqual(narrow.width, 90, accuracy: 0.5)
        XCTAssertEqual(narrow.height, 135, accuracy: 0.5)
    }

    /// The two fixed-width sites — the detail hero (124 pt) and a download's row
    /// (44 pt) — take the same box at their own width, so a book's hero is the same
    /// height as every other book's and the downloads list does not re-measure.
    func testAFixedWidthSiteGetsTheBoxAtThatWidth() {
        let hero = box(width: 124, data: imageData(width: 300, height: 200))
        XCTAssertEqual(hero.width, 124, accuracy: 0.5)
        XCTAssertEqual(hero.height, 186, accuracy: 0.5)

        let row = box(width: 44, data: imageData(width: 300, height: 200))
        XCTAssertEqual(row.width, 44, accuracy: 0.5)
        XCTAssertEqual(row.height, 66, accuracy: 0.5)
    }
}
