import Foundation
import simd

struct BallFlightSimulator: Sendable {
    struct Configuration: Equatable, Sendable {
        var timeStep: TimeInterval = 1.0 / 120.0
        var outputFramesPerSecond = 60.0
        var gravity = 9.80665
        var airDensity = 1.204
        var dragCoefficient = 0.24
        var liftSlope = 0.60
        var maximumLiftCoefficient = 0.34
        var constrainToTargetCarry = true

        static let standard = Configuration()

        static let vacuum = Configuration(
            airDensity: 0,
            dragCoefficient: 0,
            liftSlope: 0,
            maximumLiftCoefficient: 0,
            constrainToTargetCarry: false
        )
    }

    private struct State: Sendable {
        var position: SIMD3<Double>
        var velocity: SIMD3<Double>
    }

    private struct Derivative {
        let position: SIMD3<Double>
        let velocity: SIMD3<Double>
    }

    private let configuration: Configuration
    private let ballMassKilograms = 0.04593
    private let ballRadiusMeters = 0.02135
    private let maximumFlightTime: TimeInterval = 20

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    func simulate(_ input: FlightInput) -> FlightTrajectory {
        let vertical = input.launchAngleDegrees * .pi / 180
        let horizontal = input.horizontalLaunchDegrees * .pi / 180
        let horizontalSpeed = input.ballSpeedMetersPerSecond * cos(vertical)
        var state = State(
            position: .zero,
            velocity: SIMD3(
                horizontalSpeed * sin(horizontal),
                input.ballSpeedMetersPerSecond * sin(vertical),
                horizontalSpeed * cos(horizontal)
            )
        )

        var time: TimeInterval = 0
        var integrated = [
            FlightPoint(
                time: 0,
                positionMeters: state.position,
                velocityMetersPerSecond: state.velocity
            )
        ]

        while time < maximumFlightTime {
            let previous = state
            let previousTime = time
            state = rk4(state: state, input: input, step: configuration.timeStep)
            time += configuration.timeStep

            if state.position.y <= 0, time > configuration.timeStep * 2 {
                let denominator = previous.position.y - state.position.y
                let fraction = denominator > 0 ? previous.position.y / denominator : 1
                let landingTime = previousTime + configuration.timeStep * fraction
                let landingPosition = previous.position
                    + (state.position - previous.position) * fraction
                let landingVelocity = previous.velocity
                    + (state.velocity - previous.velocity) * fraction
                integrated.append(
                    FlightPoint(
                        time: landingTime,
                        positionMeters: SIMD3(landingPosition.x, 0, landingPosition.z),
                        velocityMetersPerSecond: landingVelocity
                    )
                )
                break
            }

            integrated.append(
                FlightPoint(
                    time: time,
                    positionMeters: state.position,
                    velocityMetersPerSecond: state.velocity
                )
            )
        }

        let constrained = constrain(points: integrated, targetCarry: input.targetCarryMeters)
        let compact = resample(points: constrained)
        return FlightTrajectory(
            eventID: input.eventID,
            points: compact,
            provenance: input.provenance
        )
    }

    private func acceleration(state: State, input: FlightInput) -> SIMD3<Double> {
        let relativeVelocity = state.velocity - input.windMetersPerSecond
        let speed = simd_length(relativeVelocity)
        guard speed > 0.01 else {
            return SIMD3(0, -configuration.gravity, 0)
        }

        let area = Double.pi * ballRadiusMeters * ballRadiusMeters
        let aerodynamicScale = 0.5 * configuration.airDensity * area / ballMassKilograms
        let drag = -aerodynamicScale * configuration.dragCoefficient * speed * relativeVelocity

        let spinRadiansPerSecond = input.spinRPM * 2 * .pi / 60
        let spinAxis = input.spinAxisDegrees * .pi / 180
        let angularVelocity = SIMD3(
            -cos(spinAxis) * spinRadiansPerSecond,
            sin(spinAxis) * spinRadiansPerSecond,
            0
        )
        let spinParameter = spinRadiansPerSecond * ballRadiusMeters / speed
        let liftCoefficient = min(
            configuration.maximumLiftCoefficient,
            max(0, configuration.liftSlope * spinParameter)
        )
        let liftDirectionVector = simd_cross(angularVelocity, relativeVelocity)
        let liftDirectionLength = simd_length(liftDirectionVector)
        let lift = liftDirectionLength > 0.0001
            ? aerodynamicScale * liftCoefficient * speed * speed
                * (liftDirectionVector / liftDirectionLength)
            : .zero

        return drag + lift + SIMD3(0, -configuration.gravity, 0)
    }

    private func rk4(state: State, input: FlightInput, step: TimeInterval) -> State {
        let first = derivative(state: state, input: input)
        let second = derivative(state: offset(state, by: first, scale: step / 2), input: input)
        let third = derivative(state: offset(state, by: second, scale: step / 2), input: input)
        let fourth = derivative(state: offset(state, by: third, scale: step), input: input)

        return State(
            position: state.position + step / 6
                * (first.position + 2 * second.position + 2 * third.position + fourth.position),
            velocity: state.velocity + step / 6
                * (first.velocity + 2 * second.velocity + 2 * third.velocity + fourth.velocity)
        )
    }

    private func derivative(state: State, input: FlightInput) -> Derivative {
        Derivative(position: state.velocity, velocity: acceleration(state: state, input: input))
    }

    private func offset(_ state: State, by derivative: Derivative, scale: Double) -> State {
        State(
            position: state.position + derivative.position * scale,
            velocity: state.velocity + derivative.velocity * scale
        )
    }

    private func constrain(points: [FlightPoint], targetCarry: Double) -> [FlightPoint] {
        guard configuration.constrainToTargetCarry,
              let rawCarry = points.last?.positionMeters.z,
              rawCarry > 0.5,
              targetCarry > 0
        else {
            return points
        }
        let scale = targetCarry / rawCarry
        return points.map { point in
            FlightPoint(
                time: point.time,
                positionMeters: SIMD3(
                    point.positionMeters.x * scale,
                    point.positionMeters.y,
                    point.positionMeters.z * scale
                ),
                velocityMetersPerSecond: SIMD3(
                    point.velocityMetersPerSecond.x * scale,
                    point.velocityMetersPerSecond.y,
                    point.velocityMetersPerSecond.z * scale
                )
            )
        }
    }

    private func resample(points: [FlightPoint]) -> [FlightPoint] {
        guard let last = points.last, points.count > 1, configuration.outputFramesPerSecond > 0 else {
            return points
        }
        let interval = 1 / configuration.outputFramesPerSecond
        var result: [FlightPoint] = []
        var sourceIndex = 0
        var time: TimeInterval = 0

        while time < last.time {
            while sourceIndex + 1 < points.count, points[sourceIndex + 1].time < time {
                sourceIndex += 1
            }
            let start = points[sourceIndex]
            let end = points[min(sourceIndex + 1, points.count - 1)]
            let span = end.time - start.time
            let progress = span > 0 ? (time - start.time) / span : 0
            result.append(
                FlightPoint(
                    time: time,
                    positionMeters: start.positionMeters
                        + (end.positionMeters - start.positionMeters) * progress,
                    velocityMetersPerSecond: start.velocityMetersPerSecond
                        + (end.velocityMetersPerSecond - start.velocityMetersPerSecond) * progress
                )
            )
            time += interval
        }
        result.append(last)
        return result
    }
}

