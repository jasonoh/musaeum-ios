import Foundation

/// **The narrowing a text query cannot express** — read status, format, a rating
/// floor, and the three axes whose values are the library's own strings (author,
/// series and tag) — as pure rules, so every one of them has a decider that never
/// needs a screen.
///
/// Everything the contract decides is mirrored rather than re-derived
/// (`../musaeum/docs/rest-api.md` → `GET /api/library`). Three of its rules are
/// load-bearing here:
///
/// - **An axis with nothing selected is not a parameter.** This client composes
///   no `formats=` and no `readStatus=`: a pair with no value is a question with
///   no content, and the one thing it can mean is "whatever the server decides an
///   empty list means". The Mac's own rule for a narrowing (`query.trim() ? … :
///   …`) is the same rule one level up.
/// - **One query item per selected value**, never a comma-joined list. The
///   contract reads a repeated parameter and a comma-separated one as the same
///   thing — `?tags=a&tags=b` is `?tags=a,b` — but the equivalence is the
///   *server's* to apply, and it applies it by splitting every value it is
///   handed. A client that joins with commas has taken ownership of a separator
///   rule it does not own; the repeated form leaves the reading to the server,
///   where that rule lives.
/// - **A value that contains the separator is a limit of the wire, not of this
///   file.** The split happens before the match, so `William Strixrud, PhD` — a
///   real author on the probe profile — cannot be filtered by in either form.
///   Measured, and reported upward rather than worked around: no client-side
///   spelling of that value can survive a server that splits it.
///
/// `minRating` is a whole number, and the sheet offers 1…5 because that is the
/// range a book's own rating carries; a rating floor of 0 is every book, which is
/// the same request as no floor at all.
struct LibraryFilters: Equatable, Sendable {
    /// The four formats the contract's `formats` accepts — a value outside this
    /// set is a **400**, not a default (the server refuses rather than guesses,
    /// which is what makes a client-side vocabulary worth having).
    enum Format: String, CaseIterable, Sendable {
        case epub
        case mobi
        case azw3
        case pdf
    }

    /// The axes whose values are the library's own strings.
    ///
    /// These three are one code path on purpose: the sheet draws them with one
    /// reusable picker, and a phone that grew a second kind of list for series
    /// would be a phone that had two behaviours to keep in agreement.
    enum Axis: String, CaseIterable, Sendable {
        case authors
        case series
        case tags

        /// The Mac's own group labels (`src/components/shared/FilterSidebar.tsx:109-111`),
        /// so the two devices name one axis one way.
        var title: String {
            switch self {
            case .authors: "Authors"
            case .series: "Series"
            case .tags: "Tags"
            }
        }

        /// The contract's own list for this axis, **in its own order** — count
        /// descending, as `GET /api/library/facets` returns it. No client-side
        /// rank and no top-N cut: the real library's `authors` facet is 3,727
        /// values, so the answer to a long list is a narrow field, not a shorter
        /// list.
        func values(in facets: Facets) -> [Facet] {
            switch self {
            case .authors: facets.authors
            case .series: facets.series
            case .tags: facets.tags
            }
        }

        /// What the picker's own field is for.
        var prompt: String { "Narrow \(title.lowercased())" }

        /// The token this axis takes in the probe's own encoding — `author`, not
        /// the axis's own plural, because a probe run is a line a human types into
        /// a shell.
        var probeName: String {
            switch self {
            case .authors: "author"
            case .series: "series"
            case .tags: "tag"
            }
        }

        var emptyNote: String { "No \(title.lowercased()) in this library." }
    }

    var readStatus: Set<ReadingStatus> = []
    var formats: Set<Format> = []
    var minRating: Int?
    var authors: Set<String> = []
    var series: Set<String> = []
    var tags: Set<String> = []

    /// The rating floors the sheet offers: a book's rating is 1…5, so `1` is
    /// every book that has one and `0` is every book at all.
    static let ratingRange = 1...5

