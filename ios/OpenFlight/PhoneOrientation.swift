import Foundation

struct GravitySample: Equatable {
    let x: Double
    let y: Double
    let z: Double
}

struct PhoneOrientationDisplayAngles: Equatable {
    let mountTiltDegrees: Double
    let rollDegrees: Double
    let isStableAverage: Bool
}

struct PhoneOrientationMeasurement: Encodable, Equatable {
    let schemaVersion = 1
    let mountTiltDegrees: Double
    let rollDegrees: Double
    let gravityXG: Double
    let gravityYG: Double
    let gravityZG: Double
    let tiltStandardDeviationDegrees: Double
    let rollStandardDeviationDegrees: Double
    let sampleCount: Int
    let measuredAt: String
    let deviceModel: String

    var isReadyToSend: Bool {
        sampleCount >= PhoneOrientationCalculator.minimumSampleCount
            && tiltStandardDeviationDegrees <= PhoneOrientationCalculator.maximumStandardDeviation
            && rollStandardDeviationDegrees <= PhoneOrientationCalculator.maximumStandardDeviation
            && abs(rollDegrees) <= PhoneOrientationCalculator.maximumRollDegrees
            && (-30...45).contains(mountTiltDegrees)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case mountTiltDegrees = "mount_tilt_deg"
        case rollDegrees = "roll_deg"
        case gravityXG = "gravity_x_g"
        case gravityYG = "gravity_y_g"
        case gravityZG = "gravity_z_g"
        case tiltStandardDeviationDegrees = "tilt_stddev_deg"
        case rollStandardDeviationDegrees = "roll_stddev_deg"
        case sampleCount = "sample_count"
        case measuredAt = "measured_at"
        case deviceModel = "device_model"
    }
}

enum PhoneOrientationCalculator {
    /// Two seconds at 60 Hz gives a steady average without making setup feel slow.
    static let minimumSampleCount = 120
    static let maximumStandardDeviation = 0.5
    static let maximumRollDegrees = 3.0
    static let maximumSettledDisplayDeviationDegrees = 0.5

    static func measurement(
        samples: [GravitySample],
        measuredAt: Date = Date(),
        deviceModel: String = "iPhone"
    ) -> PhoneOrientationMeasurement? {
        let valid = samples.filter { sample in
            let magnitude = sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z)
            return magnitude >= 0.8 && magnitude <= 1.2
        }
        guard valid.count >= minimumSampleCount else { return nil }

        let orientations = valid.compactMap(sensorAngles)
        guard orientations.count == valid.count else { return nil }

        let x = valid.map(\.x).reduce(0, +) / Double(valid.count)
        let y = valid.map(\.y).reduce(0, +) / Double(valid.count)
        let z = valid.map(\.z).reduce(0, +) / Double(valid.count)
        guard let meanOrientation = sensorAngles(GravitySample(x: x, y: y, z: z)) else {
            return nil
        }

        return PhoneOrientationMeasurement(
            mountTiltDegrees: meanOrientation.mountTiltDegrees,
            rollDegrees: meanOrientation.rollDegrees,
            gravityXG: x,
            gravityYG: y,
            gravityZG: z,
            tiltStandardDeviationDegrees: standardDeviation(orientations.map(\.mountTiltDegrees)),
            rollStandardDeviationDegrees: standardDeviation(orientations.map(\.rollDegrees)),
            sampleCount: valid.count,
            measuredAt: ISO8601DateFormatter().string(from: measuredAt),
            deviceModel: deviceModel
        )
    }

    static func displayAngles(
        latestSample: GravitySample,
        measurement: PhoneOrientationMeasurement?
    ) -> PhoneOrientationDisplayAngles? {
        guard let latestAngles = sensorAngles(latestSample) else { return nil }
        if let measurement,
           measurement.isReadyToSend,
           abs(latestAngles.mountTiltDegrees - measurement.mountTiltDegrees)
               <= maximumSettledDisplayDeviationDegrees,
           abs(latestAngles.rollDegrees - measurement.rollDegrees)
               <= maximumSettledDisplayDeviationDegrees
        {
            return PhoneOrientationDisplayAngles(
                mountTiltDegrees: measurement.mountTiltDegrees,
                rollDegrees: measurement.rollDegrees,
                isStableAverage: true
            )
        }
        return latestAngles
    }

    private static func sensorAngles(
        _ sample: GravitySample
    ) -> PhoneOrientationDisplayAngles? {
        let magnitude = sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z)
        guard magnitude > 0 else { return nil }
        let normalizedZ = max(-1.0, min(1.0, -sample.z / magnitude))
        return PhoneOrientationDisplayAngles(
            mountTiltDegrees: asin(normalizedZ) * 180 / .pi,
            rollDegrees: atan2(sample.x, -sample.y) * 180 / .pi,
            isStableAverage: false
        )
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
