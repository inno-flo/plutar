import SwiftUI

/// Shown when the current tab/search has nothing to display. In this
/// no-Share-Extension phase, "Simuler un partage" is how new links get
/// added — standing in for the real iOS share sheet.
struct EmptyStateView: View {
    let theme: AppTheme
    let title: String
    let text: String
    let showsSimulateButton: Bool
    let onSimulateShare: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("00")
                .font(.system(size: 76, weight: .light))
                .foregroundStyle(theme.ink(0.16))
            Text(title)
                .font(.system(size: 17))
                .tracking(0.6)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            if showsSimulateButton {
                Button(action: onSimulateShare) {
                    Text("Simuler un partage")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(theme.ink(1))
                        .foregroundStyle(theme.background)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 110)
        .padding(.horizontal, 46)
        .frame(maxWidth: .infinity)
    }
}