    static let none = LibraryFilters()

    var isActive: Bool { selectedCount > 0 }

    /// **What the indicator counts**: every value the reader has selected, across
    /// every axis — not the number of axes in use. Three authors and one format
    /// is four filters on, and an indicator reading "2" over a library narrowed
    /// by four values would be a number that means something else.
    var selectedCount: Int {
        readStatus.count + formats.count + authors.count + series.count + tags.count + (minRating == nil ? 0 : 1)
    }

    var hasRatingFloor: Bool { minRating != nil }

    // MARK: What travels

    /// The contract's parameters, and **only the axes that carry something**.
    ///
    /// One item per value, sorted so the same set always composes the same
    /// request: a `Set` has no order, and a request whose parameter order moved
    /// between two runs would be a test that flakes rather than a client that
    /// differs.
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        append(&items, "authors", authors.sorted())
        append(&items, "series", series.sorted())
        append(&items, "tags", tags.sorted())
        append(&items, "formats", formats.map(\.rawValue).sorted())
        append(&items, "readStatus", readStatus.map(\.rawValue).sorted())
        if let minRating { items.append(URLQueryItem(name: "minRating", value: String(minRating))) }
        return items
    }

    private func append(_ items: inout [URLQueryItem], _ name: String, _ values: [String]) {
        for value in values {
            items.append(URLQueryItem(name: name, value: value))
        }
    }

    // MARK: Changing it

    /// Clearing is one operation rather than six removals, because 3.13's whole
    /// requirement is a single control that undoes all of them — and a `clear`
    /// that had to remember each axis is a clear that a seventh axis would
    /// silently half-do.
    mutating func clear() { self = .none }

    mutating func toggle(_ status: ReadingStatus) { Self.toggle(status, in: &readStatus) }
    mutating func toggle(_ format: Format) { Self.toggle(format, in: &formats) }
    mutating func toggle(_ value: String, in axis: Axis) {
        switch axis {
        case .authors: Self.toggle(value, in: &authors)
        case .series: Self.toggle(value, in: &series)
        case .tags: Self.toggle(value, in: &tags)
        }
    }

    func selected(in axis: Axis) -> Set<String> {
        switch axis {
        case .authors: authors
        case .series: series
        case .tags: tags
        }
    }

    private static func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    // MARK: The probe's own encoding

    /// This filter set as one string a probe can pass in and read back —
    /// `status=reading;format=epub;rating=4;author=Kotler`.
    ///
    /// It exists so a run's *own log line* says what the run applied, which is
    /// what turns "the grid has two covers in the frame" into a reading. It is a
    /// diagnostic seam and not a wire format: `;`, `|` and `=` are its
    /// separators, and a facet value containing one would not survive the round
    /// trip. The values this app actually filters on are names, series and tags.
    var probeEncoding: String {
        var tokens: [String] = []
        if !readStatus.isEmpty { tokens.append("status=" + readStatus.map(\.rawValue).sorted().joined(separator: "|")) }
        if !formats.isEmpty { tokens.append("format=" + formats.map(\.rawValue).sorted().joined(separator: "|")) }
        if let minRating { tokens.append("rating=\(minRating)") }
        for axis in Axis.allCases {
            let values = selected(in: axis).sorted()
            guard !values.isEmpty else { continue }
            tokens.append("\(axis.probeName)=" + values.joined(separator: "|"))
        }
        return tokens.joined(separator: ";")
    }

    /// A probe's encoding, read back — with **what it could not use** returned
    /// beside it.
    ///
    /// The second half is the point. A seam no tap can reach is driven by a
    /// string, and a string a build silently ignores is a run that looks green
    /// and decides nothing — slice 3a's own trap in a new costume, which is why
    /// `LibrarySort.stored` logs when it falls back. An unrecognised axis, an
    /// unknown format and a rating outside 1…5 are all reported rather than
    /// dropped.
    static func probe(_ raw: String) -> (filters: LibraryFilters, ignored: [String]) {
        var filters = LibraryFilters()
        var ignored: [String] = []
        for token in raw.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                ignored.append(token)
                continue
            }
            let values = parts[1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            switch parts[0] {
            case "status":
                for value in values {
                    guard let status = ReadingStatus(rawValue: value) else { ignored.append(value); continue }
                    filters.readStatus.insert(status)
                }
            case "format":
                for value in values {
                    guard let format = Format(rawValue: value) else { ignored.append(value); continue }
                    filters.formats.insert(format)
                }
            case "rating":
                guard values.count == 1, let rating = Int(values[0]), ratingRange.contains(rating) else {
                    ignored.append(token)
                    continue
                }
                filters.minRating = rating
            case "author":
                filters.authors.formUnion(values)
            case "series":
                filters.series.formUnion(values)
            case "tag":
                filters.tags.formUnion(values)
            default:
                ignored.append(token)
            }
        }
        return (filters, ignored)
    }
}

