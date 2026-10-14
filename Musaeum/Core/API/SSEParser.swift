import Foundation

/// One server-sent event: its name and its `data` lines joined by newlines.
struct SSEFrame: Equatable, Sendable {
    let event: String
    let data: String
}

/// An incremental server-sent-events parser.
///
/// Chunk boundaries are not event boundaries — a read routinely ends mid-line — so this takes
/// whatever text a read happened to contain and returns the frames it completed. It works on
/// **Unicode scalars, not Characters**: Swift treats `"\r\n"` as a single Character, which would
/// make "split on newline" miss every CRLF-terminated line.
///
/// **A frame exists only once its blank line has arrived, and there is no flush.** The Mac always
/// terminates its events, so an event still open when the bytes stop was cut off — possibly in
/// the middle of its JSON — and decoding it as though it were complete is how a half-sentence
/// becomes an answer. `MusaeumClient.ask` treats a stream that ended without a terminal event
/// as the failure it is.
struct SSEParser: Sendable {
    private var line = String.UnicodeScalarView()
    private var event = "message"
    private var dataLines: [String] = []

    init() {}

    mutating func push(_ chunk: String) -> [SSEFrame] {
        var frames: [SSEFrame] = []
        for scalar in chunk.unicodeScalars {
            guard scalar == "\n" else {
                line.append(scalar)
                continue
            }
            if line.last == "\r" { line.removeLast() }
            if let frame = consume(String(line)) { frames.append(frame) }
            line.removeAll()
        }
        return frames
    }

    private mutating func consume(_ text: String) -> SSEFrame? {
        if text.isEmpty { return dispatch() }
        if text.hasPrefix(":") { return nil }  // a comment — the Mac's `: ping` heartbeat

        let name: String
        var value: String
        if let colon = text.firstIndex(of: ":") {
            name = String(text[..<colon])
            value = String(text[text.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            name = text
            value = ""
        }
        switch name {
        case "event": event = value
        case "data": dataLines.append(value)
        default: break  // `id:` and `retry:` mean nothing to this client
        }
        return nil
    }

    private mutating func dispatch() -> SSEFrame? {
        defer {
            event = "message"
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEFrame(event: event, data: dataLines.joined(separator: "\n"))
    }
}
