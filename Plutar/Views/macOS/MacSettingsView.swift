import SwiftUI
import SwiftData

/// The macOS Settings window (Cmd+, / menu Plutar > Réglages), opened via
/// the app's `Settings { }` Scene — see `PlutarMacApp`. Two tabs:
///
/// - "Général": the same display settings as iOS's "Affichage" sheet
///   (`SettingsSheet`) minus its "Avancé" section, and minus the shake
///   toggle entirely (macOS has no shake gesture — `ShakeGesture`/
///   `FlipCard` are UIKit-only and aren't part of this target).
/// - "Avancé": `SettingsSheet`'s Avancé section minus the shake toggle —
///   "Réinitialiser le classement", "Vider le fil", and "Actualiser" (moved
///   here from `MacFeedList`'s toolbar — a manual retry for enrichment, not
///   really "sync now" any more now that CloudKit push keeps the app caught
///   up on its own; see `PlutarMacApp`/`AppDelegate`).
///
/// Reads/writes the same `@AppStorage` keys as iOS — display settings are
/// per-device UI preferences, not synced content, so this is deliberately
/// not part of the CloudKit-synced `LinkItem`/`SourceRank` store.
struct MacSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query private var allItems: [LinkItem]
    @Query private var sourceRanks: [SourceRank]

    @AppStorage(DisplaySettingsKey.theme) private var themeRaw = AppTheme.scand.rawValue
    @AppStorage(DisplaySettingsKey.appearance) private var appearanceRaw = AppAppearance.auto.rawValue
    @AppStorage(DisplaySettingsKey.font) private var fontRaw = AppFont.rounded.rawValue
    @AppStorage(DisplaySettingsKey.layout) private var layoutRaw = LinkLayout.rail.rawValue
    @AppStorage(DisplaySettingsKey.blackSoirBackground) private var blackSoirBackground = false

    @State private var showResetRankingConfirm = false
    @State private var showClearFeedConfirm = false
    @State private var isRefreshing = false
    /// Raised by `persist()` when a write to the store fails — mirrors
    /// `RootView.saveFailed`. Matters here specifically because both actions
    /// in the Avancé tab are presented as irreversible.
    @State private var saveFailed = false

    private var selectedTheme: AppTheme { AppTheme(rawValue: themeRaw) ?? .scand }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .auto }
    private var theme: AppTheme {
        AppTheme.resolved(selected: selectedTheme, appearance: appearance, systemColorScheme: systemColorScheme)
    }
    private var appFont: AppFont { AppFont(rawValue: fontRaw) ?? .rounded }
    private var layout: LinkLayout { LinkLayout(rawValue: layoutRaw) ?? .rail }

    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        TabView {
            Tab("Général", systemImage: "paintbrush") {
                generalTab
            }
            Tab("Avancé", systemImage: "gearshape.2") {
                advancedTab
            }
        }
        .frame(width: 420, height: 480)
        .alert("Enregistrement impossible", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La dernière modification n'a pas pu être enregistrée et sera perdue à la fermeture de l'app.")
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSectionView(title: "Police", titleWeight: .regular) {
                    // A 2-column grid, not the single `HStack` row this used
                    // to be — four options (since "Helvetica Neue Courant"
                    // joined "Helvetica Neue Bold") no longer fit one row at
                    // this window's 420pt width without overflowing.
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach([AppFont.helveticaCourant, .sfCompact, .helvetica, .rounded]) { f in
                            SettingsPillButton(f.label, isActive: appFont == f, font: f.font(size: 13, weight: f == .rounded ? .bold : .regular), chipColor: theme.chip) {
                                fontRaw = f.rawValue
                            }
                        }
                    }
                }

                SettingsSectionView(title: "Thème", titleWeight: .regular) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(AppTheme.selectable) { t in
                            SettingsThemePillButton(theme: t, isActive: theme == t, chipColor: theme.chip) {
                                themeRaw = t.rawValue
                                appearanceRaw = (t.isSoir ? AppAppearance.dark : .light).rawValue
                            }
                        }
                    }
                }

                Toggle(isOn: $blackSoirBackground) {
                    Text("Fond noir pour les thèmes nuit")
                }

                SettingsSectionView(title: "Apparence", titleWeight: .regular) {
                    HStack(spacing: 8) {
                        ForEach(AppAppearance.allCases) { a in
                            SettingsPillButton(a.label, isActive: appearance == a, chipColor: theme.chip) { appearanceRaw = a.rawValue }
                        }
                    }
                }

                SettingsSectionView(title: "Présentation du fil", titleWeight: .regular) {
                    HStack(spacing: 8) {
                        ForEach(LinkLayout.allCases) { l in
                            SettingsPillButton(l.label, isActive: layout == l, chipColor: theme.chip) { layoutRaw = l.rawValue }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(role: .destructive) {
                        showResetRankingConfirm = true
                    } label: {
                        Text("Réinitialiser le classement")
                    }
                    .buttonStyle(.glass)
                    .confirmationDialog(
                        "Réinitialiser le classement ?",
                        isPresented: $showResetRankingConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Réinitialiser", role: .destructive, action: resetSourceRanking)
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Le classement cumulé des sources sera remis à zéro. Cette action est irréversible.")
                    }

                    Text("Le classement des sources les plus partagées sera remis à zéro")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button(role: .destructive) {
                        showClearFeedConfirm = true
                    } label: {
                        Text("Vider le fil")
                    }
                    .buttonStyle(.glass)
                    .confirmationDialog(
                        "Vider le fil ?",
                        isPresented: $showClearFeedConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Vider", role: .destructive, action: clearAll)
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Tous les liens seront supprimés définitivement.")
                    }

                    Text("Les liens non-lus et lus seront supprimés")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Actualiser")
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(isRefreshing)

                    // No supported API forces CloudKit to pull sooner —
                    // sync itself stays automatic/background. This re-runs
                    // the same enrichment pass PlutarMacApp already does on
                    // launch/foreground, so a link enriched or thumbnailed
                    // on iOS doesn't have to wait for this Mac to relaunch
                    // or background-and-foreground before catching up.
                    Text("Relance la récupération des titres et vignettes en attente")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            PlutarLog.store.error("Save failed (macOS settings): \(String(describing: error), privacy: .public)")
            saveFailed = true
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await LinkMetadataEnricher.enrichPendingLinks(in: modelContext)
    }

    private func resetSourceRanking() {
        for rank in sourceRanks { modelContext.delete(rank) }
        persist()
    }

    private func clearAll() {
        for item in allItems {
            SharedStore.deleteThumbnailFile(named: item.thumbnailFileName)
            modelContext.delete(item)
        }
        persist()
    }
}
