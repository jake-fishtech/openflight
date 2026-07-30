import XCTest
@testable import OpenFlight

final class ShotEventTests: XCTestCase {
    func testDecodesSharedV1Fixture() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "shot_v1", withExtension: "json")
        )
        let shot = try JSONDecoder().decode(ShotEvent.self, from: Data(contentsOf: fixtureURL))

        XCTAssertEqual(shot.schemaVersion, 1)
        XCTAssertEqual(shot.eventID.uuidString, "B0D91F0A-7950-4D7E-9DD5-AF9777C190E1")
        XCTAssertEqual(shot.ballSpeedMPH, 151.4)
        XCTAssertEqual(shot.estimatedCarryYards, 264)
        XCTAssertEqual(shot.spinRPM, 2380)
        XCTAssertEqual(shot.displayClub, "Driver")
    }

    func testDecodesExplicitNullMeasurements() throws {
        let data = Data(
            """
            {
              "schema_version": 1,
              "event_id": "B0D91F0A-7950-4D7E-9DD5-AF9777C190E1",
              "timestamp": "2026-07-29T19:42:10",
              "club": "iron_7",
              "ball_speed_mph": 100.0,
              "club_speed_mph": null,
              "smash_factor": null,
              "estimated_carry_yards": 142,
              "launch_angle_vertical": null,
              "launch_angle_horizontal": null,
              "spin_rpm": null,
              "club_path_deg": null,
              "spin_axis_deg": null
            }
            """.utf8
        )

        let shot = try JSONDecoder().decode(ShotEvent.self, from: data)

        XCTAssertNil(shot.clubSpeedMPH)
        XCTAssertNil(shot.spinRPM)
        XCTAssertEqual(shot.displayClub, "Iron 7")
    }
}
