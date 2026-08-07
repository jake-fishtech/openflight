import Foundation

enum RadarCalibrationClientError: LocalizedError, Equatable {
    case invalidHost(String)
    case unexpectedStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case let .invalidHost(host):
            host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter the Wi-Fi address of your OpenFlight Pi."
                : "\"\(host)\" is not a valid OpenFlight address."
        case let .unexpectedStatus(code, message):
            message ?? "OpenFlight returned HTTP \(code)."
        }
    }
}

struct RadarCalibrationResponse: Decodable, Equatable {
    let status: String
    let persistent: Bool
    let measuredMountTiltDegrees: Double
    let enclosurePitchDegrees: Double?
    let configuredIWRTiltDegrees: Double
    let rollDegrees: Double
    let azimuthOffsetDegrees: Double

    enum CodingKeys: String, CodingKey {
        case status
        case persistent
        case measuredMountTiltDegrees = "measured_mount_tilt_deg"
        case enclosurePitchDegrees = "enclosure_pitch_deg"
        case configuredIWRTiltDegrees = "configured_iwr_tilt_deg"
        case rollDegrees = "roll_deg"
        case azimuthOffsetDegrees = "azimuth_offset_deg"
    }
}

final class RadarCalibrationClient {
    static let calibrationPath = "/api/calibration/iwr6843/orientation"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func calibrationURL(host: String) -> URL? {
        WiFiShotClient.endpointURL(host: host, path: calibrationPath)
    }

    static func request(
        host: String,
        measurement: PhoneOrientationMeasurement
    ) throws -> URLRequest {
        guard let url = calibrationURL(host: host) else {
            throw RadarCalibrationClientError.invalidHost(host)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(measurement)
        return request
    }

    func submit(
        host: String,
        measurement: PhoneOrientationMeasurement
    ) async throws -> RadarCalibrationResponse {
        let request = try Self.request(host: host, measurement: measurement)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let message = (try? JSONDecoder().decode(PhoneControlServerError.self, from: data))?.error
            throw RadarCalibrationClientError.unexpectedStatus(statusCode, message)
        }
        return try JSONDecoder().decode(RadarCalibrationResponse.self, from: data)
    }
}