// MARK: - What the sheet draws on its two vocabulary rows

/// One chip on the sheet's read-status row.
struct StatusOption: Equatable, Identifiable, Sendable {
    let status: ReadingStatus
    /// The Mac's own count for this status, or `nil` when the facets are not in
    /// hand — which draws as no number at all rather than as a zero.
    let count: Int?

    var id: ReadingStatus { status }

    /// The Mac's own labels (`src/components/shared/FilterSidebar.tsx:5-9`), so
    /// the two devices word one state one way.
    var label: String {
        switch status {
        case .unread: "Unread"
        case .reading: "Reading"
        case .read: "Read"
        }
    }
}

/// One chip on the sheet's format row.
struct FormatOption: Equatable, Identifiable, Sendable {
    let format: LibraryFilters.Format
    let count: Int?

    var id: LibraryFilters.Format { format }

    /// The Mac's own rendering of a format value
    /// (`FilterSidebar.tsx:102` uppercases the facet's own string).
    var label: String { format.rawValue.uppercased() }
}

extension LibraryFilters {
    /// The contract's own three statuses, in its own order
    /// (`electron/main/services/api/shape.ts:77-81`).
    ///
    /// Written here rather than made `CaseIterable` on `ReadingStatus`, because
    /// that enum is the *payload's* vocabulary and this is the order a row of
    /// chips is drawn in — two different questions that happen to share three
    /// names.
    static let statusOrder: [ReadingStatus] = [.unread, .reading, .read]

    /// The read-status chips: always the contract's three, in the order above,
    /// with the Mac's counts beside them when the facets are in hand.
    static func statusOptions(_ facets: Facets?) -> [StatusOption] {
        guard let facets else {
            return statusOrder.map { StatusOption(status: $0, count: nil) }
        }
        let counts = countsByValue(facets.readStatus)
        return statusOrder.map { StatusOption(status: $0, count: counts[$0.rawValue] ?? 0) }
    }

    /// The format chips: always the contract's four, in its own order, with the
    /// Mac's counts when they are in hand.
    ///
    /// A format the library holds none of is **shown with a count of zero** rather
    /// than hidden — the Mac's sidebar hides a group with no values, but a
    /// four-item vocabulary that re-orders itself by what the library happens to
    /// hold is a row that moves under the reader's finger. Zero says the same
    /// thing and stays put.
    static func formatOptions(_ facets: Facets?) -> [FormatOption] {
        guard let facets else {
            return Format.allCases.map { FormatOption(format: $0, count: nil) }
        }
        let counts = countsByValue(facets.formats)
        return Format.allCases.map { FormatOption(format: $0, count: counts[$0.rawValue] ?? 0) }
    }

    private static func countsByValue(_ facets: [Facet]) -> [String: Int] {
        facets.reduce(into: [:]) { $0[$1.value] = $1.count }
    }
}
