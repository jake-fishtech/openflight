import SwiftUI

struct DrivingRangeView: View {
    let latestShot: ShotEvent?
    let selectedClub: GolfClub
    let isChangingClub: Bool
    let clubSelectionEnabled: Bool
    let clubError: String?
    let onSelectClub: (GolfClub) -> Void
    private let autoplayShot: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: DrivingRangeViewModel

    init(
        latestShot: ShotEvent?,
        selectedClub: GolfClub = .driver,
        isChangingClub: Bool = false,
        clubSelectionEnabled: Bool = true,
        clubError: String? = nil,
        onSelectClub: @escaping (GolfClub) -> Void = { _ in },
        autoplayShot: Bool = false
    ) {
        self.latestShot = latestShot
        self.selectedClub = selectedClub
        self.isChangingClub = isChangingClub
        self.clubSelectionEnabled = clubSelectionEnabled
        self.clubError = clubError
        self.onSelectClub = onSelectClub
        self.autoplayShot = autoplayShot
        _viewModel = StateObject(
            wrappedValue: DrivingRangeViewModel(currentShot: latestShot)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                RangeSceneView(
                    trajectory: viewModel.activeTrajectory,
                    reduceMotion: reduceMotion,
                    onFlightCompleted: viewModel.animationCompleted
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.38), .clear, .black.opacity(0.60)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                RangeMetricsOverlay(
                    shot: viewModel.displayedShot,
                    trajectory: viewModel.activeTrajectory,
                    phase: viewModel.phase,
                    isLandscape: isLandscape,
                    selectedClub: selectedClub,
                    isChangingClub: isChangingClub,
                    clubSelectionEnabled: clubSelectionEnabled,
                    clubError: clubError,
                    onSelectClub: onSelectClub
                )

                if viewModel.displayedShot == nil {
                    waitingCard
                }

                controls
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if autoplayShot || ProcessInfo.processInfo.arguments.contains("--preview-flight") {
                viewModel.replayDisplayedShot()
            }
        }
        .onChange(of: latestShot?.eventID) {
            viewModel.observe(latestShot)
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                viewModel.suspend()
            }
        }
        .onDisappear {
            viewModel.suspend()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.suspend()
                dismiss()
            } label: {
                Label("Exit", systemImage: "xmark")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay {
                        Capsule().stroke(.white.opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("range.exit")

            Spacer()

            Label(viewModel.phase.label, systemImage: statusSymbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.black.opacity(0.58), in: Capsule())

            if viewModel.displayedShot != nil,
               viewModel.phase != .preparing,
               viewModel.phase != .flying
            {
                Button {
                    viewModel.replayDisplayedShot()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.6), in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay shot")
                .accessibilityIdentifier("range.replay")
            }
        }
    }

    private var waitingCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.golf")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.green)
            Text("Driving Range Ready")
                .font(.title2.bold())
            Text("Hit a shot and its flight will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .padding(24)
    }

    private var statusSymbol: String {
        switch viewModel.phase {
        case .waiting: "circle.dotted"
        case .preparing: "waveform.path.ecg"
        case .flying: "smallcircle.filled.circle"
        case .landed: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

struct DrivingRangeView_Previews: PreviewProvider {
    static var previews: some View {
        DrivingRangeView(latestShot: .preview, autoplayShot: true)
            .previewDisplayName("Sample Driver Shot")
    }
}
