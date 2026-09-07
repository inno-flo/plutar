import SwiftUI

/// Reports the natural height of the settings content up to `SettingsSheet`
/// so it can size the presentation detent to fit instead of using a fixed
/// or full-screen height.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The "Affichage" drawer from the mockup: theme, font, density and timeline
/// layout, plus destructive/regenerate feed actions.
struct SettingsSheet: View {
    @Binding var theme: AppTheme
    @Binding var appearance: AppAppearance
    @Binding var appFont: AppFont
    @Binding var showThumbnails: Bool
    /// Experimental test setting: forces every "soir" theme's view
    /// background to pure black.
    @Binding var blackSoirBackground: Bool
    @Binding var layout: LinkLayout
    let onClearAll: () -> Void
    let onRegenerate: () -> Void
    let onClose: () -> Void
    /// Same color as the day/source pill and counter badge — applied only
    /// to the selected pills' fill below, not to the whole sheet (that
    /// broadly cascaded into the toolbar's close icon and other text
    /// rendering unexpectedly white).
    let chipColor: Color

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    /// Measured height of the actual content, so the sheet only opens as
    /// tall as it needs to instead of always going full-screen. The value
    /// starts at a reasonable guess and is corrected once layout runs.
    @State private var contentHeight: CGFloat = 480

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Police") {
                        HStack(spacing: 8) {
                            ForEach(AppFont.allCases) { f in
                                pill(f.label, isActive: appFont == f, font: f.font(size: 17)) {
                                    appFont = f
                                }
                            }
                        }
                    }

                    section("Thème") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(AppTheme.selectable) { t in
                                themePill(t)
                            }
                        }
                    }

                    Toggle(isOn: $blackSoirBackground) {
                        Text("Fond noir pour les thèmes soir")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    section("Apparence") {
                        HStack(spacing: 8) {
                            ForEach(AppAppearance.allCases) { a in
                                pill(a.label, isActive: appearance == a) { appearance = a }
                            }
                        }
                    }

                    section("Liens") {
                        Toggle(isOn: $showThumbnails) {
                            Text("Afficher les vignettes")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    section("Présentation du fil") {
                        HStack(spacing: 8) {
                            ForEach(LinkLayout.allCases) { l in
                                pill(l.label, isActive: layout == l) { layout = l }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button(role: .destructive, action: onClearAll) {
                            Text("Vider le fil")
                                .font(.system(size: 11.5, weight: .semibold))
                                .tracking(1.2)
                                .textCase(.uppercase)
                        }
                        .buttonStyle(.glass)

                        Button(action: onRegenerate) {
                            Text("Regénérer les liens")
                                .font(.system(size: 11.5, weight: .semibold))
                                .tracking(1.2)
                                .textCase(.uppercase)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.top, 6)
                }
                .padding(20)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .navigationTitle("Affichage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onClose) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .onPreferenceChange(ContentHeightKey.self) { height in
            // Content height plus room for the inline nav bar and the
            // home-indicator safe area below the scroll view.
            contentHeight = height + 100
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            // Sentence case, no forced all-caps.
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: iOS 26 standard (Liquid Glass) button look, currently in use.
    // `.glassProminent` reads as "selected", plain `.glass` as "unselected" —
    // there's no single ButtonStyle value that branches on `isActive`, so the
    // two cases are two separate buttons under an `if`; SwiftUI's ViewBuilder
    // erases them to the same opaque return type.

    @ViewBuilder
    private func pill(_ label: String, isActive: Bool, font: Font? = nil, action: @escaping () -> Void) -> some View {
        if isActive {
            Button(action: action) { Text(label).font(font) }
                .buttonStyle(.glassProminent)
                .tint(chipColor)
        } else {
            Button(action: action) { Text(label).font(font) }
                .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private func themePill(_ t: AppTheme) -> some View {
        if theme == t {
            Button { theme = t } label: { themeLabel(t) }
                .buttonStyle(.glassProminent)
                .tint(chipColor)
        } else {
            Button { theme = t } label: { themeLabel(t) }
                .buttonStyle(.glass)
        }
    }

    private func themeLabel(_ t: AppTheme) -> some View {
        HStack(spacing: 7) {
            Circle().fill(t.swatch).frame(width: 12, height: 12)
            Text(t.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Previous (pre-iOS 26) look — kept unused on the side in case this
    // gets reverted. Not called anywhere right now; see `pill`/`themePill`
    // above for what's actually live.

    private func legacyPill(_ label: String, isActive: Bool, font: Font? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(font)
        }
        .buttonStyle(PillButtonStyle(isActive: isActive))
    }

    private func legacyThemePill(_ t: AppTheme) -> some View {
        Button {
            theme = t
        } label: {
            themeLabel(t)
        }
        .buttonStyle(PillButtonStyle(isActive: theme == t))
    }
}

/// Previous pill look (solid accent fill / secondary tint), kept for a
/// possible revert — see the "Previous (pre-iOS 26) look" section above.
private struct PillButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
