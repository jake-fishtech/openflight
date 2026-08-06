import XCTest
@testable import OpenFlight

final class FlightInputResolverTests: XCTestCase {
    private let resolver = FlightInputResolver()

    func testMeasuredValuesArePreserved() throws {
        let input = try resolver.resolve(makeDrivingRangeShot())

        XCTAssertEqual(input.launchAngleDegrees, 12.6)
        XCTAssertEqual(input.horizontalLaunchDegrees, -1.3)
        XCTAssertEqual(input.spinRPM, 2_380)
        XCTAssertEqual(input.spinAxisDegrees, -3.4)
        XCTAssertTrue(input.provenance.estimatedParameters.isEmpty)
        XCTAssertTrue(input.provenance.clampedParameters.isEmpty)
    }

    func testMissingDriverMeasurementsUseExplicitDefaults() throws {
        let input = try resolver.resolve(
            makeDrivingRangeShot(
                launchAngle: nil,
                horizontalLaunch: nil,
                spinRPM: nil,
                spinAxis: nil
            )
        )

        XCTAssertEqual(input.launchAngleDegrees, 12)
        XCTAssertEqual(input.horizontalLaunchDegrees, 0)
        XCTAssertEqual(input.spinRPM, 2_500)
        XCTAssertEqual(input.spinAxisDegrees, 0)
        XCTAssertEqual(input.provenance.estimatedParameters, Set(FlightParameter.allCases))
        XCTAssertTrue(input.provenance.usesEstimatedFlight)
    }

    func testClubDefaultTableCoversEveryClubFamily() throws {
        let cases: [(String, Double, Double)] = [
            ("3-wood", 15, 3_500),
            ("5_hybrid", 18, 4_200),
            ("iron_3", 17, 4_500),
            ("7-iron", 21, 5_500),
            ("iron_9", 26, 7_000),
            ("sw", 31, 8_500),
            ("unknown", 18, 4_500),
        ]

        for (club, expectedLaunch, expectedSpin) in cases {
            let input = try resolver.resolve(
                makeDrivingRangeShot(club: club, launchAngle: nil, spinRPM: nil)
            )
            XCTAssertEqual(input.launchAngleDegrees, expectedLaunch, club)
            XCTAssertEqual(input.spinRPM, expectedSpin, club)
        }
    }

    func testExtremeMeasurementsAreClampedAndRecorded() throws {
        let input = try resolver.resolve(
            makeDrivingRangeShot(
                launchAngle: 90,
                horizontalLaunch: -80,
                spinRPM: 18_000,
                spinAxis: 92
            )
        )

        XCTAssertEqual(input.launchAngleDegrees, 55)
        XCTAssertEqual(input.horizontalLaunchDegrees, -45)
        XCTAssertEqual(input.spinRPM, 12_000)
        XCTAssertEqual(input.spinAxisDegrees, 60)
        XCTAssertEqual(input.provenance.clampedParameters, Set(FlightParameter.allCases))
    }

    func testNonFiniteOptionalMeasurementUsesFallback() throws {
        let input = try resolver.resolve(
            makeDrivingRangeShot(launchAngle: .nan, spinRPM: .infinity)
        )

        XCTAssertEqual(input.launchAngleDegrees, 12)
        XCTAssertEqual(input.spinRPM, 2_500)
        XCTAssertEqual(input.provenance.estimatedParameters, [.launchAngle, .spinRate])
    }

    func testRejectsInvalidBallSpeedAndCarry() {
        XCTAssertThrowsError(try resolver.resolve(makeDrivingRangeShot(ballSpeedMPH: 0))) {
            XCTAssertEqual($0 as? FlightInputResolutionError, .invalidBallSpeed)
        }
        XCTAssertThrowsError(try resolver.resolve(makeDrivingRangeShot(carryYards: -.infinity))) {
            XCTAssertEqual($0 as? FlightInputResolutionError, .invalidCarry)
        }
    }
}

