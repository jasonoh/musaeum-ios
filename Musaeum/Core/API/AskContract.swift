import Foundation

/// The ask route's request and its five events — `POST /api/ai/ask` in the Mac's
/// `docs/rest-api.md`. Every shape here is read from that document's own blocks (the
/// fixtures `scripts/vendor-contract-fixtures.sh` extracts); nothing restates a payload.
///
/// **"Characters" on this route are UTF-16 code units**, the length JavaScript reports and
/// the unit the Mac measures every cap and offset in. `SectionText` is where the phone
/// counts them.

// MARK: - the request

enum AskMode: String, Equatable, Sendable {
    /// Assemble and disclose; the Mac calls no model.
    case preview
    /// Ask the model to place the book; the Mac answers a verdict, never the reply.
    case probe
    case ask
}

enum AskRung: String, Equatable, Sendable {
    case pointer
    case passage
}

struct AskSection: Equatable, Sendable {
    var label: String?
    /// The section **from its start** — never a window. The Mac scores a probe against the
    /// section's opening and windows the passage itself.
    var text: String?
    /// Where the reader is within `text`, in UTF-16 code units.
    var offset: Int?
    var truncated: Bool

    static let empty = AskSection(label: nil, text: nil, offset: nil, truncated: false)
}

struct AskRequest: Equatable, Sendable {
    var bookId: String
    var mode: AskMode
    var rung: AskRung
    var section: AskSection
    var fraction: Double?
    var selection: String?
    var question: String?

    /// The JSON body. Absent members are **omitted**, not `null`: the contract accepts both,
    /// and omission keeps a preview's request honest about what it does not carry.
    func body() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension AskRequest: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(bookId, forKey: AnyCodingKey("bookId"))
        try container.encode(mode.rawValue, forKey: AnyCodingKey("mode"))
        try container.encode(rung.rawValue, forKey: AnyCodingKey("rung"))
        try container.encode(section, forKey: AnyCodingKey("section"))
        try container.encodeIfPresent(fraction.map { $0.clampedToUnit() }, forKey: AnyCodingKey("fraction"))
        try container.encodeIfPresent(selection, forKey: AnyCodingKey("selection"))
        try container.encodeIfPresent(question, forKey: AnyCodingKey("question"))
    }
}

extension AskSection: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encodeIfPresent(label, forKey: AnyCodingKey("label"))
        try container.encodeIfPresent(text, forKey: AnyCodingKey("text"))
        try container.encodeIfPresent(offset.map { max(0, $0) }, forKey: AnyCodingKey("offset"))
        try container.encode(truncated, forKey: AnyCodingKey("truncated"))
    }
}

// MARK: - the events

enum RecallVerdict: Equatable, Sendable {
    case strong
    case weak
    case unknown
}

enum AskDoneReason: Equatable, Sendable {
    case stop
    case length
    case canceled
    case timeout
    /// A reason a newer Mac invented. It ends the stream all the same.
    case other(String)
}

/// What leaves the Mac for the model, and where — the Mac's own sentence, shown verbatim.
struct AskDisclosure: Decodable, Equatable, Sendable {
    let text: String
    let members: [String]
    let rung: AskRung
    let windowed: Bool
    let truncated: [String]
    let host: String
    let isLocal: Bool
    let model: String?

    init(
        text: String, members: [String], rung: AskRung, windowed: Bool, truncated: [String],
        host: String, isLocal: Bool, model: String?
    ) {
        self.text = text
        self.members = members
        self.rung = rung
        self.windowed = windowed
        self.truncated = truncated
        self.host = host
        self.isLocal = isLocal
        self.model = model
    }

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "ask-disclosure")
        text = try o.string("text")
        members = try o.strings("members")
        let rawRung = try o.string("rung")
        guard let rung = AskRung(rawValue: rawRung) else {
            throw ContractError.malformedField("rung", at: "ask-disclosure", value: rawRung)
        }
        self.rung = rung
        windowed = try o.bool("windowed")
        truncated = try o.strings("truncated")
        let endpoint = try o.object("endpoint", as: Endpoint.self)
        host = endpoint.host
        isLocal = endpoint.isLocal
        model = try o.optionalString("model")
    }

    private struct Endpoint: Decodable {
        let host: String
        let isLocal: Bool

        init(from decoder: any Decoder) throws {
            let o = StrictObject(
                container: try decoder.container(keyedBy: AnyCodingKey.self), path: "ask-disclosure.endpoint")
            host = try o.string("host")
            isLocal = try o.bool("isLocal")
        }
    }
}

enum AskEvent: Equatable, Sendable {
    case disclosure(AskDisclosure)
    case verdict(RecallVerdict)
    case delta(String)
    case done(AskDoneReason)
    case error(String)

    /// One frame, decoded. **`nil` for a name this app does not know** — the contract says
    /// unknown events are ignored by both sides, which is how the route grows without a
    /// version bump. A *known* event whose payload breaks the contract throws.
    static func decode(name: String, data: Data) throws -> AskEvent? {
        let decoder = JSONDecoder()
        switch name {
        case "disclosure":
            return .disclosure(try decoder.decode(AskDisclosure.self, from: data))
        case "verdict":
            return .verdict(try decoder.decode(VerdictBody.self, from: data).verdict)
        case "delta":
            return .delta(try decoder.decode(DeltaBody.self, from: data).text)
        case "done":
            return .done(try decoder.decode(DoneBody.self, from: data).reason)
        case "error":
            return .error(try decoder.decode(ErrorBody.self, from: data).message)
        default:
            return nil
        }
    }

    private struct VerdictBody: Decodable {
        let verdict: RecallVerdict
        init(from decoder: any Decoder) throws {
            let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "ask-verdict")
            // A value this app does not know is *unverified* — the safe reading, and the one that
            // widens nothing.
            switch try o.string("value") {
            case "strong": verdict = .strong
            case "weak": verdict = .weak
            default: verdict = .unknown
            }
        }
    }

    private struct DeltaBody: Decodable {
        let text: String
        init(from decoder: any Decoder) throws {
            let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "ask-delta")
            text = try o.string("text")
        }
    }

    private struct DoneBody: Decodable {
        let reason: AskDoneReason
        init(from decoder: any Decoder) throws {
            let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "ask-done")
            switch try o.string("reason") {
            case "stop": reason = .stop
            case "length": reason = .length
            case "canceled": reason = .canceled
            case "timeout": reason = .timeout
            case let other: reason = .other(other)
            }
        }
    }

    private struct ErrorBody: Decodable {
        let message: String
        init(from decoder: any Decoder) throws {
            let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "ask-error")
            message = try o.string("message")
        }
    }
}
