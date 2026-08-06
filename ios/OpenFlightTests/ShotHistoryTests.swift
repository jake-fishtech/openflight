import XCTest
@testable import OpenFlight

final class ShotHistoryTests: XCTestCase {
    func testRecordKeepsNewestShotFirstAndIgnoresDuplicates() {
        let first = makeShot(ballSpeedMPH: 140)
        let second = makeShot(ballSpeedMPH: 151)
        var history = ShotHistory(maximumCount: 10)

        history.record(first)
        history.record(second)
        history.record(first)

        XCTAssertEqual(history.shots.map(\.eventID), [second.eventID, first.eventID])
        XCTAssertEqual(history.latestShot, second)
    }

    func testRecordDropsOldestShotsAtCapacity() {
        let first = makeShot(ballSpeedMPH: 140)
        let second = makeShot(ballSpeedMPH: 145)
        let third = makeShot(ballSpeedMPH: 150)
        var history = ShotHistory(maximumCount: 2)

        history.record(first)
        history.record(second)
        history.record(third)

        XCTAssertEqual(history.shots.map(\.eventID), [third.eventID, second.eventID])
    }

    private func makeShot(ballSpeedMPH: Double) -> ShotEvent {
        ShotEvent(
            schemaVersion: 1,
            eventID: UUID(),
            timestamp: "2026-08-05T23:54:00",
            club: "driver",
            ballSpeedMPH: ballSpeedMPH,
            clubSpeedMPH: 106.1,
            smashFactor: 1.45,
            estimatedCarryYards: 270,
            launchAngleVertical: 14.2,
            launchAngleHorizontal: -0.3,
            spinRPM: 2512,
            clubPathDegrees: -1.5,
            spinAxisDegrees: 0.4
        )
    }
}
