import XCTest
@testable import OpenFlight

final class SSEEventParserTests: XCTestCase {
    func testByteStreamPreservesBlankLineAndDispatchesEvent() {
        var parser = SSEByteStreamParser()
        let wireEvent = "event: shot\ndata: {\"schema_version\":1}\n\n"

        let events = wireEvent.utf8.compactMap { parser.append(byte: $0) }

        XCTAssertEqual(
            events,
            [SSEEvent(name: "shot", data: "{\"schema_version\":1}")]
        )
    }

    func testByteStreamHandlesCRLFAndConsecutiveEvents() {
        var parser = SSEByteStreamParser()
        let stream = "data: first\r\n\r\ndata: second\r\n\r\n"

        let events = stream.utf8.compactMap { parser.append(byte: $0) }

        XCTAssertEqual(
            events,
            [
                SSEEvent(name: nil, data: "first"),
                SSEEvent(name: nil, data: "second"),
            ]
        )
    }

    func testByteStreamResetDiscardsPartialLineAndEvent() {
        var parser = SSEByteStreamParser()
        for byte in "event: shot\ndata: partial".utf8 {
            XCTAssertNil(parser.append(byte: byte))
        }

        parser.reset()
        let events = "data: replacement\n\n".utf8.compactMap { parser.append(byte: $0) }

        XCTAssertEqual(events, [SSEEvent(name: nil, data: "replacement")])
    }

    func testBlankLineDispatchesNamedEvent() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: "event: shot"))
        XCTAssertNil(parser.append(line: "data: {\"schema_version\":1}"))
        let event = parser.append(line: "")

        XCTAssertEqual(event, SSEEvent(name: "shot", data: "{\"schema_version\":1}"))
    }

    func testHeartbeatCommentsAreIgnored() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: ": ping"))
        XCTAssertNil(parser.append(line: ""))
    }

    func testBlankLineWithoutDataDispatchesNothing() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: "event: shot"))
        XCTAssertNil(parser.append(line: ""))
    }

    func testMultipleDataLinesAreJoinedWithNewlines() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: "data: first"))
        XCTAssertNil(parser.append(line: "data: second"))

        XCTAssertEqual(parser.append(line: "")?.data, "first\nsecond")
    }

    func testCarriageReturnsAreStripped() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: "event: shot\r"))
        XCTAssertNil(parser.append(line: "data: payload\r"))

        XCTAssertEqual(parser.append(line: "\r"), SSEEvent(name: "shot", data: "payload"))
    }

    func testOnlyOneSpaceAfterTheColonIsDropped() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: "data:  padded"))

        XCTAssertEqual(parser.append(line: "")?.data, " padded")
    }

    func testValueWithoutSpaceAfterColonIsKept() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: "data:{\"a\":1}"))

        XCTAssertEqual(parser.append(line: "")?.data, "{\"a\":1}")
    }

    func testUnknownFieldsAreIgnored() {
        var parser = SSEEventParser()

        XCTAssertNil(parser.append(line: "id: 7"))
        XCTAssertNil(parser.append(line: "retry: 3000"))
        XCTAssertNil(parser.append(line: "data: payload"))

        XCTAssertEqual(parser.append(line: ""), SSEEvent(name: nil, data: "payload"))
    }

    func testConsecutiveEventsDoNotLeakState() {
        var parser = SSEEventParser()

        _ = parser.append(line: "event: shot")
        _ = parser.append(line: "data: first")
        _ = parser.append(line: "")

        XCTAssertNil(parser.append(line: "data: second"))
        XCTAssertEqual(parser.append(line: ""), SSEEvent(name: nil, data: "second"))
    }

    func testResetDiscardsPartialEvent() {
        var parser = SSEEventParser()

        _ = parser.append(line: "data: partial")
        parser.reset()

        XCTAssertNil(parser.append(line: ""))
    }
}
