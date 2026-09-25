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
