import SwiftUI

enum ShotMetricFormatter {
    static func number(_ value: Double?, decimals: Int, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let formatted = value.formatted(.number.precision(.fractionLength(decimals)))
        return signed && value > 0 ? "+\(formatted)" : formatted
    }
}

struct RangeMetricsOverlay: View {
    let shot: ShotEvent?
    let trajectory: FlightTrajectory?
    let phase: DrivingRangeViewModel.Phase
    let isLandscape: Bool
    let selectedClub: GolfClub
    let isChangingClub: Bool
    let clubSelectionEnabled: Bool
    let clubError: String?
    let onSelectClub: (GolfClub) -> Void

    var body: some View {
        VStack(spacing: 12) {
            primaryMetrics
            Spacer(minLength: 20)
            secondaryMetrics
        }
        .padding(.horizontal, isLandscape ? 28 : 16)
        .padding(.top, isLandscape ? 16 : 72)
        .padding(.bottom, 14)
    }

    private var primaryMetrics: some View {
        HStack(spacing: 12) {
            RangePrimaryMetric(
                title: "BALL SPEED",
                value: ShotMetricFormatter.number(shot?.ballSpeedMPH, decimals: 1),
                unit: "MPH",
                accessibilityIdentifier: "range.ballSpeed"
            )
            RangePrimaryMetric(
                title: "CARRY",
                value: ShotMetricFormatter.number(shot?.estimatedCarryYards, decimals: 0),
                unit: "YDS",
                accessibilityIdentifier: "range.carry"
            )
        }
        .frame(maxWidth: isLandscape ? 540 : .infinity)
    }

    private var secondaryMetrics: some View {
        VStack(spacing: 8) {
            if let clubError {
                Label(clubError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.64), in: Capsule())
            }

            if trajectory?.provenance.usesEstimatedFlight == true {
                Label("Estimated flight uses club defaults", systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
            }

            let metrics = detailMetrics
            if isLandscape {
                HStack(spacing: 8) {
                    clubMetric
                    ForEach(metrics) { metric in
                        RangeDetailMetric(metric: metric)
                    }
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    clubMetric
                    ForEach(metrics) { metric in
                        RangeDetailMetric(metric: metric)
                    }
                }
            }
        }
    }

    private var detailMetrics: [RangeMetricValue] {
        [
            RangeMetricValue(
                title: "CLUB SPEED",
                value: ShotMetricFormatter.number(shot?.clubSpeedMPH, decimals: 1),
                unit: "mph"
            ),
            RangeMetricValue(
                title: "SMASH",
                value: ShotMetricFormatter.number(shot?.smashFactor, decimals: 2),
                unit: ""
            ),
            RangeMetricValue(
                title: "LAUNCH",
                value: ShotMetricFormatter.number(shot?.launchAngleVertical, decimals: 1),
                unit: "°"
            ),
            RangeMetricValue(
                title: "DIRECTION",
                value: ShotMetricFormatter.number(shot?.launchAngleHorizontal, decimals: 1, signed: true),
                unit: "°"
            ),
            RangeMetricValue(
                title: "SPIN",
                value: ShotMetricFormatter.number(shot?.spinRPM, decimals: 0),
                unit: "rpm"
            ),
            RangeMetricValue(
                title: "PATH",
                value: ShotMetricFormatter.number(shot?.clubPathDegrees, decimals: 1, signed: true),
                unit: "°"
            ),
            RangeMetricValue(
                title: "SPIN AXIS",
                value: ShotMetricFormatter.number(shot?.spinAxisDegrees, decimals: 1, signed: true),
                unit: "°"
            ),
        ]
    }

    private var clubMetric: some View {
        ClubSelectionMenu(
            selectedClub: selectedClub,
            isChanging: isChangingClub,
            isEnabled: clubSelectionEnabled,
            onSelect: onSelectClub
        ) {
            HStack(spacing: 5) {
                VStack(spacing: 2) {
                    Text("NEXT CLUB")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                    Text(selectedClub.displayName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity)

                if isChangingClub {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.green)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 45)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.green.opacity(0.48), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Club for next shot, \(selectedClub.displayName)")
        .accessibilityIdentifier("range.clubSelector")
    }
}

private struct RangeMetricValue: Identifiable {
    let title: String
    let value: String
    let unit: String

    var id: String { title }
}

private struct RangePrimaryMetric: View {
    let title: String
    let value: String
    let unit: String
    let accessibilityIdentifier: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.72))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct RangeDetailMetric: View {
    let metric: RangeMetricValue

    var body: some View {
        VStack(spacing: 2) {
            Text(metric.title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !metric.unit.isEmpty, metric.value != "—" {
                    Text(metric.unit)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 45)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.13), lineWidth: 0.8)
        }
    }
}
