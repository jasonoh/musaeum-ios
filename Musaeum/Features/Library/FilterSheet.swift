import SwiftUI

/// The filter sheet: the axes a text query cannot express, and the facet lists
/// the Mac's own sidebar draws from.
///
/// **Every tick applies immediately**, the way it does on the Mac
/// (`FilterSidebar`'s `toggleFilter` re-runs the query per tick), and the sheet
/// keeps no draft of its own — a second copy of "what is selected" is a second
/// thing that can disagree with the request. The sheet is presented from the
/// library screen's toolbar and dismissed with Done; nothing is lost by
/// dismissing it, because nothing was pending.
///
/// **The two small rows are a vocabulary, and the three big ones are a list.**
/// Read status and format draw the contract's own values in the contract's own
/// order, always — so the sheet is fully usable with the Mac asleep, and a chip
/// never moves under the reader's finger as counts drift. Counts come from the
/// facets when they are in hand and are simply absent when they are not. Author,
/// series and tag have no fixed vocabulary, so their rows are the facet arrays
/// themselves, count-descending as the server sends them, each behind a narrow
/// field: the real library's `authors` facet is 3,727 values, and a list that
/// long is not one anybody reaches the bottom of.
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: LibraryModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    chips(statusOptions.map { option in
                        (key: option.status.rawValue,
                         label: option.label,
                         count: option.count,
                         isOn: model.filters.readStatus.contains(option.status),
                         toggle: { await model.toggle(option.status) })
                    })
                } header: {
                    header("Read status")
                }

                Section {
                    chips(formatOptions.map { option in
                        (key: option.format.rawValue,
                         label: option.label,
                         count: option.count,
                         isOn: model.filters.formats.contains(option.format),
                         toggle: { await model.toggle(option.format) })
                    })
                } header: {
                    header("Format")
                }

                Section {
                    chips(ratingOptions)
                } header: {
                    header("Rating")
                } footer: {
                    Text("Matched against the Mac's own star rating, so “3★” is every book rated three or better.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }

                facetSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.ink)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { clearAll }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: LibraryFilters.Axis.self) { axis in
                FacetList(axis: axis, model: model)
            }
            // **Fetched when the sheet opens, never with a library page** (the
            // annex's own reading): a request per page for counts nobody has asked
            // to see, on a screen whose whole cost model is latency. A failure here
            // is not a failure of the library — the two small rows still draw, and
            // the three big ones say what happened.
            .task { await model.loadFacets() }
        }
        .tint(Palette.gold)
    }

    // MARK: The rows

    private var statusOptions: [StatusOption] { LibraryFilters.statusOptions(model.facets) }
    private var formatOptions: [FormatOption] { LibraryFilters.formatOptions(model.facets) }

    /// The rating floor, with the contract's own range — a book carries 1…5, so
    /// "Any" and the five floors are the whole of it.
    private var ratingOptions: [ChipSpec] {
        [(key: "any", label: "Any", count: nil, isOn: !model.filters.hasRatingFloor, toggle: { await model.setRatingFloor(nil) })]
            + LibraryFilters.ratingRange.map { floor in
                (key: "rating-\(floor)",
                 label: "\(floor)★",
                 count: nil,
                 isOn: model.filters.minRating == floor,
                 toggle: { await model.setRatingFloor(floor) })
            }
    }

    @ViewBuilder
    private var facetSection: some View {
        Section {
            ForEach(LibraryFilters.Axis.allCases, id: \.self) { axis in
                NavigationLink(value: axis) {
                    HStack(spacing: 8) {
                        Text(axis.title)
                            .foregroundStyle(Palette.parchment)
                        Spacer(minLength: 8)
                        Text(facetSubtitle(axis))
                            .font(.footnote)
                            .foregroundStyle(isNarrowed(axis) ? Palette.gold : Palette.muted)
                    }
                }
            }
        } header: {
            header("More")
        } footer: {
            facetFooter
        }
    }

    private func facetSubtitle(_ axis: LibraryFilters.Axis) -> String {
        let selected = model.filters.selected(in: axis).count
        guard let facets = model.facets else { return selected > 0 ? "\(selected) selected" : "—" }
        let total = axis.values(in: facets).count
        return selected > 0 ? "\(selected) of \(total)" : "\(total)"
    }

    private func isNarrowed(_ axis: LibraryFilters.Axis) -> Bool {
        !model.filters.selected(in: axis).isEmpty
    }

    /// The failure is a surface (CD7), and this is the one place in the sheet
    /// where a missing answer changes what can be done — the two vocabularies
    /// above are drawn from the contract and need no request at all.
    @ViewBuilder
    private var facetFooter: some View {
        if case let .failed(message) = model.facetsPhase {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("The Mac is not answering, so the author, series and tag lists are not here: \(message)")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Button("Try again") { Task { await model.loadFacets() } }
                    .font(.caption)
            }
        } else if model.facets == nil {
            Text("Loading the library's own lists…")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private var clearAll: some View {
        Button("Clear all") { Task { await model.clearFilters() } }
            .disabled(!model.hasActiveFilters)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.muted)
            .textCase(nil)
    }

    /// A wrapping grid of chips. `GridItem(.adaptive:)` does the wrapping rather
    /// than a hand-rolled flow layout: the rows here are three, four and six
    /// items, and one adaptive grid holds all three without a second mechanism.
    private func chips(_ specs: [ChipSpec]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(specs, id: \.key) { spec in
                Chip(spec)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One chip's whole specification — a value, the Mac's count for it when there is
/// one, and the door that toggles it. Built in the view body and consumed by
/// `Chip`, so the two chip rows and the rating row are one code path.
typealias ChipSpec = (key: String, label: String, count: Int?, isOn: Bool, toggle: () async -> Void)

private struct Chip: View {
    let spec: ChipSpec

    init(_ spec: ChipSpec) { self.spec = spec }

    var body: some View {
        Button {
            Task { await spec.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(spec.label)
                    .font(.subheadline.weight(spec.isOn ? .semibold : .regular))
                    .lineLimit(1)
                // A count of `nil` is "the facets are not in hand", and it draws as
                // nothing rather than as a zero: a chip reading "0" says the library
                // holds none, which is a different and stronger claim.
                if let count = spec.count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(spec.isOn ? Palette.gold : Palette.raised, in: .capsule)
            .foregroundStyle(spec.isOn ? Palette.ink : Palette.parchment)
            .overlay(
                Capsule().stroke(spec.isOn ? Palette.gold : Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// One of the three long lists, pushed from the sheet.
///
/// The values are **the contract's own, in the order it returned them** — count
/// descending, no client-side rank and no top-N cut — and the narrow field is what
/// makes the tail reachable. A value the reader has selected and the library no
/// longer holds is not in this list; the sheet's own **Clear all** is what undoes
/// anything this list cannot show.
struct FacetList: View {
    let axis: LibraryFilters.Axis
    let model: LibraryModel

    @State private var narrow = ""

    var body: some View {
        List {
            if let facets = model.facets {
                let values = axis.values(in: facets)
                let shown = matching(values)
                if values.isEmpty {
                    Text(axis.emptyNote).foregroundStyle(Palette.muted)
                } else if shown.isEmpty {
                    Text("Nothing matches “\(narrow)”.").foregroundStyle(Palette.muted)
                } else {
                    ForEach(shown, id: \.value) { facet in
                        row(facet)
                    }
                }
            } else if case let .failed(message) = model.facetsPhase {
                Text("The Mac is not answering — \(message)").foregroundStyle(Palette.muted)
            } else {
                ProgressView().tint(Palette.gold)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.ink)
        .navigationTitle(axis.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $narrow, prompt: axis.prompt)
        .tint(Palette.gold)
    }

    /// Narrowed **case-insensitively on a substring**, because a phone keyboard
    /// and a title-cased author are the two things a prefix match gets wrong:
    /// "corey" has to find "James S. A. Corey".
    private func matching(_ values: [Facet]) -> [Facet] {
        let term = narrow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return values }
        return values.filter { $0.value.localizedCaseInsensitiveContains(term) }
    }

    private func row(_ facet: Facet) -> some View {
        let isOn = model.filters.selected(in: axis).contains(facet.value)
        return Button {
            Task { await model.toggle(facet.value, in: axis) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Palette.gold : Palette.muted)
                Text(facet.value)
                    .foregroundStyle(isOn ? Palette.gold : Palette.parchment)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(facet.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.muted)
            }
        }
        .buttonStyle(.plain)
    }
}
