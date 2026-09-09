import SwiftUI

/// Shown when the current view/mode has nothing to display. In this
/// no-Share-Extension phase, "Simuler un partage" is how new links get
/// added — standing in for the real iOS share sheet. A quiet "moon.stars"
/// glyph, wider spacing before the title (~2 blank lines) and a single
/// line's worth before the subtitle, set in the Affichage font instead of
/// the system font.
struct QuietEmptyStateView: View {
    let theme: AppTheme
    let appFont: AppFont
    let icon: String
    let title: String
    let text: String
    let showsSimulateButton: Bool
    let onSimulateShare: () -> Void
    /// True (the default) centers the block in the full available height —
    /// the ordinary case, an overlay on an otherwise-empty list. Sources
    /// passes false when the source ranking still has entries: there the
    /// block is placed as a normal row above the ranking instead of an
    /// overlay, and sizing it to the full height would push the ranking
    /// off-screen.
    var fillHeight: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.ink(0.3))

            Text(title)
                .font(appFont.font(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 40)

            Text(text)
                .font(appFont.font(size: 13))
                .foregroundStyle(theme.ink(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.top, 20)

            if showsSimulateButton {
                Button(action: onSimulateShare) {
                    Text("Simuler un partage")
                        .font(appFont.font(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(theme.ink(1))
                        .foregroundStyle(theme.background)
                        .clipShape(Capsule())
                }
                .padding(.top, 24)
            }
        }
        .padding(.horizontal, 46)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)
    }
}
