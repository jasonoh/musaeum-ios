import SwiftUI

/// The book's shelves, as a checklist — **the phone's only membership surface**
/// (D11): each tap is exactly one `PUT` or `DELETE`, and the row refreshes from
/// the book the Mac answers with (F6), never from a local flip.
///
/// **A failure is a sentence under the list** (CD7), and the checklist stays as
/// it was: the Mac's writes are idempotent (D10 — an existing member keeps its
/// `added_at`, removing a non-member is a 200), so the retry is a second tap and
/// nothing has to be unwound.
///
/// **The sheet is a presentation, not a decider.** Everything it needs —
/// the list, the membership, the in-flight write, the failure line — lives on
/// `BookDetailModel`, which is also what the probe's `ACTION=shelf-toggle` drives;
/// this view adds no rule of its own.
struct ShelfChecklistSheet: View {
    let model: BookDetailModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.shelves.isEmpty {
                        Text("No shelves yet.")
                            .font(.callout)
                            .foregroundStyle(Palette.muted)
                    }
                    ForEach(model.shelves) { shelf in
                        row(shelf)
                    }
                    if let failure = model.shelfFailure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                .padding(16)
            }
            .background(Palette.ink)
            .navigationTitle("Shelves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Palette.gold)
        // A refresh on the way in: the library's own load may have been minutes
        // ago, and this is the moment the answer is about to be drawn.
        .task { await model.loadShelves() }
    }

    /// One row: the shelf, its check, and — while its own write is in flight —
    /// the spinner that says so. Every row is disabled while any write is in
    /// flight: two toggles at once would be two answers racing to replace the
    /// same book.
    private func row(_ shelf: Shelf) -> some View {
        let on = model.book?.shelves.contains(shelf.id) == true
        return Button {
            Task { await model.toggle(shelf) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Palette.gold : Palette.muted)
                Text(shelf.name)
                    .font(.body)
                    .foregroundStyle(Palette.parchment)
                Spacer(minLength: 0)
                if model.toggling == shelf.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.muted)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Palette.raised, in: .rect(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.toggling != nil)
        .accessibilityLabel("\(shelf.name), \(on ? "on" : "off")")
    }
}
