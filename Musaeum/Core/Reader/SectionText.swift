import Foundation

/// The current section's text, shaped for `POST /api/ai/ask` (design D3, D6).
///
/// **Pure, and Readium-free on purpose**: the extraction (`ReaderModel+Ask`) hands this a list of
/// pieces, and everything the contract constrains — the join, the cap, the unit, the offset — is
/// decided here where a test can reach it without an EPUB.
///
/// Two rules from the Mac's contract shape it:
/// - **The text is a prefix of the section**, never a window. The Mac scores a probe against the
///   section's opening and cuts the passage window itself, so this cuts only at the *end*.
/// - **Characters are UTF-16 code units** — what JavaScript's `.length` reports and what the Mac
///   measures every cap and offset in. `String.count` counts grapheme clusters and would let an
///   emoji-heavy section sail past a cap the Mac then refuses with a 400.
struct SectionText: Equatable, Sendable {
    /// The most the Mac will accept (`ASK_SECTION_TEXT_MAX_CHARS`), in UTF-16 units.
    static let cap = 200_000

    /// One block of the section's text, with where Readium says it sits in the resource (0…1).
    struct Piece: Equatable, Sendable {
        let text: String
        let progression: Double?
    }

    /// `nil` when the section yielded no text at all — an image-only page, a failed extraction.
    let text: String?
    /// Where the reader is, in UTF-16 units into `text`. `nil` when unknown, or when it falls past the cut.
    let offset: Int?
    let truncated: Bool

    static func make(pieces: [Piece], readerProgression: Double?, highlight: String?) -> SectionText {
        let kept = pieces.filter { !$0.text.isEmpty }
        guard !kept.isEmpty else { return SectionText(text: nil, offset: nil, truncated: false) }

        // The start of each piece in the joined text, in UTF-16 units.
        var starts: [Int] = []
        var joined = ""
        var units = 0
        for (index, piece) in kept.enumerated() {
            if index > 0 {
                joined += "\n"
                units += 1
            }
            starts.append(units)
            joined += piece.text
            units += piece.text.utf16.count
        }

        var offset: Int?
        if let highlight = highlight?.trimmingCharacters(in: .whitespacesAndNewlines), !highlight.isEmpty,
            let range = joined.range(of: highlight)
        {
            // The highlight is an exact anchor — and the Mac's own fallback anchor.
            offset = joined.utf16.distance(from: joined.utf16.startIndex, to: range.lowerBound)
        } else if let progression = readerProgression {
            offset = kept.indices.first { (kept[$0].progression ?? -1) >= progression }.map { starts[$0] }
        }

        guard units > cap else { return SectionText(text: joined, offset: offset, truncated: false) }

        // Cut at the largest scalar boundary whose UTF-16 length is within the cap.
        var count = 0
        var cut = joined.unicodeScalars.startIndex
        for index in joined.unicodeScalars.indices {
            let width = joined.unicodeScalars[index].utf16.count
            if count + width > cap { break }
            count += width
            cut = joined.unicodeScalars.index(after: index)
        }
        let text = String(joined.unicodeScalars[..<cut])
        return SectionText(
            text: text, offset: offset.flatMap { $0 < count ? $0 : nil }, truncated: true)
    }
}
