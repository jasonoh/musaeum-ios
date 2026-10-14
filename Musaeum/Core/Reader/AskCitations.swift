import Foundation

/// Which entries of the book's contents an answer names (design D7).
///
/// The only jump the panel offers is to a **section label that is in the table of contents the
/// reader already holds** — never a position the model invented. A match is a lookup and a miss
/// is visibly a miss. Known limit: a short, common title ("Notes") can match ordinary prose; the
/// jump is a convenience, a wrong offer costs one tap, and four characters is the floor.
enum AskCitations {
    static func entries(in answer: String, toc: [ReaderTocEntry], limit: Int = 3) -> [ReaderTocEntry] {
        let haystack = normalized(answer)
        var seen = Set<String>()
        var found: [ReaderTocEntry] = []
        for entry in toc {
            let title = normalized(entry.title)
            guard title.count >= 4, title != "untitled", haystack.contains(title),
                seen.insert(title).inserted
            else { continue }
            found.append(entry)
            if found.count == limit { break }
        }
        return found
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
