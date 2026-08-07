import Foundation
import XCTest
@testable import OpenFlight

final class PhoneOrientationTests: XCTestCase {
    func testDisplayUsesLatestSensorAnglesWhileWindowIsUnstable() throws {
        let samples = (0..<120).map { index in
            let tilt = (index.isMultiple(of: 2) ? 10.0 : 12.0) * Double.pi / 180
            return GravitySample(x: 0, y: -cos(tilt), z: -sin(tilt))
        }
        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(samples: samples)
        )
        let liveTilt = 24.0 * Double.pi / 180
        let latest = GravitySample(x: 0, y: -cos(liveTilt), z: -sin(liveTilt))

        let display = try XCTUnwrap(
            PhoneOrientationCalculator.displayAngles(
                latestSample: latest,
                measurement: measurement
            )
        )

        XCTAssertFalse(measurement.isReadyToSend)
        XCTAssertEqual(display.mountTiltDegrees, 24, accuracy: 0.0001)
        XCTAssertFalse(display.isStableAverage)
    }

    func testDisplayUsesCalibrationAverageAfterItSettles() throws {
        let tilt = 12.25 * Double.pi / 180
        let sample = GravitySample(x: 0, y: -cos(tilt), z: -sin(tilt))
        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(
                samples: Array(repeating: sample, count: 120)
            )
        )

        let display = try XCTUnwrap(
            PhoneOrientationCalculator.displayAngles(
                latestSample: sample,
                measurement: measurement
            )
        )

        XCTAssertTrue(measurement.isReadyToSend)
        XCTAssertEqual(display.mountTiltDegrees, measurement.mountTiltDegrees, accuracy: 0.0001)
        XCTAssertEqual(display.rollDegrees, measurement.rollDegrees, accuracy: 0.0001)
        XCTAssertTrue(display.isStableAverage)
    }

    func testDisplayImmediatelyReturnsToLiveWhenPhoneMovesAfterSettling() throws {
        let settledTilt = 12.25 * Double.pi / 180
        let settled = GravitySample(
            x: 0,
            y: -cos(settledTilt),
            z: -sin(settledTilt)
        )
        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(
                samples: Array(repeating: settled, count: 120)
            )
        )
        let movedTilt = 20.0 * Double.pi / 180
        let moved = GravitySample(x: 0, y: -cos(movedTilt), z: -sin(movedTilt))

        let display = try XCTUnwrap(
            PhoneOrientationCalculator.displayAngles(
                latestSample: moved,
                measurement: measurement
            )
        )

        XCTAssertTrue(measurement.isReadyToSend)
        XCTAssertEqual(display.mountTiltDegrees, 20, accuracy: 0.0001)
        XCTAssertFalse(display.isStableAverage)
    }

    func testPortraitPhoneAgainstVerticalFaceReadsZeroTiltAndRoll() throws {
        let samples = Array(
            repeating: GravitySample(x: 0, y: -1, z: 0),
            count: PhoneOrientationCalculator.minimumSampleCount
        )

        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(
                samples: samples,
                measuredAt: Date(timeIntervalSince1970: 0),
                deviceModel: "iPhone"
            )
        )

        XCTAssertEqual(measurement.mountTiltDegrees, 0, accuracy: 0.0001)
        XCTAssertEqual(measurement.rollDegrees, 0, accuracy: 0.0001)
        XCTAssertTrue(measurement.isReadyToSend)
    }

    func testGravityVectorProducesRadarTiltAndRoll() throws {
        let tilt = 12.25 * Double.pi / 180
        let roll = -1.5 * Double.pi / 180
        let horizontal = cos(tilt)
        let sample = GravitySample(
            x: sin(roll) * horizontal,
            y: -cos(roll) * horizontal,
            z: -sin(tilt)
        )

        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(
                samples: Array(repeating: sample, count: 120),
                measuredAt: Date(timeIntervalSince1970: 0),
                deviceModel: "iPhone"
            )
        )

        XCTAssertEqual(measurement.mountTiltDegrees, 12.25, accuracy: 0.0001)
        XCTAssertEqual(measurement.rollDegrees, -1.5, accuracy: 0.0001)
        XCTAssertEqual(measurement.gravityXG, sample.x, accuracy: 0.000001)
        XCTAssertTrue(measurement.isReadyToSend)
    }

    func testMovingPhoneIsNotReadyToSend() throws {
        let samples = (0..<120).map { index in
            let tilt = (index.isMultiple(of: 2) ? 10.0 : 12.0) * Double.pi / 180
            return GravitySample(x: 0, y: -cos(tilt), z: -sin(tilt))
        }

        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(samples: samples)
        )

        XCTAssertGreaterThan(measurement.tiltStandardDeviationDegrees, 0.5)
        XCTAssertFalse(measurement.isReadyToSend)
    }

    func testBadlyRolledRadarIsNotReadyToSend() throws {
        let roll = 4.0 * Double.pi / 180
        let sample = GravitySample(x: sin(roll), y: -cos(roll), z: 0)

        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(
                samples: Array(repeating: sample, count: 120)
            )
        )

        XCTAssertEqual(measurement.rollDegrees, 4.0, accuracy: 0.0001)
        XCTAssertFalse(measurement.isReadyToSend)
    }

    func testCalibrationRequestUsesWiFiHostAndSnakeCasePayload() throws {
        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(
                samples: Array(
                    repeating: GravitySample(x: 0, y: -1, z: 0),
                    count: 120
                ),
                measuredAt: Date(timeIntervalSince1970: 0),
                deviceModel: "iPhone"
            )
        )

        let request = try RadarCalibrationClient.request(
            host: "raspberrypi.local",
            measurement: measurement
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "http://raspberrypi.local:8080/api/calibration/iwr6843/orientation"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["mount_tilt_deg"] as? Double, 0)
        XCTAssertEqual(object["sample_count"] as? Int, 120)
        XCTAssertEqual(object["device_model"] as? String, "iPhone")
    }

    func testCalibrationURLRejectsUnsupportedHost() {
        XCTAssertNil(RadarCalibrationClient.calibrationURL(host: "ftp://pi.local"))
        XCTAssertNil(RadarCalibrationClient.calibrationURL(host: " "))
    }

    func testBluetoothCalibrationCommandWrapsSharedMeasurementPayload() throws {
        let measurement = try XCTUnwrap(
            PhoneOrientationCalculator.measurement(
                samples: Array(
                    repeating: GravitySample(x: 0, y: -1, z: 0),
                    count: 120
                ),
                measuredAt: Date(timeIntervalSince1970: 0),
                deviceModel: "iPhone"
            )
        )

        let command = try BluetoothCalibrationCommand.encode(
            measurement: measurement,
            requestID: "request-1"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: command) as? [String: Any]
        )
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["type"] as? String, "iwr6843_orientation_calibration")
        XCTAssertEqual(object["request_id"] as? String, "request-1")
        XCTAssertEqual(payload["sample_count"] as? Int, 120)
        XCTAssertEqual(payload["mount_tilt_deg"] as? Double, 0)
    }

    func testBluetoothClubCommandUsesSharedControlEnvelope() throws {
        let command = try BluetoothClubCommand.encode(
            club: .iron7,
            requestID: "club-request-1"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: command) as? [String: Any]
        )
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["type"] as? String, "set_club")
        XCTAssertEqual(object["request_id"] as? String, "club-request-1")
        XCTAssertEqual(payload["club"] as? String, "7-iron")
    }

    func testWiFiClubRequestUsesClubEndpoint() throws {
        let request = try ClubSelectionClient.request(
            host: "raspberrypi.local",
            club: .pitchingWedge
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(request.url?.absoluteString, "http://raspberrypi.local:8080/api/club")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(object["club"] as? String, "pw")
    }
}
