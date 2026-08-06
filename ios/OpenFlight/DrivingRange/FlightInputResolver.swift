import Foundation

enum FlightInputResolutionError: LocalizedError, Equatable {
    case invalidBallSpeed
    case invalidCarry

    var errorDescription: String? {
        switch self {
        case .invalidBallSpeed:
            "Ball speed is unavailable for this shot."
        case .invalidCarry:
            "Carry distance is unavailable for this shot."
        }
    }
}

struct FlightInputResolver: Sendable {
    private struct ClubDefaults {
        let launchDegrees: Double
        let spinRPM: Double
    }

    private let milesPerHourToMetersPerSecond = 0.44704
    private let yardsToMeters = 0.9144

    func resolve(_ shot: ShotEvent) throws -> FlightInput {
        guard shot.ballSpeedMPH.isFinite, shot.ballSpeedMPH > 0 else {
            throw FlightInputResolutionError.invalidBallSpeed
        }
        guard shot.estimatedCarryYards.isFinite, shot.estimatedCarryYards > 0 else {
            throw FlightInputResolutionError.invalidCarry
        }

        let defaults = defaults(for: shot.club)
        var estimated = Set<FlightParameter>()
        var clamped = Set<FlightParameter>()

        let launch = resolved(
            shot.launchAngleVertical,
            fallback: defaults.launchDegrees,
            range: 1 ... 55,
            parameter: .launchAngle,
            estimated: &estimated,
            clamped: &clamped
        )
        let horizontal = resolved(
            shot.launchAngleHorizontal,
            fallback: 0,
            range: -45 ... 45,
            parameter: .horizontalLaunch,
            estimated: &estimated,
            clamped: &clamped
        )
        let spin = resolved(
            shot.spinRPM,
            fallback: defaults.spinRPM,
            range: 0 ... 12_000,
            parameter: .spinRate,
            estimated: &estimated,
            clamped: &clamped
        )
        let spinAxis = resolved(
            shot.spinAxisDegrees,
            fallback: 0,
            range: -60 ... 60,
            parameter: .spinAxis,
            estimated: &estimated,
            clamped: &clamped
        )

        return FlightInput(
            eventID: shot.eventID,
            ballSpeedMetersPerSecond: shot.ballSpeedMPH * milesPerHourToMetersPerSecond,
            launchAngleDegrees: launch,
            horizontalLaunchDegrees: horizontal,
            spinRPM: spin,
            spinAxisDegrees: spinAxis,
            targetCarryMeters: shot.estimatedCarryYards * yardsToMeters,
            windMetersPerSecond: .zero,
            provenance: FlightInputProvenance(
                estimatedParameters: estimated,
                clampedParameters: clamped
            )
        )
    }

    private func resolved(
        _ value: Double?,
        fallback: Double,
        range: ClosedRange<Double>,
        parameter: FlightParameter,
        estimated: inout Set<FlightParameter>,
        clamped: inout Set<FlightParameter>
    ) -> Double {
        guard let value, value.isFinite else {
            estimated.insert(parameter)
            return fallback
        }
        let bounded = min(max(value, range.lowerBound), range.upperBound)
        if bounded != value {
            clamped.insert(parameter)
        }
        return bounded
    }

    private func defaults(for club: String) -> ClubDefaults {
        let normalized = club
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalized {
        case "driver":
            return ClubDefaults(launchDegrees: 12, spinRPM: 2_500)
        case "3-wood", "5-wood", "7-wood":
            return ClubDefaults(launchDegrees: 15, spinRPM: 3_500)
        case "3-hybrid", "5-hybrid", "7-hybrid", "9-hybrid":
            return ClubDefaults(launchDegrees: 18, spinRPM: 4_200)
        case "2-iron", "3-iron", "4-iron", "iron-2", "iron-3", "iron-4":
            return ClubDefaults(launchDegrees: 17, spinRPM: 4_500)
        case "5-iron", "6-iron", "7-iron", "iron-5", "iron-6", "iron-7":
            return ClubDefaults(launchDegrees: 21, spinRPM: 5_500)
        case "8-iron", "9-iron", "iron-8", "iron-9":
            return ClubDefaults(launchDegrees: 26, spinRPM: 7_000)
        case "pw", "gw", "sw", "lw", "pitching-wedge", "gap-wedge", "sand-wedge", "lob-wedge":
            return ClubDefaults(launchDegrees: 31, spinRPM: 8_500)
        default:
            return ClubDefaults(launchDegrees: 18, spinRPM: 4_500)
        }
    }
}

