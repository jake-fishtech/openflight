import Foundation

struct RangeMarkerDescription: Equatable, Sendable {
    let yards: Int
    let radiusMeters: Float
}

struct RangeTreeDescription: Equatable, Sendable {
    let xMeters: Float
    let downrangeMeters: Float
    let scale: Float
}

struct RangeSceneDescription: Equatable, Sendable {
    let markers: [RangeMarkerDescription]
    let trees: [RangeTreeDescription]
    let rangeDepthMeters: Float
    let fairwayWidthMeters: Float

    static func standard(treeCount: Int) -> RangeSceneDescription {
        let markers = stride(from: 50, through: 350, by: 50).map { yards in
            RangeMarkerDescription(
                yards: yards,
                radiusMeters: yards.isMultiple(of: 100) ? 7.5 : 5.5
            )
        }
        let count = max(0, treeCount)
        let trees = (0 ..< count).map { index in
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let lane = Float(index / 2)
            return RangeTreeDescription(
                xMeters: side * (32 + Float(index % 3) * 5),
                downrangeMeters: 22 + lane * 18,
                scale: 0.82 + Float(index % 4) * 0.09
            )
        }
        return RangeSceneDescription(
            markers: markers,
            trees: trees,
            rangeDepthMeters: 390,
            fairwayWidthMeters: 52
        )
    }
}

struct RangeTracerStyle: Equatable, Sendable {
    let nearWidthMeters: Float
    let farWidthMeters: Float
    let opacity: Float

    static let highVisibility = RangeTracerStyle(
        nearWidthMeters: 0.040,
        farWidthMeters: 0.26,
        opacity: 0.84
    )
}

enum RangeQualityProfile: Equatable, Sendable {
    case balanced
    case high

    static var current: RangeQualityProfile {
        ProcessInfo.processInfo.physicalMemory < 4_500_000_000 ? .balanced : .high
    }

    var treeCount: Int {
        switch self {
        case .balanced: 20
        case .high: 36
        }
    }

    var tracerPointCount: Int {
        switch self {
        case .balanced: 72
        case .high: 120
        }
    }
}
