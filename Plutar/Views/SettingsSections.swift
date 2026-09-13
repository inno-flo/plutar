import SwiftUI

/// Shared building blocks for the display-settings UI — iOS's `SettingsSheet`
/// and macOS's `MacSettingsView` both lay out a title above its pills the
/// same way and toggle the same "selected" pill look, so both reuse these
/// instead of each defining their own `section(_:)`/`pill(_:)` helpers.

/// A titled group of settings controls — sentence case, no forced all-caps.
struct SettingsSectionView<Content: View>: View {
    let title: String
    var titleWeight: Font.Weight = .semibold
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .fontWeight(titleWeight)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// A single pill-style option button — `.glassProminent`, tinted with
/// `chipColor`, when selected; plain `.glass` otherwise. There's no single
/// `ButtonStyle` value that branches on `isActive`, so the two cases are two
/// separate buttons under an `if`; SwiftUI's `ViewBuilder` erases them to the
/// same opaque return type.
struct SettingsPillButton: View {
    let label: String
    let isActive: Bool
    var font: Font?
    let chipColor: Color
    let action: () -> Void

    init(_ label: String, isActive: Bool, font: Font? = nil, chipColor: Color, action: @escaping () -> Void) {
        self.label = label
        self.isActive = isActive
        self.font = font
        self.chipColor = chipColor
        self.action = action
    }

    var body: some View {
        if isActive {
            Button(action: action) { Text(label).font(font) }
                .buttonStyle(.glassProminent)
                .tint(chipColor)
        } else {
            Button(action: action) { Text(label).font(font) }
                .buttonStyle(.glass)
        }
    }
}

/// One theme swatch in the "Thème" grid — a color dot plus its name, same
/// selected-pill treatment as `SettingsPillButton`.
struct SettingsThemePillButton: View {
    let theme: AppTheme
    let isActive: Bool
    let chipColor: Color
    let action: () -> Void

    var body: some View {
        if isActive {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(chipColor)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
        }
    }

    private var label: some View {
        HStack(spacing: 7) {
            Circle().fill(theme.chip).frame(width: 12, height: 12)
            Text(theme.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
