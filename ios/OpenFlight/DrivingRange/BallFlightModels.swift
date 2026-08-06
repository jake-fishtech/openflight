import Foundation

enum FlightParameter: String, CaseIterable, Hashable, Sendable {
    case launchAngle
    case horizontalLaunch
    case spinRate
    case spinAxis
}

struct FlightInputProvenance: Equatable, Sendable {
    let estimatedParameters: Set<FlightParameter>
    let clampedParameters: Set<FlightParameter>

    var usesEstimatedFlight: Bool {
        estimatedParameters.contains(.launchAngle) || estimatedParameters.contains(.spinRate)
    }
}

struct FlightInput: Equatable, Sendable {
    let eventID: UUID
    let ballSpeedMetersPerSecond: Double
    let launchAngleDegrees: Double
    let horizontalLaunchDegrees: Double
    let spinRPM: Double
    let spinAxisDegrees: Double
    let targetCarryMeters: Double
    let windMetersPerSecond: SIMD3<Double>
    let provenance: FlightInputProvenance
}

struct FlightPoint: Equatable, Sendable {
    let time: TimeInterval
    let positionMeters: SIMD3<Double>
    let velocityMetersPerSecond: SIMD3<Double>
}

struct FlightTrajectory: Equatable, Identifiable, Sendable {
    let id: UUID
    let eventID: UUID
    let points: [FlightPoint]
    let apexMeters: Double
    let flightTime: TimeInterval
    let carryMeters: Double
    let lateralMeters: Double
    let provenance: FlightInputProvenance

    init(
        id: UUID = UUID(),
        eventID: UUID,
        points: [FlightPoint],
        provenance: FlightInputProvenance
    ) {
        self.id = id
        self.eventID = eventID
        self.points = points
        self.apexMeters = points.map(\.positionMeters.y).max() ?? 0
        self.flightTime = points.last?.time ?? 0
        self.carryMeters = points.last?.positionMeters.z ?? 0
        self.lateralMeters = points.last?.positionMeters.x ?? 0
        self.provenance = provenance
    }

    var playbackDuration: TimeInterval {
        min(max(flightTime * 0.68, 3.5), 6.0)
    }

    func point(at time: TimeInterval) -> FlightPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if time <= first.time { return first }
        if time >= last.time { return last }

        var lower = 0
        var upper = points.count - 1
        while upper - lower > 1 {
            let middle = (lower + upper) / 2
            if points[middle].time <= time {
                lower = middle
            } else {
                upper = middle
            }
        }

        let start = points[lower]
        let end = points[upper]
        let interval = end.time - start.time
        guard interval > 0 else { return start }
        let progress = (time - start.time) / interval
        return FlightPoint(
            time: time,
            positionMeters: start.positionMeters
                + (end.positionMeters - start.positionMeters) * progress,
            velocityMetersPerSecond: start.velocityMetersPerSecond
                + (end.velocityMetersPerSecond - start.velocityMetersPerSecond) * progress
        )
    }
}

