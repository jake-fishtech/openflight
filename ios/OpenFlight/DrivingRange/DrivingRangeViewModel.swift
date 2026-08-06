import Foundation

@MainActor
final class DrivingRangeViewModel: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case preparing
        case flying
        case landed
        case unavailable(String)

        var label: String {
            switch self {
            case .waiting:
                "Ready for the next shot"
            case .preparing:
                "Calculating flight"
            case .flying:
                "Ball in flight"
            case .landed:
                "Shot complete"
            case let .unavailable(message):
                message
            }
        }
    }

    typealias Simulation = @Sendable (FlightInput) -> FlightTrajectory
    typealias Sleep = @Sendable (Duration) async throws -> Void

    @Published private(set) var phase: Phase = .waiting
    @Published private(set) var displayedShot: ShotEvent?
    @Published private(set) var activeTrajectory: FlightTrajectory?

    private let resolver: FlightInputResolver
    private let simulation: Simulation
    private let sleep: Sleep
    private var lastObservedEventID: UUID?
    private var pendingShot: ShotEvent?
    private var preparationTask: Task<Void, Never>?
    private var landingTask: Task<Void, Never>?
    private var generation = UUID()

    init(
        currentShot: ShotEvent?,
        resolver: FlightInputResolver = FlightInputResolver(),
        simulator: BallFlightSimulator = BallFlightSimulator(),
        simulation: Simulation? = nil,
        sleep: @escaping Sleep = { duration in try await Task.sleep(for: duration) }
    ) {
        displayedShot = currentShot
        lastObservedEventID = currentShot?.eventID
        self.resolver = resolver
        self.simulation = simulation ?? { input in simulator.simulate(input) }
        self.sleep = sleep
    }

    func observe(_ shot: ShotEvent?) {
        guard let shot, shot.eventID != lastObservedEventID else { return }
        lastObservedEventID = shot.eventID

        switch phase {
        case .preparing, .flying, .landed:
            pendingShot = shot
        case .waiting, .unavailable:
            prepare(shot)
        }
    }

    func replayDisplayedShot() {
        guard let displayedShot, phase != .preparing, phase != .flying else { return }
        pendingShot = nil
        prepare(displayedShot)
    }

    func animationCompleted() {
        guard phase == .flying else { return }
        phase = .landed
        landingTask?.cancel()
        landingTask = Task { [weak self, sleep] in
            do {
                try await sleep(.milliseconds(1_250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.advanceAfterLanding()
        }
    }

    func suspend() {
        generation = UUID()
        preparationTask?.cancel()
        landingTask?.cancel()
        preparationTask = nil
        landingTask = nil
        pendingShot = nil
        activeTrajectory = nil
        phase = .waiting
    }

    private func prepare(_ shot: ShotEvent) {
        preparationTask?.cancel()
        landingTask?.cancel()
        landingTask = nil
        activeTrajectory = nil
        displayedShot = shot

        let input: FlightInput
        do {
            input = try resolver.resolve(shot)
        } catch {
            phase = .unavailable(error.localizedDescription)
            return
        }

        phase = .preparing
        let currentGeneration = UUID()
        generation = currentGeneration
        let simulation = simulation
        preparationTask = Task { [weak self] in
            let trajectory = await Task.detached(priority: .userInitiated) {
                simulation(input)
            }.value
            guard !Task.isCancelled, self?.generation == currentGeneration else { return }
            self?.activeTrajectory = trajectory
            self?.phase = .flying
            self?.preparationTask = nil
        }
    }

    private func advanceAfterLanding() {
        landingTask = nil
        activeTrajectory = nil
        if let pendingShot {
            self.pendingShot = nil
            prepare(pendingShot)
        } else {
            phase = .waiting
        }
    }
}

