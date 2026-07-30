import Foundation

enum ShotDecodeError: LocalizedError, Equatable {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "Shot schema version \(version) is not supported."
        }
    }
}

/// Turns a complete shot payload into a `ShotEvent`, rejecting unknown schema
/// versions and suppressing the replay every transport sends on connect.
///
/// Both transports share this so the BLE and Wi-Fi paths cannot drift apart in
/// how they validate or de-duplicate what the Pi sends.
struct ShotEventDecoder {
    private var lastEventID: UUID?

    /// Returns the shot when it is new, or `nil` when it repeats the last one.
    mutating func decode(_ payload: Data) throws -> ShotEvent? {
        let shot = try JSONDecoder().decode(ShotEvent.self, from: payload)
        guard shot.schemaVersion == 1 else {
            throw ShotDecodeError.unsupportedSchema(shot.schemaVersion)
        }
        guard shot.eventID != lastEventID else {
            return nil
        }
        lastEventID = shot.eventID
        return shot
    }

    mutating func reset() {
        lastEventID = nil
    }
}
