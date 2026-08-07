import SwiftUI

struct RadarCalibrationView: View {
    @Binding var host: String
    let transport: ShotTransport
    @ObservedObject var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var monitor = PhoneOrientationMonitor()
    @State private var isSending = false
    @State private var response: RadarCalibrationResponse?
    @State private var submissionError: String?

    private let client = RadarCalibrationClient()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                instructions
                transportCard
                measurementCard
                submissionCard
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.11, blue: 0.17), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Calibrate TI Radar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Measure the radar face", systemImage: "iphone.gen3.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Remove the case. Hold the phone upright in portrait with its back flat against a straight reference surface parallel to the TI antenna face. Keep the screen facing the target.")
            Text("Avoid the camera bump and keep both the radar and phone still while the two-second sample fills.")
                .foregroundStyle(.secondary)
            Text("This calibrates gravity-referenced mount tilt. It does not change target-line azimuth.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var transportCard: some View {
        if transport == .wifi {
            hostField
        } else {
            bluetoothField
        }
    }

    private var hostField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPENFLIGHT PI")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                TextField("raspberrypi.local:8080", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .font(.callout.monospaced())
            .padding(12)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private var bluetoothField: some View {
        HStack(spacing: 12) {
            Image(systemName: "bluetooth")
                .foregroundStyle(bluetooth.supportsPhoneControls ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("OPENFLIGHT BLUETOOTH")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                Text(
                    bluetooth.supportsPhoneControls
                        ? "Connected and ready to calibrate"
                        : "Connect to an updated OpenFlight Pi"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private var measurementCard: some View {
        VStack(spacing: 16) {
            if let display = monitor.displayAngles {
                Label(
                    display.isStableAverage ? "STABLE 2-SECOND AVERAGE" : "LIVE SENSOR READING",
                    systemImage: display.isStableAverage ? "checkmark.circle.fill" : "waveform.path"
                )
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(display.isStableAverage ? .green : .cyan)

                HStack(spacing: 12) {
                    angleMetric(
                        title: "MOUNT TILT",
                        value: display.mountTiltDegrees,
                        color: display.isStableAverage ? .green : .cyan
                    )
                    angleMetric(
                        title: "LEFT / RIGHT ROLL",
                        value: display.rollDegrees,
                        color: abs(display.rollDegrees) <= 3
                            ? (display.isStableAverage ? .green : .cyan)
                            : .orange
                    )
                }

                if let measurement = monitor.measurement {
                    Label(readinessMessage(measurement), systemImage: readinessIcon(measurement))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(measurement.isReadyToSend ? .green : .orange)

                    Text(
                        "Stability ±\(max(measurement.tiltStandardDeviationDegrees, measurement.rollStandardDeviationDegrees).formatted(.number.precision(.fractionLength(2))))° from \(measurement.sampleCount) samples"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: monitor.progress)
                        .tint(.cyan)
                    Text(
                        "Collecting calibration average: \(monitor.sampleCount) / \(PhoneOrientationCalculator.minimumSampleCount) samples"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } else if let error = monitor.errorMessage {
                ContentUnavailableView(
                    "Motion unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "gyroscope")
                        .font(.system(size: 38))
                        .foregroundStyle(.green)
                    Text("Hold still while OpenFlight averages the sensors")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    ProgressView(value: monitor.progress)
                        .tint(.green)
                    Text("\(monitor.sampleCount) / \(PhoneOrientationCalculator.minimumSampleCount) samples")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var submissionCard: some View {
        VStack(spacing: 12) {
            Button {
                submit()
            } label: {
                HStack {
                    if isSending {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(isSending ? "Sending…" : "Apply Calibration")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .foregroundStyle(.black)
            .disabled(
                !(monitor.measurement?.isReadyToSend ?? false)
                    || !transportIsReady
                    || isSending
            )

            if let response {
                Label(
                    "Saved TI tilt: \(response.configuredIWRTiltDegrees.formatted(.number.precision(.fractionLength(2))))°",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
                Text(responseSummary(response))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let submissionError {
                Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private func angleMetric(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text("\(value.formatted(.number.precision(.fractionLength(2))))°")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }

    private func readinessMessage(_ measurement: PhoneOrientationMeasurement) -> String {
        if abs(measurement.rollDegrees) > PhoneOrientationCalculator.maximumRollDegrees {
            return "Level the radar left-to-right within 3°"
        }
        if measurement.tiltStandardDeviationDegrees > PhoneOrientationCalculator.maximumStandardDeviation
            || measurement.rollStandardDeviationDegrees > PhoneOrientationCalculator.maximumStandardDeviation
        {
            return "Keep the phone and radar still"
        }
        return measurement.isReadyToSend ? "Stable measurement ready" : "Adjust the radar angle"
    }

    private func readinessIcon(_ measurement: PhoneOrientationMeasurement) -> String {
        measurement.isReadyToSend ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func responseSummary(_ response: RadarCalibrationResponse) -> String {
        guard let enclosurePitch = response.enclosurePitchDegrees else {
            return "The measured phone tilt is now active and will be restored after restart."
        }
        return "Measured \(response.measuredMountTiltDegrees.formatted(.number.precision(.fractionLength(2))))° minus enclosure pitch \(enclosurePitch.formatted(.number.precision(.fractionLength(2))))°."
    }

    private func submit() {
        guard let measurement = monitor.measurement, measurement.isReadyToSend else { return }
        isSending = true
        response = nil
        submissionError = nil
        Task {
            do {
                switch transport {
                case .bluetooth:
                    response = try await bluetooth.submitCalibration(measurement)
                case .wifi:
                    response = try await client.submit(host: host, measurement: measurement)
                }
            } catch {
                submissionError = error.localizedDescription
            }
            isSending = false
        }
    }

    private var transportIsReady: Bool {
        transport == .wifi || bluetooth.supportsPhoneControls
    }
}
