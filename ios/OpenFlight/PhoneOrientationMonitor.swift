import CoreMotion
import Foundation
import UIKit

@MainActor
final class PhoneOrientationMonitor: ObservableObject {
    @Published private(set) var measurement: PhoneOrientationMeasurement?
    @Published private(set) var displayAngles: PhoneOrientationDisplayAngles?
    @Published private(set) var sampleCount = 0
    @Published private(set) var errorMessage: String?

    private let motionManager: CMMotionManager
    private var samples: [GravitySample] = []

    init(motionManager: CMMotionManager = CMMotionManager()) {
        self.motionManager = motionManager
    }

    var progress: Double {
        min(1, Double(sampleCount) / Double(PhoneOrientationCalculator.minimumSampleCount))
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            errorMessage = "Motion sensing is unavailable on this device. Use a physical iPhone."
            return
        }
        samples.removeAll(keepingCapacity: true)
        measurement = nil
        displayAngles = nil
        sampleCount = 0
        errorMessage = nil
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) {
            [weak self] motion, error in
            guard let self else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                return
            }
            guard let gravity = motion?.gravity else { return }
            self.add(GravitySample(x: gravity.x, y: gravity.y, z: gravity.z))
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func add(_ sample: GravitySample) {
        samples.append(sample)
        if samples.count > PhoneOrientationCalculator.minimumSampleCount {
            samples.removeFirst(samples.count - PhoneOrientationCalculator.minimumSampleCount)
        }
        sampleCount = samples.count
        let updatedMeasurement = PhoneOrientationCalculator.measurement(
            samples: samples,
            deviceModel: UIDevice.current.model
        )
        measurement = updatedMeasurement
        displayAngles = PhoneOrientationCalculator.displayAngles(
            latestSample: sample,
            measurement: updatedMeasurement
        )
    }
}
