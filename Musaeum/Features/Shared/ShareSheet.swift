import SwiftUI
import UIKit

/// What a door hands the sheet: the staged file, and the title a probe line (and
/// a future `SharePreview`) can name it by.
struct ShareRequest: Identifiable, Sendable {
    let title: String
    let fileURL: URL
    var id: String { fileURL.path }
}

@MainActor
extension ShareRequest {
    /// The door's own work, in one place so both doors do it identically: stage
    /// the book's file under the name a recipient can read, and say so in the
    /// probe log.
    ///
    /// Returns `nil` — not an error — when the phone holds no file for this book,
    /// which is the condition both screens already use to decide whether the door
    /// exists at all. A **thrown** error means the file is there and could not be
    /// staged, which is the case each screen reports in its own place: the detail
    /// screen has a line for it, the shelf has only an alert.
    static func staged(for book: ContractBook, in downloads: DownloadStore) throws -> ShareRequest? {
        guard let staged = try downloads.stagedForSharing(book) else { return nil }
        let bytes = (try? staged.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        Probe.log(
            "share staged book=\(book.id) name=\(staged.url.lastPathComponent) "
                + "linked=\(staged.linked ? 1 : 0) bytes=\(bytes)"
        )
        return ShareRequest(title: book.title, fileURL: staged.url)
    }
}

/// The system share sheet, presented as the sheet it is: AirDrop, Mail, Messages
/// and everything else that can take this file.
///
/// **Why a representable rather than `ShareLink`.** A file URL is resolved when
/// the transfer runs, so the staged copy has to exist before the sheet is built —
/// and with `ShareLink` the only place to build it is the row's `body`, where
/// copying a 528 MiB book would happen by scrolling. A button that stages and
/// then presents says when, and it is the same shape the reader's own door on
/// these two screens already uses (`@State` + a presentation modifier).
struct ShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
