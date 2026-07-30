import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.11, blue: 0.17), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    connectionCard

                    if let shot = bluetooth.latestShot {
                        shotCard(shot)
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            bluetooth.start()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OPENFLIGHT")
                    .font(.caption.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(.green)
                Text("Launch Monitor")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 34))
                .foregroundStyle(.green)
        }
    }

    private var connectionCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.8), radius: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(bluetooth.state == .connected ? "OpenFlight Pi" : "Bluetooth")
                    .font(.subheadline.weight(.semibold))
                Text(bluetooth.state.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if bluetooth.state.canRetry {
                Button("Retry") {
                    bluetooth.retry()
                }
                .buttonStyle(.bordered)
                .tint(.green)
            } else if bluetooth.state != .connected {
                ProgressView()
                    .tint(.green)
            }
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Waiting for a shot", systemImage: "dot.radiowaves.left.and.right")
        } description: {
            Text("Connect to your OpenFlight Pi, then hit a ball.")
        }
        .frame(minHeight: 300)
    }

    private func shotCard(_ shot: ShotEvent) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LATEST SHOT")
                        .font(.caption.weight(.bold))
                        .tracking(1.7)
                        .foregroundStyle(.green)
                    Text(shot.displayClub)
                        .font(.title2.bold())
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                PrimaryMetric(
                    title: "BALL SPEED",
                    value: shot.ballSpeedMPH.formatted(.number.precision(.fractionLength(1))),
                    unit: "MPH"
                )
                PrimaryMetric(
                    title: "CARRY",
                    value: shot.estimatedCarryYards.formatted(.number.precision(.fractionLength(0))),
                    unit: "YDS"
                )
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                GridRow {
                    DetailMetric(
                        title: "Club speed",
                        value: formatted(shot.clubSpeedMPH, decimals: 1),
                        unit: "mph"
                    )
                    DetailMetric(
                        title: "Smash",
                        value: formatted(shot.smashFactor, decimals: 2)
                    )
                }
                GridRow {
                    DetailMetric(
                        title: "Launch",
                        value: formatted(shot.launchAngleVertical, decimals: 1),
                        unit: "°"
                    )
                    DetailMetric(
                        title: "Direction",
                        value: formatted(shot.launchAngleHorizontal, decimals: 1),
                        unit: "°"
                    )
                }
                GridRow {
                    DetailMetric(
                        title: "Spin",
                        value: formatted(shot.spinRPM, decimals: 0),
                        unit: "rpm"
                    )
                    DetailMetric(
                        title: "Club path",
                        value: formatted(shot.clubPathDegrees, decimals: 1),
                        unit: "°"
                    )
                }
                GridRow {
                    DetailMetric(
                        title: "Spin axis",
                        value: formatted(shot.spinAxisDegrees, decimals: 1),
                        unit: "°"
                    )
                    Color.clear
                }
            }
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var statusColor: Color {
        switch bluetooth.state {
        case .connected:
            .green
        case .scanning, .connecting, .discovering:
            .orange
        case .error, .unavailable:
            .red
        case .idle:
            .gray
        }
    }

    private func formatted(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }
}

private struct PrimaryMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 37, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    var unit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.headline.monospacedDigit())
                if !unit.isEmpty, value != "—" {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
