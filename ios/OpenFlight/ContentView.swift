import SwiftUI

enum ShotTransport: String, CaseIterable, Identifiable {
    case bluetooth
    case wifi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bluetooth: "Bluetooth"
        case .wifi: "Wi-Fi"
        }
    }
}

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var wifi = WiFiShotClient()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDrivingRange = false
    @State private var showRadarCalibration = false
    @State private var isChangingClub = false
    @State private var clubError: String?

    @AppStorage("shotTransport") private var storedTransport = ShotTransport.bluetooth.rawValue
    @AppStorage("piHost") private var host = WiFiShotClient.defaultHost
    @AppStorage("selectedClub") private var storedClub = GolfClub.driver.rawValue

    private let clubClient = ClubSelectionClient()

    init() {
        _showDrivingRange = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--range-mode")
        )
    }

    private var transport: ShotTransport {
        ShotTransport(rawValue: storedTransport) ?? .bluetooth
    }

    private var state: ConnectionState {
        transport == .bluetooth ? bluetooth.state : wifi.state
    }

    private var latestShot: ShotEvent? {
        if ProcessInfo.processInfo.arguments.contains("--preview-shot") {
            return .preview
        }
        return shots.first
    }

    private var shots: [ShotEvent] {
        if ProcessInfo.processInfo.arguments.contains("--preview-shot") {
            return [.preview]
        }
        return transport == .bluetooth
            ? bluetooth.shotHistory.shots
            : wifi.shotHistory.shots
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.11, blue: 0.17), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 20) {
                    header
                    connectionCard

                    if let shot = latestShot {
                        shotCard(shot)
                            .id(shot.id)
                            .transition(.opacity)

                        if shots.count > 1 {
                            shotHistoryCard(Array(shots.dropFirst()))
                                .transition(.opacity)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(20)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25),
                    value: shots.map(\.id)
                )
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                startSelectedTransport()
            }
        }
        .onChange(of: storedTransport) {
            bluetooth.disconnect()
            wifi.disconnect()
            startSelectedTransport()
        }
        .onChange(of: state) {
            synchronizeStoredClubIfReady()
        }
        .onChange(of: bluetooth.supportsPhoneControls) {
            synchronizeStoredClubIfReady()
        }
        .onChange(of: wifi.activeClub) {
            if transport == .wifi, let club = wifi.activeClub {
                storedClub = club.rawValue
            }
        }
        .onChange(of: bluetooth.activeClub) {
            if transport == .bluetooth, let club = bluetooth.activeClub {
                storedClub = club.rawValue
            }
        }
        .fullScreenCover(isPresented: $showDrivingRange) {
            DrivingRangeView(
                latestShot: latestShot,
                selectedClub: selectedClub,
                isChangingClub: isChangingClub,
                clubSelectionEnabled: state == .connected,
                clubError: clubError,
                onSelectClub: changeClub
            )
        }
        .sheet(isPresented: $showRadarCalibration) {
            NavigationStack {
                RadarCalibrationView(
                    host: $host,
                    transport: transport,
                    bluetooth: bluetooth
                )
            }
        }
    }

    private func startSelectedTransport() {
        switch transport {
        case .bluetooth:
            bluetooth.start()
        case .wifi:
            wifi.start(host: host)
        }
    }

    private func retrySelectedTransport() {
        switch transport {
        case .bluetooth:
            bluetooth.retry()
        case .wifi:
            wifi.retry(host: host)
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
            Button {
                showDrivingRange = true
            } label: {
                Label("Range", systemImage: "mountain.2.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.green.opacity(0.16), in: Capsule())
                    .overlay {
                        Capsule().stroke(.green.opacity(0.42), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)
            .accessibilityIdentifier("dashboard.range")
            Image(systemName: "figure.golf")
                .font(.system(size: 34))
                .foregroundStyle(.green)
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 14) {
            Picker("Transport", selection: $storedTransport) {
                ForEach(ShotTransport.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.8), radius: 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state == .connected ? "OpenFlight Pi" : transport.label)
                        .font(.subheadline.weight(.semibold))
                    Text(state.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if state.canRetry {
                    Button("Retry") {
                        retrySelectedTransport()
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                } else if state != .connected {
                    ProgressView()
                        .tint(.green)
                }
            }

            if transport == .wifi {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                    TextField("raspberrypi.local:8080", text: $host)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit {
                            retrySelectedTransport()
                        }
                }
                .font(.callout.monospaced())
                .padding(12)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            }

            clubSelector

            Button {
                showRadarCalibration = true
            } label: {
                Label("Calibrate TI Radar", systemImage: "level.fill")
                    .font(.callout.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .accessibilityIdentifier("dashboard.calibrateRadar")
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private var selectedClub: GolfClub {
        GolfClub(rawValue: storedClub) ?? .driver
    }

    private var clubSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLUB FOR NEXT SHOT")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            ClubSelectionMenu(
                selectedClub: selectedClub,
                isChanging: isChangingClub,
                isEnabled: state == .connected,
                onSelect: changeClub
            ) {
                HStack {
                    Image(systemName: "figure.golf")
                    Text(selectedClub.displayName)
                        .fontWeight(.semibold)
                    Spacer()
                    if isChangingClub {
                        ProgressView().tint(.green)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                }
                .padding(12)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.clubSelector")

            if let clubError {
                Label(clubError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func changeClub(to club: GolfClub) {
        isChangingClub = true
        clubError = nil
        Task {
            do {
                let response: ClubSelectionResponse
                switch transport {
                case .bluetooth:
                    response = try await bluetooth.setClub(club)
                case .wifi:
                    response = try await clubClient.submit(host: host, club: club)
                }
                storedClub = response.club.rawValue
            } catch {
                clubError = error.localizedDescription
            }
            isChangingClub = false
        }
    }

    private func synchronizeStoredClubIfReady() {
        guard state == .connected, !isChangingClub else { return }
        if transport == .bluetooth, !bluetooth.supportsPhoneControls {
            return
        }
        isChangingClub = true
        clubError = nil
        Task {
            do {
                let response: ClubSelectionResponse
                switch transport {
                case .bluetooth:
                    response = try await bluetooth.currentClub()
                case .wifi:
                    response = try await clubClient.current(host: host)
                }
                storedClub = response.club.rawValue
            } catch {
                clubError = error.localizedDescription
            }
            isChangingClub = false
        }
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

            GeometryReader { geometry in
                let metricWidth = (geometry.size.width - 10) / 2

                HStack(spacing: 10) {
                    PrimaryMetric(
                        title: "BALL SPEED",
                        value: shot.ballSpeedMPH.formatted(.number.precision(.fractionLength(1))),
                        unit: "MPH"
                    )
                    .frame(width: metricWidth)
                    PrimaryMetric(
                        title: "CARRY",
                        value: shot.estimatedCarryYards.formatted(.number.precision(.fractionLength(0))),
                        unit: "YDS"
                    )
                    .frame(width: metricWidth)
                }
            }
            .frame(height: 108)

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
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func shotHistoryCard(_ previousShots: [ShotEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("PREVIOUS SHOTS")
                    .font(.caption.weight(.bold))
                    .tracking(1.7)
                    .foregroundStyle(.green)
                Spacer()
                Text(previousShots.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            LazyVStack(spacing: 0) {
                ForEach(Array(previousShots.enumerated()), id: \.element.id) { index, shot in
                    PreviousShotRow(shot: shot)
                        .transition(.opacity)

                    if index < previousShots.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Previous shots")
    }

    private var statusColor: Color {
        switch state {
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
        ShotMetricFormatter.number(value, decimals: decimals)
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
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Text(unit)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 82)
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
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
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                if !unit.isEmpty, value != "—" {
                    Text(unit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreviousShotRow: View {
    let shot: ShotEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(shot.displayClub)
                    .font(.headline)
                    .lineLimit(1)
                Text("Completed shot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HistoryMetric(
                value: shot.ballSpeedMPH.formatted(.number.precision(.fractionLength(1))),
                unit: "MPH"
            )
            HistoryMetric(
                value: shot.estimatedCarryYards.formatted(.number.precision(.fractionLength(0))),
                unit: "YDS"
            )
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryMetric: View {
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(unit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 62, alignment: .trailing)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
