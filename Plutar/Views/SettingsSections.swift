import SwiftUI

/// Shared building blocks for the display-settings UI — iOS's `SettingsSheet`
/// and macOS's `MacSettingsView` both lay out a title above its pills the
/// same way and toggle the same "selected" pill look, so both reuse these
/// instead of each defining their own `section(_:)`/`pill(_:)` helpers.

/// The 2-column grid both settings screens lay their "Police" and "Thème"
/// pills out in.
let settingsGridColumns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

/// A titled group of settings controls — sentence case, no forced all-caps.
struct SettingsSectionView<Content: View>: View {
    let title: String
    var titleWeight: Font.Weight = .semibold
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .fontWeight(titleWeight)
                .foregroundStyle(.primary)
            content()
        }
    }
}

/// The selected-pill look shared by `SettingsPillButton` and
/// `SettingsThemePillButton` — `.glassProminent`, tinted with `chipColor`,
/// when selected; plain `.glass` otherwise. There's no single `ButtonStyle`
/// value that branches on `isActive`, so the two cases are two separate
/// branches under an `if`; SwiftUI's `ViewBuilder` erases them to the same
/// opaque return type.
private struct SettingsPillStyle: ViewModifier {
    let isActive: Bool
    let chipColor: Color

    func body(content: Content) -> some View {
        if isActive {
            content
                .buttonStyle(.glassProminent)
                .tint(chipColor)
        } else {
            content
                .buttonStyle(.glass)
        }
    }
}

/// A single pill-style option button.
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
        Button(action: action) { Text(label).font(font) }
            .modifier(SettingsPillStyle(isActive: isActive, chipColor: chipColor))
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
        Button(action: action) { label }
            .modifier(SettingsPillStyle(isActive: isActive, chipColor: chipColor))
    }

    private var label: some View {
        HStack(spacing: 7) {
            Circle().fill(theme.dotColor).frame(width: 12, height: 12)
            Text(theme.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// iOS Settings-style action cell: a full-width rounded cell with the label
/// in the system accent color, in place of a glass button. Used by the
/// iOS "Avancé" page and `BackupSection(usesCells:)`.
struct SettingsCellButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Self.labelColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Self.cellColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.6 : 1))
    }

    /// The system accent color (system blue) — deliberately not `.tint`,
    /// which carries the theme's own accent here.
    private static var labelColor: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBlue)
        #else
        Color(nsColor: .controlAccentColor)
        #endif
    }

    private static var cellColor: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

extension View {
    /// The glass button used on the Mac, or the iOS Settings-style cell.
    @ViewBuilder
    func settingsActionStyle(cells: Bool) -> some View {
        if cells {
            buttonStyle(SettingsCellButtonStyle())
        } else {
            buttonStyle(.glass)
        }
    }
}
