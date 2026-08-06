import Foundation

struct RangeCameraPose: Equatable, Sendable {
    let position: SIMD3<Float>
    let target: SIMD3<Float>
}

/// Produces a fixed tee-box camera aimed down the target line. The pose never
/// depends on the ball, so distance, height, and lateral curvature remain
/// visible relative to a stable range throughout the complete flight.
struct RangeCameraPlanner: Sendable {
    let pose = RangeCameraPose(
        position: SIMD3(0, 3.4, 8),
        target: SIMD3(0, 9, -145)
    )
}
