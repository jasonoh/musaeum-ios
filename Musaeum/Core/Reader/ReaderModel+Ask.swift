import ReadiumNavigator
import ReadiumShared

/// What the Ask sheet asks of the open book.
extension ReaderModel: AskContextProviding {
    func askContext() async -> AskReaderContext? {
        guard let navigator, let publication, let location = navigator.currentLocation else { return nil }

        let highlight = navigator.currentSelection?.locator.text.highlight?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `AskSession` holds its "probing" flag for as long as this runs, so a cancelled caller must
        // get control back at once: a cancelled extraction yields nothing rather than half a section.
        guard let pieces = await Self.pieces(of: publication, resource: location) else { return nil }
        let section = SectionText.make(
            pieces: pieces,
            readerProgression: location.locations.progression,
            highlight: highlight)

        return AskReaderContext(
            label: chapterTitle,
            fraction: landingFraction,
            selection: (highlight?.isEmpty ?? true) ? nil : highlight,
            section: section)
    }

    /// The current resource's text blocks, in reading order, each with where Readium says it sits.
    ///
    /// Iteration starts at the top of the resource and **stops at the first element that belongs
    /// to the next one** — `content(from:)` runs on through the whole book otherwise. The pieces
    /// are `TextContentElement`s only: an image's alt text is not the section's prose, and the
    /// Mac's own extraction reads text nodes the same way.
    ///
    /// An element's `progression` is its index over the resource's element count (Readium's
    /// `HTMLResourceContentIterator`), not a character fraction — so it is a coarse anchor, and
    /// `SectionText` prefers the highlight when there is one. How coarse is measured on a real
    /// book in the live pass (design AC26), not assumed here.
    ///
    /// `nil` only when the task was cancelled; a resource Readium cannot iterate is `[]`.
    private static func pieces(of publication: Publication, resource location: Locator) async -> [SectionText.Piece]? {
        let top = Locator(
            href: location.href, mediaType: location.mediaType,
            locations: Locator.Locations(progression: 0))
        guard let content = publication.content(from: top) else { return [] }

        // The navigator's href may carry a fragment or differ in encoding from the iterator's.
        let resource = location.href.removingFragment()
        var pieces: [SectionText.Piece] = []
        // The iterator, not `content.sequence()`: the sequence's `next()` swallows an error and
        // calls itself again, and a resource whose parse failed (XHTML that is not valid UTF-8, in
        // this resource or the next one we read into to find the section's end) fails the same
        // way every time — so the loop body, and its cancellation check, would never run and
        // `askContext()` would never return. A throw here ends the section with what we have.
        let iterator = ElementIterator(content.iterator())
        while !Task.isCancelled {
            guard let element = await iterator.next() else { break }
            if !element.locator.href.removingFragment().isEquivalentTo(resource) { break }
            guard let block = element as? TextContentElement, let text = block.text, !text.isEmpty else { continue }
            pieces.append(SectionText.Piece(text: text, progression: element.locator.locations.progression))
        }
        return Task.isCancelled ? nil : pieces
    }
}

/// Readium's `ContentIterator` is not `Sendable`, and its `next()` is a nonisolated `async` call, which
/// Swift 6 will not let the main actor make. This loop is the only thing that ever touches the
/// iterator, one `next()` at a time, so the box says so. A throw becomes `nil`: the end of the section.
private final class ElementIterator: @unchecked Sendable {
    private let base: ContentIterator
    init(_ base: ContentIterator) { self.base = base }
    func next() async -> ContentElement? { try? await base.next() }
}
