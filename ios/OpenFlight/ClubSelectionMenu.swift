import SwiftUI

/// Shared club menu used by the dashboard and the full-screen range.
struct ClubSelectionMenu<MenuLabel: View>: View {
    let selectedClub: GolfClub
    let isChanging: Bool
    let isEnabled: Bool
    let onSelect: (GolfClub) -> Void
    private let label: () -> MenuLabel

    init(
        selectedClub: GolfClub,
        isChanging: Bool,
        isEnabled: Bool,
        onSelect: @escaping (GolfClub) -> Void,
        @ViewBuilder label: @escaping () -> MenuLabel
    ) {
        self.selectedClub = selectedClub
        self.isChanging = isChanging
        self.isEnabled = isEnabled
        self.onSelect = onSelect
        self.label = label
    }

    var body: some View {
        Menu {
            ForEach(GolfClub.allCases) { club in
                Button {
                    onSelect(club)
                } label: {
                    if club == selectedClub {
                        Label(club.displayName, systemImage: "checkmark")
                    } else {
                        Text(club.displayName)
                    }
                }
            }
        } label: {
            label()
        }
        .disabled(isChanging || !isEnabled)
    }
}
