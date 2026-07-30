import XCTest
@testable import OpenFlight

@MainActor
final class WiFiShotClientTests: XCTestCase {
    func testBareHostGetsDefaultSchemePortAndPath() {
        XCTAssertEqual(
            WiFiShotClient.streamURL(host: "raspberrypi.local")?.absoluteString,
            "http://raspberrypi.local:8080/api/shots/stream"
        )
    }

    func testExplicitPortIsPreserved() {
        XCTAssertEqual(
            WiFiShotClient.streamURL(host: "10.0.0.10:9000")?.absoluteString,
            "http://10.0.0.10:9000/api/shots/stream"
        )
    }

    func testSurroundingWhitespaceIsTolerated() {
        XCTAssertEqual(
            WiFiShotClient.streamURL(host: "  10.0.0.10  ")?.absoluteString,
            "http://10.0.0.10:8080/api/shots/stream"
        )
    }

    func testPastedURLPathAndQueryAreReplaced() {
        XCTAssertEqual(
            WiFiShotClient.streamURL(host: "http://pi.local:8080/display?x=1")?.absoluteString,
            "http://pi.local:8080/api/shots/stream"
        )
    }

    func testHTTPSHostDoesNotGainTheHTTPDefaultPort() {
        XCTAssertEqual(
            WiFiShotClient.streamURL(host: "https://pi.example.com")?.absoluteString,
            "https://pi.example.com/api/shots/stream"
        )
    }

    func testUnusableHostsAreRejected() {
        XCTAssertNil(WiFiShotClient.streamURL(host: ""))
        XCTAssertNil(WiFiShotClient.streamURL(host: "   "))
        XCTAssertNil(WiFiShotClient.streamURL(host: "ftp://pi.local"))
        XCTAssertNil(WiFiShotClient.streamURL(host: "http://"))
    }

    func testReceivePublishesSharedFixture() throws {
        let client = WiFiShotClient()
        let payload = try sharedShotFixture()

        client.receive(SSEEvent(name: "shot", data: String(decoding: payload, as: UTF8.self)))

        XCTAssertEqual(client.latestShot?.ballSpeedMPH, 151.4)
        XCTAssertEqual(
            client.latestShot?.eventID.uuidString,
            "B0D91F0A-7950-4D7E-9DD5-AF9777C190E1"
        )
    }

    func testReceiveIgnoresReplayWithSameEventID() throws {
        let client = WiFiShotClient()
        let original = try sharedShotFixture()
        var replayObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        replayObject["ball_speed_mph"] = 199.0
        let changedReplay = try JSONSerialization.data(withJSONObject: replayObject)

        client.receive(SSEEvent(name: "shot", data: String(decoding: original, as: UTF8.self)))
        client.receive(SSEEvent(name: "shot", data: String(decoding: changedReplay, as: UTF8.self)))

        XCTAssertEqual(client.latestShot?.ballSpeedMPH, 151.4)
    }

    func testReceiveIgnoresOtherEventNames() throws {
        let client = WiFiShotClient()
        let payload = try sharedShotFixture()

        client.receive(SSEEvent(name: "stats", data: String(decoding: payload, as: UTF8.self)))

        XCTAssertNil(client.latestShot)
        XCTAssertEqual(client.state, .idle)
    }

    func testUnsupportedSchemaSurfacesAsRetryableError() throws {
        let client = WiFiShotClient()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try sharedShotFixture()) as? [String: Any]
        )
        object["schema_version"] = 2
        let payload = try JSONSerialization.data(withJSONObject: object)

        client.receive(SSEEvent(name: "shot", data: String(decoding: payload, as: UTF8.self)))

        XCTAssertNil(client.latestShot)
        XCTAssertTrue(client.state.canRetry)
        XCTAssertEqual(
            client.state,
            .error(ShotDecodeError.unsupportedSchema(2).localizedDescription)
        )
    }

    func testMalformedPayloadDoesNotCrashAndStaysRetryable() {
        let client = WiFiShotClient()

        client.receive(SSEEvent(name: "shot", data: "not json"))

        XCTAssertNil(client.latestShot)
        XCTAssertTrue(client.state.canRetry)
    }

    func testStartWithBlankHostReportsAnActionableError() {
        let client = WiFiShotClient()

        client.start(host: " ")

        XCTAssertEqual(
            client.state,
            .error(WiFiShotError.invalidHost(" ").localizedDescription)
        )
        XCTAssertTrue(client.state.canRetry)
    }

    func testDisconnectReturnsToIdle() {
        let client = WiFiShotClient()
        client.start(host: "")

        client.disconnect()

        XCTAssertEqual(client.state, .idle)
    }
}
