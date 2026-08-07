import Foundation

enum GolfClub: String, CaseIterable, Identifiable, Codable {
    case driver
    case wood3 = "3-wood"
    case wood5 = "5-wood"
    case wood7 = "7-wood"
    case hybrid3 = "3-hybrid"
    case hybrid5 = "5-hybrid"
    case hybrid7 = "7-hybrid"
    case hybrid9 = "9-hybrid"
    case iron2 = "2-iron"
    case iron3 = "3-iron"
    case iron4 = "4-iron"
    case iron5 = "5-iron"
    case iron6 = "6-iron"
    case iron7 = "7-iron"
    case iron8 = "8-iron"
    case iron9 = "9-iron"
    case pitchingWedge = "pw"
    case gapWedge = "gw"
    case sandWedge = "sw"
    case lobWedge = "lw"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pitchingWedge: "Pitching Wedge"
        case .gapWedge: "Gap Wedge"
        case .sandWedge: "Sand Wedge"
        case .lobWedge: "Lob Wedge"
        default: rawValue.capitalized
        }
    }
}

private struct BluetoothControlEnvelope<Payload: Encodable>: Encodable {
    let schemaVersion = 1
    let type: String
    let requestID: String
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case type
        case requestID = "request_id"
        case payload
    }
}

enum BluetoothCalibrationCommand {
    static func encode(
        measurement: PhoneOrientationMeasurement,
        requestID: String
    ) throws -> Data {
        try JSONEncoder().encode(
            BluetoothControlEnvelope(
                type: "iwr6843_orientation_calibration",
                requestID: requestID,
                payload: measurement
            )
        )
    }
}

private struct ClubPayload: Codable {
    let club: GolfClub
}

enum BluetoothClubCommand {
    static func encode(club: GolfClub, requestID: String) throws -> Data {
        try JSONEncoder().encode(
            BluetoothControlEnvelope(
                type: "set_club",
                requestID: requestID,
                payload: ClubPayload(club: club)
            )
        )
    }
}

struct ClubSelectionResponse: Decodable, Equatable {
    let status: String
    let club: GolfClub
}

final class ClubSelectionClient {
    static let path = "/api/club"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func request(host: String, club: GolfClub) throws -> URLRequest {
        guard let url = WiFiShotClient.endpointURL(host: host, path: path) else {
            throw RadarCalibrationClientError.invalidHost(host)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(ClubPayload(club: club))
        return request
    }

    func submit(host: String, club: GolfClub) async throws -> ClubSelectionResponse {
        let request = try Self.request(host: host, club: club)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let message = (try? JSONDecoder().decode(PhoneControlServerError.self, from: data))?.error
            throw RadarCalibrationClientError.unexpectedStatus(statusCode, message)
        }
        return try JSONDecoder().decode(ClubSelectionResponse.self, from: data)
    }
}

struct PhoneControlServerError: Decodable {
    let error: String
}
