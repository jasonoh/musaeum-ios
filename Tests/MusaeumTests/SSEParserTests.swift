import XCTest

@testable import Musaeum

final class SSEParserTests: XCTestCase {
    func testReturnsNothingUntilAFrameIsComplete() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("event: delta\n"), [])
        XCTAssertEqual(parser.push("data: {\"text\":\"a\"}\n"), [])
        XCTAssertEqual(parser.push("\n"), [SSEFrame(event: "delta", data: "{\"text\":\"a\"}")])
    }

    func testSeveralFramesInOneChunk() {
        var parser = SSEParser()
        let frames = parser.push("event: a\ndata: 1\n\nevent: b\ndata: 2\n\n")
        XCTAssertEqual(frames, [SSEFrame(event: "a", data: "1"), SSEFrame(event: "b", data: "2")])
    }

    func testAFrameSplitAtEveryByteBoundaryIsTheSameFrame() {
        let stream = "event: delta\ndata: {\"text\":\"héllo — 🙂\"}\n\n"
        var whole = SSEParser()
        let expected = whole.push(stream)
        XCTAssertEqual(expected.count, 1)

        var parser = SSEParser()
        var collected: [SSEFrame] = []
        for character in stream { collected += parser.push(String(character)) }
        XCTAssertEqual(collected, expected)
    }

    /// The test above feeds one *Character* at a time, but every Character in its stream is a single
    /// scalar and it holds no CRLF, so a Character-wise parser would pass it too. This one feeds one
    /// *scalar* at a time over a stream where the two differ: `\r\n` is one Character, and `e` +
    /// U+0301 is one Character of two scalars.
    func testASplitAtEveryScalarBoundaryIsTheSameFrameEvenAcrossCRLFAndCombiningMarks() {
        let stream = "event: delta\r\ndata: {\"text\":\"cafe\u{301} 🙂\"}\r\n\r\n"
        XCTAssertLessThan(stream.count, stream.unicodeScalars.count)
        var whole = SSEParser()
        let expected = whole.push(stream)
        XCTAssertEqual(expected, [SSEFrame(event: "delta", data: "{\"text\":\"cafe\u{301} 🙂\"}")])

        var parser = SSEParser()
        var collected: [SSEFrame] = []
        for scalar in stream.unicodeScalars { collected += parser.push(String(scalar)) }
        XCTAssertEqual(collected, expected)
    }

    func testCommentLinesAreIgnored() {
        var parser = SSEParser()
        let frames = parser.push(": ping\n\n: ping\nevent: done\ndata: {\"reason\":\"stop\"}\n\n")
        XCTAssertEqual(frames, [SSEFrame(event: "done", data: "{\"reason\":\"stop\"}")])
    }

    func testCRLFIsAccepted() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("event: x\r\ndata: y\r\n\r\n"), [SSEFrame(event: "x", data: "y")])
    }

    func testMultiLineDataJoinsWithANewline() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("data: a\ndata: b\n\n"), [SSEFrame(event: "message", data: "a\nb")])
    }

    func testAnEventWithNoDataIsNotAFrame() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("event: lonely\n\n"), [])
        // …and does not leak its name into the next frame
        XCTAssertEqual(parser.push("data: x\n\n"), [SSEFrame(event: "message", data: "x")])
    }

    /// A stream cut in the middle of an event must not produce that event.
    func testATruncatedFinalEventIsNeverEmitted() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("event: delta\ndata: {\"text\":\"par"), [])
    }

    func testOnlyOneLeadingSpaceAfterTheColonIsStripped() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("data:  two spaces\n\n"), [SSEFrame(event: "message", data: " two spaces")])
        XCTAssertEqual(parser.push("data:none\n\n"), [SSEFrame(event: "message", data: "none")])
    }
}
