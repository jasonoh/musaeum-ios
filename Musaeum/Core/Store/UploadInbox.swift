import Foundation

/// **The app's half of "Copy to Musaeum"** — the only hand-off this client has,
/// and the reason it needs no entitlement.
///
/// F2 weighed two shapes for the share sheet, and both assumed an *extension*: a
/// second target plus either an app-group container or a keychain access group.
/// Measured against this app's own signing, that assumption decided the fork —
/// App Groups and Keychain Sharing are Apple Developer Program capabilities, the
/// app is signed with a **free personal team**, and adding either stops the
/// profile being issued, so the app itself would stop installing on the owner's
/// iPhone. The simulator ignores provisioning, so every gate in this repo would
/// have stayed green while the phone could no longer run the app: a green
/// instrument over a broken product.
///
/// The route with no capability at all is the system's own. With the four document
/// types declared and `LSSupportsOpeningDocumentsInPlace` false, Files, Safari and
/// Mail offer **Copy to Musaeum**; iOS copies the file into this app's own
/// `Documents/Inbox` and opens the app, which then sends it through exactly the
/// path the picker uses. The token never leaves this process (invariant 10), and
/// there is no second binary to keep in step.
///
/// **The price, stated rather than discovered:** the share sheet shows a plain
/// row against a rich extension panel, one file at a time, and Musaeum comes to
/// the foreground — which is also where the progress and the refusal's own words
/// already live.
enum UploadInbox {
    /// Where the system leaves what another app handed over. iOS creates this
    /// directory for a document-handling app; a scan of a directory that does not
    /// exist is simply empty, which is the state on a phone that has never
    /// received a share.
    static func directory(container: URL? = nil) -> URL {
        let documents = container ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// **What to send, or why not** — a rule over one URL, so the four states a
    /// share can arrive in (a book, a directory the system called a file, a file
    /// that is already gone, a file this app will not send) are decidable without a
    /// share sheet. The refusal is the app's own: nothing was asked of the Mac.
    static func incoming(_ url: URL) -> Result<URL, Refusal> {
        let name = url.lastPathComponent
        guard url.isFileURL, UploadFile.format(for: url) != nil else {
            return .failure(.unsendable(name))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path)
        else {
            return .failure(.unreadable(name))
        }
        return .success(url)
    }

    /// **Everything the system has left and no send has taken yet.** A share that
    /// arrives while the app is not configured, or while it is not running at all,
    /// is not lost: the file is in this app's own container, and the next time the
    /// library screen appears the sweep sends it. Name order, so a run over more
    /// than one is repeatable.
    ///
    /// Only files this app will actually send are returned: the system's directory
    /// can hold anything a share ever handed over, including things that are not
    /// books, and a sweep that returned those would make a refusal out of something
    /// the reader never chose.
    static func pending(container: URL? = nil) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory(container: container),
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { if case .success = incoming($0) { return true } else { return false } }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The system's copy goes once the app has taken it. It is not this app's
    /// library — the book now lives on the Mac, and the phone's own copy is the
    /// outbox's, which the send deletes for itself.
    ///
    /// **Only a file inside this app's own Inbox is touched.** The URL comes from
    /// the system and is normally ours, but a URL that is not in the Inbox belongs
    /// to something else, and deleting it would be this app reaching outside its
    /// own container (invariant 2's shape, one directory over).
    static func discard(_ url: URL, container: URL? = nil) {
        let inbox = directory(container: container).standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(inbox + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
