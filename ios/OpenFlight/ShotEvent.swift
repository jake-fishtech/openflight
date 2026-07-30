import Foundation

struct ShotEvent: Codable, Equatable, Identifiable {
    let schemaVersion: Int
    let eventID: UUID
    let timestamp: String
    let club: String
    let ballSpeedMPH: Double
    let clubSpeedMPH: Double?
    let smashFactor: Double?
    let estimatedCarryYards: Double
    let launchAngleVertical: Double?
    let launchAngleHorizontal: Double?
    let spinRPM: Double?
    let clubPathDegrees: Double?
    let spinAxisDegrees: Double?

    var id: UUID { eventID }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case timestamp
        case club
        case ballSpeedMPH = "ball_speed_mph"
        case clubSpeedMPH = "club_speed_mph"
        case smashFactor = "smash_factor"
        case estimatedCarryYards = "estimated_carry_yards"
        case launchAngleVertical = "launch_angle_vertical"
        case launchAngleHorizontal = "launch_angle_horizontal"
        case spinRPM = "spin_rpm"
        case clubPathDegrees = "club_path_deg"
        case spinAxisDegrees = "spin_axis_deg"
    }

    var displayClub: String {
        club
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

extension ShotEvent {
    static let preview = ShotEvent(
        schemaVersion: 1,
        eventID: UUID(),
        timestamp: "2026-07-29T19:42:10",
        club: "driver",
        ballSpeedMPH: 151.4,
        clubSpeedMPH: 103.2,
        smashFactor: 1.47,
        estimatedCarryYards: 264,
        launchAngleVertical: 12.6,
        launchAngleHorizontal: -1.3,
        spinRPM: 2380,
        clubPathDegrees: 2.1,
        spinAxisDegrees: -3.4
    )
}
