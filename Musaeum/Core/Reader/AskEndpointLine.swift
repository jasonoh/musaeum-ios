/// Where the next send goes, as the sheet's *Local / Remote* line reads it.
///
/// The Mac's `disclosure` events carry the endpoint every time (`host`, `isLocal`), and the Mac's
/// model setting can change while the sheet lives, so the freshest disclosure wins; the capability
/// (one `/api/health` read at first open) only speaks before any disclosure has arrived.
struct AskEndpointLine: Equatable {
    let isLocal: Bool
    let host: String

    static func make(disclosure: AskDisclosure?, capability: AskCapability) -> AskEndpointLine {
        if let disclosure { return AskEndpointLine(isLocal: disclosure.isLocal, host: disclosure.host) }
        return AskEndpointLine(isLocal: capability.isLocal, host: capability.host)
    }

    var text: String { isLocal ? "Local — nothing leaves your Mac." : "Remote — \(host) receives this." }
}
