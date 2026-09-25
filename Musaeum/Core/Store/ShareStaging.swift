import Foundation

/// **What the recipient gets, and how it gets there.**
///
/// A download is stored under the book's id (`<id>.<format>`, `DownloadStore`),
/// because the id is the only name the wire carries — so sharing the stored file
/// directly hands the recipient `540bd9a6-9d3f-….epub`: a file they cannot
/// identify in any list, on any device, ever. This is the rule that answers that,
/// with a name derived from the contract's own fields and a copy made where the
/// share sheet can read it.
///
/// Nothing here is a store. A staged share is transient by construction — every
/// stage sweeps what the last one left — so CD3's local-state inventory is
/// untouched by it.
enum ShareStaging {
    /// What a stage produced: where the file is, and whether it is **the same
    /// file** as the download (a hard link, so no bytes were copied at all) or a
    /// second copy of it.
    struct Staged: Equatable, Sendable {
        let url: URL
        let linked: Bool
    }

    /// Where a staged share lives, under whatever root the store was given:
    /// `Application Support/Musaeum/Share/`, beside `Books/` — it is a copy of
    /// something in there, and belongs on the same volume as it.
    static func directory(in root: URL) -> URL {
        root.appendingPathComponent("Share", isDirectory: true)
    }

    /// The longest stem this rule produces, in **UTF-8 bytes**.
    ///
    /// Bytes, not characters, and 180 of them: a filesystem name is capped at 255
    /// bytes, an emoji is four bytes per character, and 180 leaves the byline, the
    /// separator and the extension the room they need. Clipping by character
    /// count would blow the limit on exactly the titles most likely to carry
    /// emoji, which is a defect that appears only for some books.
    static let stemByteLimit = 180

    /// `Title - Author.ext`, from the contract's own fields and the format the
    /// stored file actually holds.
    ///
    /// `fallback` is the book's id, and it is what a title with nothing in it
    /// falls back to: a share called `.epub` is a share the recipient can do
    /// nothing with. It is the **only** fallback — see `fallbackStem`.
    static func fileName(title: String, author: String?, format: String, fallback: String) -> String {
        var stem = joined([safeStem(title), author.map(safeStem) ?? ""])
        if stem.isEmpty {
            stem = fallbackStem(fallback)
        }
        let ext = format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// The last resort, and the one place a name comes from something that is not
    /// prose.
    ///
    /// Sanitised rather than used raw, because an id is a string from the wire like
    /// any other — but when even that leaves nothing (an id of nothing but
    /// separators, or of control characters), the answer is a fixed word rather
    /// than an empty stem: `book.epub` is a file a recipient can act on, and the
    /// book it holds is still the right one, because the bytes and the extension
    /// are what it is opened by.
    static func fallbackStem(_ id: String) -> String {
        let stem = safeStem(id)
        return stem.isEmpty ? "book" : stem
    }

    /// One part of the name: a name is one line, and it has to survive a
    /// filesystem, a mail attachment and whichever list the recipient sees it in.
    static func safeStem(_ raw: String) -> String {
        // A newline or a control character survives a share and comes out as
        // something else on the other side; whitespace collapses in `trimmed`.
        let flattened = raw.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
        // `/` reads as a path separator and macOS shows `:` as a slash, so neither
        // belongs in a name handed to another machine.
        let replaced = flattened
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
        var stem = trimmed(replaced)
        // A name that begins with a dot is a hidden file wherever it lands.
        if stem.hasPrefix(".") {
            stem = "_" + stem.dropFirst()
        }
        return stem
    }

    /// Puts a copy of `source` where the share sheet can read it, under the name
    /// the recipient will see.
    ///
    /// **A hard link first, a copy second.** Both files live in the app's own
    /// container, so linking is the common case — and it is what makes sharing a
    /// 528 MiB book free rather than a second 528 MiB write. `linker` is a seam:
    /// the fallback is a rule with a decider, not a branch only a full disk would
    /// ever reach.
    static func stage(
        source: URL,
        named name: String,
        into directory: URL,
        linker: (URL, URL) throws -> Void = { try FileManager.default.linkItem(at: $0, to: $1) }
    ) throws -> Staged {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // At most one staged share exists at a time, so a name can never collide
        // with a book that has already been sent.
        sweep(directory)
        let destination = directory.appendingPathComponent(name)
        do {
            try linker(source, destination)
            return Staged(url: destination, linked: true)
        } catch {
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: source, to: destination)
            return Staged(url: destination, linked: false)
        }
    }

    /// Empties the staging directory. The sheet's dismissal calls this, so what a
    /// share left does not become a second copy of the library on the phone.
    static func sweep(_ directory: URL) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for entry in entries {
            try? manager.removeItem(at: entry)
        }
    }

    private static func joined(_ parts: [String]) -> String {
        clipped(parts.filter { !$0.isEmpty }.joined(separator: " - "), toBytes: stemByteLimit)
    }

    /// Truncated on a **character** boundary at no more than `limit` UTF-8 bytes,
    /// then trimmed of the whitespace and separator a cut can leave behind — a
    /// stem ending in `-` reads to a recipient as a broken name.
    private static func clipped(_ text: String, toBytes limit: Int) -> String {
        guard text.utf8.count > limit else { return trimmed(text) }
        var kept = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            if used + size > limit { break }
            kept.append(character)
            used += size
        }
        return trimmed(kept)
    }

    /// Runs of whitespace become one space, and the ends lose their padding.
    private static func trimmed(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
    }
}
