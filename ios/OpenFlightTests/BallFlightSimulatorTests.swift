import XCTest
@testable import OpenFlight

final class BallFlightSimulatorTests: XCTestCase {
    func testVacuumTrajectoryMatchesClosedFormBallistics() {
        let speed = 50.0
        let angle = 30.0
        let input = makeInput(speed: speed, launch: angle, spin: 0, carry: 200)
        let trajectory = BallFlightSimulator(configuration: .vacuum).simulate(input)
        let verticalSpeed = speed * sin(angle * .pi / 180)
        let horizontalSpeed = speed * cos(angle * .pi / 180)
        let expectedTime = 2 * verticalSpeed / 9.80665
        let expectedCarry = horizontalSpeed * expectedTime

        XCTAssertEqual(trajectory.flightTime, expectedTime, accuracy: 0.02)
        XCTAssertEqual(trajectory.carryMeters, expectedCarry, accuracy: 0.6)
        XCTAssertEqual(trajectory.points.last?.positionMeters.y ?? .nan, 0, accuracy: 0.000_1)
    }

    func testProductionTrajectoryLandsAtOpenFlightCarry() {
        let input = makeInput(speed: 67, launch: 13, spin: 2_500, carry: 245)
        let trajectory = BallFlightSimulator().simulate(input)

        XCTAssertEqual(trajectory.carryMeters, 245, accuracy: 0.01)
        XCTAssertGreaterThan(trajectory.apexMeters, 10)
        XCTAssertGreaterThan(trajectory.flightTime, 2)
        XCTAssertTrue(trajectory.points.allSatisfy { $0.positionMeters.y >= 0 })
    }

    func testDragReducesUnconstrainedCarry() {
        var aerodynamicConfiguration = BallFlightSimulator.Configuration.standard
        aerodynamicConfiguration.constrainToTargetCarry = false
        let input = makeInput(speed: 60, launch: 14, spin: 0, carry: 240)
        let aerodynamic = BallFlightSimulator(configuration: aerodynamicConfiguration).simulate(input)
        let vacuum = BallFlightSimulator(configuration: .vacuum).simulate(input)

        XCTAssertLessThan(aerodynamic.carryMeters, vacuum.carryMeters)
    }

    func testBackspinProducesMoreLiftThanNoSpin() {
        var configuration = BallFlightSimulator.Configuration.standard
        configuration.constrainToTargetCarry = false
        let simulator = BallFlightSimulator(configuration: configuration)
        let noSpin = simulator.simulate(makeInput(speed: 62, launch: 12, spin: 0, carry: 230))
        let backspin = simulator.simulate(makeInput(speed: 62, launch: 12, spin: 3_000, carry: 230))

        XCTAssertGreaterThan(backspin.apexMeters, noSpin.apexMeters)
        XCTAssertGreaterThan(backspin.flightTime, noSpin.flightTime)
    }

    func testSpinAxisControlsCurveDirection() {
        var configuration = BallFlightSimulator.Configuration.standard
        configuration.constrainToTargetCarry = false
        let simulator = BallFlightSimulator(configuration: configuration)
        let fade = simulator.simulate(makeInput(spinAxis: 18))
        let draw = simulator.simulate(makeInput(spinAxis: -18))

        XCTAssertGreaterThan(fade.lateralMeters, 0)
        XCTAssertLessThan(draw.lateralMeters, 0)
        XCTAssertEqual(abs(fade.lateralMeters), abs(draw.lateralMeters), accuracy: 0.2)
    }

    func testTrajectorySamplingInterpolatesBetweenFrames() {
        let trajectory = BallFlightSimulator(configuration: .vacuum).simulate(makeInput())
        let time = trajectory.flightTime * 0.5
        let point = trajectory.point(at: time)

        XCTAssertNotNil(point)
        XCTAssertEqual(point?.time ?? .nan, time, accuracy: 0.000_1)
        XCTAssertGreaterThan(point?.positionMeters.y ?? 0, 0)
    }

    func testIntegrationConvergesAcrossReasonableTimeSteps() {
        var coarseConfiguration = BallFlightSimulator.Configuration.standard
        coarseConfiguration.timeStep = 1.0 / 60.0
        coarseConfiguration.constrainToTargetCarry = false
        var fineConfiguration = coarseConfiguration
        fineConfiguration.timeStep = 1.0 / 240.0
        let input = makeInput()
        let coarse = BallFlightSimulator(configuration: coarseConfiguration).simulate(input)
        let fine = BallFlightSimulator(configuration: fineConfiguration).simulate(input)

        XCTAssertEqual(coarse.carryMeters, fine.carryMeters, accuracy: fine.carryMeters * 0.005)
        XCTAssertEqual(coarse.apexMeters, fine.apexMeters, accuracy: 0.15)
    }

    private func makeInput(
        speed: Double = 67,
        launch: Double = 13,
        horizontal: Double = 0,
        spin: Double = 2_500,
        spinAxis: Double = 0,
        carry: Double = 245
    ) -> FlightInput {
        FlightInput(
            eventID: UUID(),
            ballSpeedMetersPerSecond: speed,
            launchAngleDegrees: launch,
            horizontalLaunchDegrees: horizontal,
            spinRPM: spin,
            spinAxisDegrees: spinAxis,
            targetCarryMeters: carry,
            windMetersPerSecond: .zero,
            provenance: FlightInputProvenance(
                estimatedParameters: [],
                clampedParameters: []
            )
        )
    }
}
