import RealityKit
import SwiftUI

struct RangeSceneView: UIViewRepresentable {
    let trajectory: FlightTrajectory?
    let reduceMotion: Bool
    let onFlightCompleted: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        context.coordinator.controller = RangeSceneController(view: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.onFlightCompleted = onFlightCompleted
        guard let trajectory else {
            context.coordinator.controller?.suspend()
            return
        }
        context.coordinator.controller?.play(
            trajectory,
            reduceMotion: reduceMotion,
            completion: { [weak coordinator = context.coordinator] in
                coordinator?.onFlightCompleted?()
            }
        )
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.controller?.tearDown()
        coordinator.controller = nil
    }

    @MainActor
    final class Coordinator {
        var controller: RangeSceneController?
        var onFlightCompleted: (@MainActor () -> Void)?
    }
}

