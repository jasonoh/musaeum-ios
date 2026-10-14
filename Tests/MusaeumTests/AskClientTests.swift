import XCTest

@testable import Musaeum

final class AskClientTests: XCTestCase {
    private let base = URL(string: "http://100.64.0.1:8788")!

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: AskClientTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("the contract fixture \(name).json is not in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// A frame as the Mac writes it, built from the document's own payload block.
    private func frame(_ event: String, _ name: String) throws -> String {
        let line = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: fixture(name)))
        return "event: \(event)\ndata: \(String(decoding: line, as: UTF8.self))\n\n"
    }

    private func client(_ handler: @escaping (URLRequest) -> StubURLProtocol.Response) -> MusaeumClient {
        StubURLProtocol.configure(handler)
        return MusaeumClient(base: base, token: "test-token", session: StubURLProtocol.session())
    }

    private let request = AskRequest(
        bookId: "b1", mode: .ask, rung: .pointer,
        section: AskSection(label: "Chapter 4", text: nil, offset: nil, truncated: false),
        fraction: 0.42, selection: nil, question: "What is this about?"
    )

    private func collect(_ stream: AsyncThrowingStream<AskEvent, Error>) async throws -> [AskEvent] {
        var events: [AskEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    // MARK: the request

    func testTheRequestIsAPostWithTheBearerAndAJSONBodyAndNothingElseSecret() throws {
        let urlRequest = try MusaeumClient.askRequest(base: base, token: "test-token", request: request)
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.url?.path, "/api/ai/ask")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(urlRequest.timeoutInterval, 45)
        let body = String(decoding: try XCTUnwrap(urlRequest.httpBody), as: UTF8.self)
        XCTAssertFalse(body.contains("test-token"), "the token lives in the header and nowhere else (invariant 10)")
    }

    // MARK: the stream

    func testAStreamIsDecodedInOrderAndEndsAtDone() async throws {
        let text = try frame("disclosure", "ask-disclosure") + frame("delta", "ask-delta")
            + frame("delta", "ask-delta") + frame("done", "ask-done")
        let client = client { _ in
            StubURLProtocol.Response(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(text.utf8))
        }
        let events = try await collect(client.ask(request))

        XCTAssertEqual(events.count, 4)
        guard case .disclosure = events[0], case .delta = events[1], case .delta = events[2] else {
            return XCTFail("order lost: \(events)")
        }
        XCTAssertEqual(events[3], .done(.stop))
    }

    func testEventsArrivingInPiecesStillDecode() async throws {
        let text = try frame("delta", "ask-delta") + frame("done", "ask-done")
        let bytes = Array(text.utf8)
        // Cut into 7-byte reads — some will end inside a frame, some inside a multi-byte character
        let chunks = stride(from: 0, to: bytes.count, by: 7).map { Data(bytes[$0 ..< min($0 + 7, bytes.count)]) }
        let client = client { _ in StubURLProtocol.Response(status: 200, chunks: chunks) }

        let events = try await collect(client.ask(request))
        XCTAssertEqual(events.count, 2)
    }

    func testAHeartbeatAndAnUnknownEventAreIgnored() async throws {
        let text = ": ping\n\nevent: citation\ndata: {\"section\":\"x\"}\n\n" + (try frame("done", "ask-done"))
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data(text.utf8)) }
        let events = try await collect(client.ask(request))
        XCTAssertEqual(events, [.done(.stop)])
    }

    func testAnErrorEventEndsTheStreamAsAnOutcomeNotAThrow() async throws {
        let text = try frame("disclosure", "ask-disclosure") + frame("error", "ask-error")
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data(text.utf8)) }
        let events = try await collect(client.ask(request))
        guard case .error? = events.last else { return XCTFail("expected a trailing error event: \(events)") }
    }

    /// **The Review Focus case.** The Mac quit, the tailnet dropped, or the app was
    /// backgrounded mid-answer: the bytes just stop. That is a failure, and reporting it as
    /// a finished answer would present half a sentence as the whole of one.
    func testAStreamThatEndsWithoutATerminalEventThrows() async throws {
        let text = try frame("delta", "ask-delta")
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data(text.utf8)) }
        do {
            _ = try await collect(client.ask(request))
            XCTFail("a truncated stream finished cleanly")
        } catch let error as ClientError {
            guard case .unreachable = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    func testAStreamCutMidEventDoesNotDecodeTheCutEvent() async throws {
        let whole = try frame("delta", "ask-delta")
        let cut = String(whole.dropLast(8))  // inside the JSON, before the blank line
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data(cut.utf8)) }
        do {
            _ = try await collect(client.ask(request))
            XCTFail("a cut stream finished cleanly")
        } catch let error as ClientError {
            guard case .unreachable = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    func testAKnownEventWithABrokenPayloadThrowsADecodingError() async throws {
        let text = "event: delta\ndata: {\"nope\":1}\n\n"
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data(text.utf8)) }
        do {
            _ = try await collect(client.ask(request))
            XCTFail("a broken payload was accepted")
        } catch let error as ClientError {
            guard case .decoding = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    /// Cancelling the task that reads the stream must close the connection — the Mac reads that
    /// as the reader leaving — and must end the stream rather than leave the consumer waiting.
    func testCancellingTheConsumerClosesTheConnectionAndEndsTheStream() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data(), delay: 30) }
        let stream = client.ask(request)
        let consumer = Task {
            var events: [AskEvent] = []
            for try await event in stream { events.append(event) }
            return events
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "the request should be in flight")

        consumer.cancel()
        let started = ContinuousClock.now
        let outcome = await consumer.result
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "the stream did not end on cancel")
        if case let .success(events) = outcome { XCTAssertTrue(events.isEmpty) }

        for _ in 0 ..< 50 where StubURLProtocol.stoppedLoads == 0 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(StubURLProtocol.stoppedLoads, 1, "the connection was not closed")
    }

    // MARK: the refusals before the stream

    func testEachRefusalIsItsOwnState() async throws {
        let cases: [(Int, [String: String], String, ClientError)] = [
            (401, [:], #"{"error":"unauthorized"}"#, .unauthorized),
            (404, [:], #"{"error":"not found"}"#, .notFound),
            (400, [:], #"{"error":"bad request"}"#, .badRequest("bad request")),
            (503, ["Retry-After": "1"], #"{"error":"busy"}"#, .busy(retryAfter: 1)),
            (503, [:], #"{"error":"ai unavailable","reason":"No model set"}"#, .aiUnavailable("No model set")),
        ]
        for (status, headers, body, expected) in cases {
            let client = client { _ in StubURLProtocol.Response(status: status, headers: headers, body: Data(body.utf8)) }
            do {
                _ = try await collect(client.ask(request))
                XCTFail("\(status) was accepted")
            } catch let error as ClientError {
                XCTAssertEqual(error, expected, "status \(status)")
            }
        }
    }

    func testAnUnreachableMacIsAnOrdinaryState() async throws {
        // Port 1 on loopback refuses at once — a real connection, not the stub
        let client = MusaeumClient(base: URL(string: "http://127.0.0.1:1")!, token: "t")
        do {
            _ = try await collect(client.ask(request))
            XCTFail("an unreachable Mac produced events")
        } catch let error as ClientError {
            guard case .unreachable = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: the seam

    func testTheRelayReportsAnOlderMacAsUnavailableWithASentence() async throws {
        var object = try JSONSerialization.jsonObject(with: fixture("health")) as! [String: Any]
        object.removeValue(forKey: "ai")
        let body = try JSONSerialization.data(withJSONObject: object)
        let backend = RelayBackend(client: client { _ in StubURLProtocol.Response(status: 200, body: body) })

        let capability = try await backend.capability()
        XCTAssertFalse(capability.available)
        XCTAssertNotNil(capability.reason)
    }

    func testTheRelayPassesAMacsCapabilityThrough() async throws {
        let body = try fixture("health")
        let backend = RelayBackend(client: client { _ in StubURLProtocol.Response(status: 200, body: body) })

        let capability = try await backend.capability()
        let wire = try XCTUnwrap(JSONDecoder().decode(Health.self, from: body).ai)
        XCTAssertEqual(capability, AskCapability(wire))
    }
}
