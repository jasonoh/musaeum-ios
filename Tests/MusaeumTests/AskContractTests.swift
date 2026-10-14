import XCTest

@testable import Musaeum

/// The ask route's models, decoded from the Mac's own `json payload=` blocks.
/// Nothing here restates a payload: the fixtures are the document.
final class AskContractTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: AskContractTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("the contract fixture \(name).json is not in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// One compact line, as the wire carries it.
    private func compact(_ name: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: fixture(name)))
    }

    private func keyPaths(_ value: Any, prefix: String = "") -> Set<String> {
        guard let object = value as? [String: Any] else { return prefix.isEmpty ? [] : [prefix] }
        return Set(object.flatMap { key, inner in
            keyPaths(inner, prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
        })
    }

    // MARK: health.ai

    func testHealthCarriesTheAIMember() throws {
        let health = try JSONDecoder().decode(Health.self, from: fixture("health"))
        let ai = try XCTUnwrap(health.ai, "the document's health block names an ai member")
        XCTAssertFalse(ai.host.isEmpty)
    }

    /// A Mac older than this feature sends no `ai`; that is "no Ask here", never a decode failure.
    func testAHealthPayloadWithoutAIStillDecodes() throws {
        var object = try JSONSerialization.jsonObject(with: fixture("health")) as! [String: Any]
        object.removeValue(forKey: "ai")
        let health = try JSONDecoder().decode(Health.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(health.ai)
        object["ai"] = NSNull()
        let nulled = try JSONDecoder().decode(Health.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(nulled.ai)
    }

    /// Present means strict again — the exception is for absence only.
    func testAPresentButMalformedAIThrows() throws {
        var object = try JSONSerialization.jsonObject(with: fixture("health")) as! [String: Any]
        object["ai"] = ["available": "yes"]
        XCTAssertThrowsError(try JSONDecoder().decode(Health.self, from: JSONSerialization.data(withJSONObject: object)))
        object["ai"] = ["available": true]  // every other member absent
        XCTAssertThrowsError(try JSONDecoder().decode(Health.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    // MARK: the five events

    func testEveryEventFixtureDecodes() throws {
        XCTAssertNotNil(try AskEvent.decode(name: "disclosure", data: compact("ask-disclosure")))
        XCTAssertEqual(try AskEvent.decode(name: "verdict", data: compact("ask-verdict")), .verdict(.weak))
        XCTAssertNotNil(try AskEvent.decode(name: "delta", data: compact("ask-delta")))
        XCTAssertEqual(try AskEvent.decode(name: "done", data: compact("ask-done")), .done(.stop))
        XCTAssertNotNil(try AskEvent.decode(name: "error", data: compact("ask-error")))
    }

    func testTheDisclosureCarriesWhatTheDocumentNames() throws {
        guard case let .disclosure(disclosure)? = try AskEvent.decode(name: "disclosure", data: compact("ask-disclosure")) else {
            return XCTFail("not a disclosure")
        }
        XCTAssertTrue(disclosure.text.hasPrefix("Sends:"))
        XCTAssertFalse(disclosure.members.isEmpty)
        XCTAssertFalse(disclosure.host.isEmpty)
    }

    func testAnEventNameThisAppDoesNotKnowIsIgnoredNotAnError() throws {
        XCTAssertNil(try AskEvent.decode(name: "citation", data: Data("{\"section\":\"x\"}".utf8)))
    }

    func testAVerdictOrReasonThisAppDoesNotKnowDegradesSafely() throws {
        XCTAssertEqual(try AskEvent.decode(name: "verdict", data: Data("{\"value\":\"maybe\"}".utf8)), .verdict(.unknown))
        XCTAssertEqual(try AskEvent.decode(name: "done", data: Data("{\"reason\":\"filtered\"}".utf8)), .done(.other("filtered")))
    }

    func testAKnownEventMissingItsMemberThrows() {
        XCTAssertThrowsError(try AskEvent.decode(name: "delta", data: Data("{}".utf8)))
        XCTAssertThrowsError(try AskEvent.decode(name: "error", data: Data("{\"text\":\"x\"}".utf8)))
    }

    // MARK: the request

    /// Keys only — the document's example values are not restated here (invariant 1).
    func testTheRequestCarriesExactlyTheMembersTheDocumentNames() throws {
        let request = AskRequest(
            bookId: "b", mode: .ask, rung: .passage,
            section: AskSection(label: "L", text: "T", offset: 1, truncated: false),
            fraction: 0.5, selection: "S", question: "Q"
        )
        let sent = try JSONSerialization.jsonObject(with: request.body())
        let documented = try JSONSerialization.jsonObject(with: fixture("request-ask"))
        XCTAssertEqual(keyPaths(sent), keyPaths(documented))
    }

    func testAbsentMembersAreOmittedNotNull() throws {
        let request = AskRequest(
            bookId: "b", mode: .preview, rung: .pointer,
            section: .empty, fraction: nil, selection: nil, question: nil
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body()) as? [String: Any])
        XCTAssertNil(object["selection"])
        XCTAssertNil(object["question"])
        XCTAssertNil(object["fraction"])
        let section = try XCTUnwrap(object["section"] as? [String: Any])
        XCTAssertNil(section["text"])
        XCTAssertEqual(section["truncated"] as? Bool, false)
    }

    func testTheFractionIsClampedAndTheOffsetNeverNegative() throws {
        let request = AskRequest(
            bookId: "b", mode: .ask, rung: .pointer,
            section: AskSection(label: nil, text: "x", offset: -5, truncated: false),
            fraction: 60, selection: nil, question: "q"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body()) as? [String: Any])
        XCTAssertEqual(object["fraction"] as? Double, 1)
        XCTAssertEqual((object["section"] as? [String: Any])?["offset"] as? Int, 0)
    }
}
