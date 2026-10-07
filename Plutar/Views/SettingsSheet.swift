import SwiftUI

/// Reports the natural height of the settings content up to `SettingsSheet`
/// so it can size the presentation detent to fit instead of using a fixed
/// or full-screen height.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
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
    /// Forces every "soir" theme's view background to pure black instead of
    /// its own defined color.
    @Binding var blackSoirBackground: Bool
    /// Whether shaking the device (see `RootView.shakeToRandomizeTheme`)
    /// picks a new theme within the current light/soir family.
    @Binding var shakeToChangeTheme: Bool
    @Binding var layout: LinkLayout
    let onClearUnread: () -> Void
    let onClearRead: () -> Void
    let onResetRanking: () -> Void
    let onClose: () -> Void
    /// Same color as the day/source pill and counter badge — applied only
    /// to the selected pills' fill below, not to the whole sheet (that
    /// broadly cascaded into the toolbar's close icon and other text
    /// rendering unexpectedly white).
    let chipColor: Color

    /// Room for the inline nav bar and the home-indicator safe area below
    /// the scroll view.
    private static let chromeAllowance: CGFloat = 100
    /// Upper bound on the proposed detent. Past this the sheet is full
    /// height anyway and the ScrollView takes over, so there is nothing to
    /// gain from a taller one — and it stops an accessibility text size from
    /// driving the measurement somewhere absurd.
    private static let maxDetentHeight: CGFloat = 860

    /// Measured height of the actual content, so the sheet only opens as
    /// tall as it needs to instead of always going full-screen. The value
    /// starts at a reasonable guess and is corrected once layout runs.
    @State private var contentHeight: CGFloat = 480

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsSectionView(title: "Police") {
                        HStack(spacing: 8) {
                            // Not `AppFont.allCases`'s declaration order —
                            // see `AppFont.settingsOrder`.
                            ForEach(AppFont.settingsOrder) { f in
                                SettingsPillButton(f.label, isActive: appFont == f, font: f.pillFont(size: 17), chipColor: chipColor) {
                                    appFont = f
                                }
                            }
                        }
                    }

                    SettingsSectionView(title: "Thème") {
                        LazyVGrid(columns: settingsGridColumns, spacing: 8) {
                            ForEach(AppTheme.allCases) { t in
                                SettingsThemePillButton(theme: t, isActive: theme == t, chipColor: chipColor) {
                                    theme = t
                                }
                            }
                        }
                    }

                    Toggle(isOn: $blackSoirBackground) {
                        Text("Fond noir pour les thèmes nuit")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Toggle(isOn: $shakeToChangeTheme) {
                        Text("Secouer pour changer de thème")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    SettingsSectionView(title: "Apparence") {
                        HStack(spacing: 8) {
                            ForEach(AppAppearance.allCases) { a in
                                SettingsPillButton(a.label, isActive: appearance == a, chipColor: chipColor) { appearance = a }
                            }
                        }
                    }

                    SettingsSectionView(title: "Présentation des liens") {
                        HStack(spacing: 8) {
                            ForEach(LinkLayout.allCases) { l in
                                SettingsPillButton(l.label, isActive: layout == l, chipColor: chipColor) { layout = l }
                            }
                        }
                    }

                    // Opens its own page: backups, clearing the feeds, resetting
                    // the ranking.
                    NavigationLink {
                        AdvancedSettingsView(
                            onClearUnread: onClearUnread,
                            onClearRead: onClearRead,
                            onResetRanking: onResetRanking
                        )
                    } label: {
                        HStack {
                            Text("Avancé")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // A rule, then 10pt, then the credit.
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Florian Innocente")
                            // A tap opens the site.
                            Link("florianinnocente.com", destination: URL(string: "https://florianinnocente.com")!)
                        }
                        .font(.footnote)
                        .foregroundStyle(Color(white: 0.4))
                        .tint(Color(white: 0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            .navigationTitle("Réglages")
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
            // This is a feedback loop: the measured height sets the detent,
            // the detent resizes the sheet, and that re-runs the
            // measurement. It converges because the width never changes, but
            // the theme `LazyVGrid` reports a growing height as it
            // materializes its rows, so the loop fires several times on
            // open. Ignoring sub-point differences stops the last of those
            // from resizing the sheet again over a rounding artefact.
            let proposed = min(height + Self.chromeAllowance, Self.maxDetentHeight)
            guard abs(proposed - contentHeight) > 1 else { return }
            contentHeight = proposed
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        // iPad shows a form sheet that ignores the detent above and is too
        // short for the whole page (the "Avancé" row and the credit sat
        // below the fold): use the taller page sizing there.
        .iPadPageSizing()
    }
}

/// The page behind "Avancé" in the settings: backups, clearing the feeds
/// and resetting the ranking. The confirmation dialogs live here, so the
/// callbacks (which also close the settings sheet) are all that crosses over.
private struct AdvancedSettingsView: View {
    let onClearUnread: () -> Void
    let onClearRead: () -> Void
    let onResetRanking: () -> Void

    @State private var showResetRankingConfirm = false
    @State private var showClearFeedConfirm = false
    @State private var showClearReadConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BackupSection(captionFont: .footnote, usesCells: true)

                SettingsSectionView(title: "Suppression") {
                    VStack(alignment: .leading, spacing: 24) {

                    VStack(alignment: .leading, spacing: 8) {
                        Button(role: .destructive) {
                            showClearFeedConfirm = true
                        } label: {
                            Text("Vider le fil À lire…")
                        }
                        .buttonStyle(SettingsCellButtonStyle())
                        .confirmationDialog(
                            "Vider le fil À lire",
                            isPresented: $showClearFeedConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Vider", role: .destructive, action: onClearUnread)
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text("Tous les liens À lire seront supprimés définitivement.")
                        }

                        Text("Supprime tous les liens non-lus.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button(role: .destructive) {
                            showClearReadConfirm = true
                        } label: {
                            Text("Vider le fil Lus…")
                        }
                        .buttonStyle(SettingsCellButtonStyle())
                        .confirmationDialog(
                            "Supprimer tous les liens lus",
                            isPresented: $showClearReadConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Supprimer", role: .destructive, action: onClearRead)
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text("Tous les liens lus seront supprimés définitivement.")
                        }

                        Text("Supprime tous les liens déjà lus.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button(role: .destructive) {
                            showResetRankingConfirm = true
                        } label: {
                            Text("Réinitialiser le classement…")
                        }
                        .buttonStyle(SettingsCellButtonStyle())
                        .confirmationDialog(
                            "Réinitialiser le classement",
                            isPresented: $showResetRankingConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Réinitialiser", role: .destructive, action: onResetRanking)
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text("Le classement cumulé des sources sera remis à zéro. Cette action est irréversible.")
                        }

                        Text("Remise à zéro du classement des 15 sources les plus partagées.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Avancé")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    /// iPad only: the taller page sizing (iPhone keeps its height detent).
    @ViewBuilder
    func iPadPageSizing() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
