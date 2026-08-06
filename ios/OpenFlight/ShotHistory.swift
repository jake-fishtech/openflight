import Foundation

/// In-memory shot history shared by every transport.
///
/// Shots are newest-first so the collection can be rendered directly by the
/// dashboard. The decoder normally removes duplicate events, but the history
/// also guards against them so alternate transports cannot add replays later.
struct ShotHistory: Equatable {
    static let defaultMaximumCount = 100

    let maximumCount: Int
    private(set) var shots: [ShotEvent] = []

    var latestShot: ShotEvent? { shots.first }

    init(maximumCount: Int = defaultMaximumCount) {
        precondition(maximumCount > 0, "Shot history must retain at least one shot")
        self.maximumCount = maximumCount
    }

    mutating func record(_ shot: ShotEvent) {
        guard !shots.contains(where: { $0.eventID == shot.eventID }) else { return }

        shots.insert(shot, at: 0)
        if shots.count > maximumCount {
            shots.removeLast(shots.count - maximumCount)
        }
    }
}
