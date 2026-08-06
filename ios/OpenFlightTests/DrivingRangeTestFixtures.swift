import Foundation
@testable import OpenFlight

func makeDrivingRangeShot(
    eventID: UUID = UUID(),
    club: String = "driver",
    ballSpeedMPH: Double = 151.4,
    carryYards: Double = 264,
    launchAngle: Double? = 12.6,
    horizontalLaunch: Double? = -1.3,
    spinRPM: Double? = 2_380,
    spinAxis: Double? = -3.4
) -> ShotEvent {
    ShotEvent(
        schemaVersion: 1,
        eventID: eventID,
        timestamp: "2026-08-06T01:00:00",
        club: club,
        ballSpeedMPH: ballSpeedMPH,
        clubSpeedMPH: 103.2,
        smashFactor: 1.47,
        estimatedCarryYards: carryYards,
        launchAngleVertical: launchAngle,
        launchAngleHorizontal: horizontalLaunch,
        spinRPM: spinRPM,
        clubPathDegrees: 2.1,
        spinAxisDegrees: spinAxis
    )
}

func makeTestTrajectory(for input: FlightInput) -> FlightTrajectory {
    FlightTrajectory(
        id: input.eventID,
        eventID: input.eventID,
        points: [
            FlightPoint(
                time: 0,
                positionMeters: .zero,
                velocityMetersPerSecond: SIMD3(0, 10, 40)
            ),
            FlightPoint(
                time: 1,
                positionMeters: SIMD3(0, 0, input.targetCarryMeters),
                velocityMetersPerSecond: SIMD3(0, -10, 30)
            ),
        ],
        provenance: input.provenance
    )
}

