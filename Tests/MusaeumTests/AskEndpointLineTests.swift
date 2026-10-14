import XCTest

@testable import Musaeum

final class AskEndpointLineTests: XCTestCase {
    private let local = AskCapability(available: true, reason: nil, isLocal: true, host: "localhost:11434", model: "m")

    private func disclosure(host: String, isLocal: Bool) -> AskDisclosure {
        AskDisclosure(
            text: "Sends: title", members: ["title"], rung: .pointer, windowed: false, truncated: [],
            host: host, isLocal: isLocal, model: "m")
    }

    func testBeforeAnyDisclosureTheCapabilitySpeaks() {
        let line = AskEndpointLine.make(disclosure: nil, capability: local)
        XCTAssertEqual(line, AskEndpointLine(isLocal: true, host: "localhost:11434"))
        XCTAssertEqual(line.text, "Local — nothing leaves your Mac.")
    }

    func testADisclosureOverridesAStaleCapability() {
        // The Mac's model was switched to a hosted endpoint after the sheet's first health read.
        let line = AskEndpointLine.make(
            disclosure: disclosure(host: "api.example.com", isLocal: false), capability: local)
        XCTAssertEqual(line, AskEndpointLine(isLocal: false, host: "api.example.com"))
        XCTAssertEqual(line.text, "Remote — api.example.com receives this.")
    }

    func testTheOtherWayRoundToo() {
        let remote = AskCapability(available: true, reason: nil, isLocal: false, host: "api.example.com", model: "m")
        let line = AskEndpointLine.make(disclosure: disclosure(host: "127.0.0.1:8799", isLocal: true), capability: remote)
        XCTAssertTrue(line.isLocal)
        XCTAssertEqual(line.host, "127.0.0.1:8799")
    }
}
