import Foundation

/// What the UI needs to know before it offers Ask: whether it works, why not, and where a
/// question would go. The wire's `health.ai` is one source of it; a future backend that talks
/// to a model directly would be another, which is why the UI reads *this* and not the wire type.
struct AskCapability: Equatable, Sendable {
    var available: Bool
    /// Why Ask is off, in words a reader can act on. `nil` when it is on.
    var reason: String?
    /// Nothing sent leaves the Mac (or, for a direct backend, the device).
    var isLocal: Bool
    var host: String
    var model: String?

    init(available: Bool, reason: String?, isLocal: Bool, host: String, model: String?) {
        self.available = available
        self.reason = reason
        self.isLocal = isLocal
        self.host = host
        self.model = model
    }

    init(_ wire: HealthAI) {
        self.init(
            available: wire.available, reason: wire.reason, isLocal: wire.isLocal,
            host: wire.host, model: wire.model)
    }
}

/// The seam between the reader's Ask sheet and wherever answers come from (design D1).
///
/// The sheet consumes `AskEvent`s and nothing else, so it does not know that the tokens came from
/// the Mac. `RelayBackend` is the only implementation: a `DirectBackend` — the phone calling an
/// OpenAI-compatible endpoint itself — would have to assemble prompts on the phone, which means a
/// Swift port of the Mac's `shared/ask` modules against shared golden fixtures. That is deliberately
/// not built; this protocol is what keeps it possible without the UI moving.
protocol AskBackend: Sendable {
    func capability() async throws -> AskCapability
    func ask(_ request: AskRequest) -> AsyncThrowingStream<AskEvent, Error>
}

/// Ask through the Mac: `GET /api/health` for the capability, `POST /api/ai/ask` for the answer.
struct RelayBackend: AskBackend {
    let client: MusaeumClient

    func capability() async throws -> AskCapability {
        let health = try await client.health()
        guard let ai = health.ai else {
            return AskCapability(
                available: false,
                reason: "This Mac's Musaeum is too old to answer questions — update it.",
                isLocal: true, host: "", model: nil)
        }
        return AskCapability(ai)
    }

    func ask(_ request: AskRequest) -> AsyncThrowingStream<AskEvent, Error> {
        client.ask(request)
    }
}
