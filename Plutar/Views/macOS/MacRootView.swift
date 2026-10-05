import SwiftUI
import SwiftData

/// macOS's window content: a HIG-style sidebar (`MacSidebarView`) driving a
/// detail column (`MacFeedList`), replacing the old top-strip `TabView`.
/// "Date" and "Lus" are plain sidebar rows; each source is its own row under
/// a disclosed "Sources" group, so picking one shows just that source's
/// links rather than a shared, expand-per-source "Sources" screen. The
/// Sources group also carries a "Classement" row (`MacSourceRankingView`) for
/// the standing, all-time `SourceRank` tally. Display settings live in a
/// real `Settings` scene (Cmd+,) — see `MacSettingsView`.
/// No shake-to-theme here either (`ShakeGesture` is UIKit-only and stays out
/// of this target's sources).
struct MacRootView: View {
    /// Not `@Environment(\.colorScheme)` — see `SystemAppearanceObserver`'s
    /// doc comment for why that gets corrupted by this same view's own
    /// `.preferredColorScheme` below.
    @StateObject private var systemAppearance = SystemAppearanceObserver()
    @Query(sort: \LinkItem.dateAdded, order: .reverse) private var allItems: [LinkItem]
    /// Only fetched for the sidebar's "Classement" row — see
    /// `MacSourceRankingView`.
    @Query(sort: \SourceRank.count, order: .reverse) private var sourceRanks: [SourceRank]

    @AppStorage(DisplaySettingsKey.theme) private var themeRaw = AppTheme.scand.rawValue
    @AppStorage(DisplaySettingsKey.appearance) private var appearanceRaw = AppAppearance.auto.rawValue
    @AppStorage(DisplaySettingsKey.font) private var fontRaw = AppFont.rounded.rawValue
    // Détaillée par défaut sur Mac (iOS garde Simple) — and remembered across launches.
    @AppStorage(DisplaySettingsKey.layout) private var layoutRaw = LinkLayout.card.rawValue
    @AppStorage(DisplaySettingsKey.sidebarSelection) private var selectionRaw = SidebarSelection.date.storageKey
    @AppStorage(DisplaySettingsKey.blackSoirBackground) private var blackSoirBackground = false

    /// Backed by `selectionRaw` so the last active section survives a quit;
    /// first launch (nothing stored) lands on "À lire".
    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: { SidebarSelection(storageKey: selectionRaw) ?? .date },
            set: { selectionRaw = ($0 ?? .date).storageKey }
        )
    }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Each feed view's own UI state (collapsed groups/months, expanded
    /// sources, selected link), kept here — keyed by sidebar selection — so
    /// it survives switching to another sidebar item and back.
    @State private var feedStates: [String: MacFeedViewState] = [:]
    @State private var scrollStore = ScrollOffsetStore()
    private func feedState(_ key: String, initialExpandedSources: Set<String> = []) -> Binding<MacFeedViewState> {
        Binding(
            get: { feedStates[key] ?? MacFeedViewState(expandedSources: initialExpandedSources) },
            set: { feedStates[key] = $0 }
        )
    }

    private var selectedTheme: AppTheme { AppTheme(rawValue: themeRaw) ?? .scand }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .auto }
    private var theme: AppTheme {
        AppTheme.resolved(selected: selectedTheme, appearance: appearance, systemColorScheme: systemAppearance.colorScheme)
    }
    /// A click on one of the sidebar's quick-switch dots — same effect as
    /// picking that variant in Settings' theme grid (`MacSettingsView`). Reads
    /// the system appearance from `systemAppearance`, not
    /// `@Environment(\.colorScheme)`, for the reason given on that property.
    private func pickTheme(_ t: AppTheme) {
        themeRaw = t.rawValue
        appearanceRaw = t.appearanceAfterPicking(
            current: appearance, systemColorScheme: systemAppearance.colorScheme
        ).rawValue
    }
    private var appFont: AppFont { AppFont(rawValue: fontRaw) ?? .rounded }
    private var layout: LinkLayout { LinkLayout(rawValue: layoutRaw) ?? .card }
    /// `MacFeedList`'s toolbar picker needs to change the layout, not just
    /// read it — a plain `LinkLayout` value can't do that, so this wraps
    /// `layoutRaw` (the actual `@AppStorage` source of truth) as a
    /// `Binding<LinkLayout>` instead.
    private var layoutBinding: Binding<LinkLayout> {
        Binding(get: { layout }, set: { layoutRaw = $0.rawValue })
    }

    /// Same resolution as `RootView.effectiveBackground` — see there for why
    /// Tokyo and the "Fond noir" toggle are special-cased.
    private var effectiveBackground: Color {
        if blackSoirBackground && theme.isSoir { return Color(hex: "#000000") }
        if theme == .tokyo { return Color(hex: "#FFFFFF") }
        // Copenhague clair: the list and the sidebar swapped backgrounds —
        // the list takes the light gray macOS's own sidebar material
        // normally shows (see `sidebarBackground` for the other half).
        if theme == .scand { return Color(hex: "#F2F2F2") }
        return theme.background
    }

    /// Sidebar backdrop — nil (the system's own sidebar material) except
    /// Copenhague clair, which swapped it with the list: the sidebar takes
    /// the theme's own beige (see `effectiveBackground` for the other half).
    private var sidebarBackground: Color? {
        theme == .scand ? theme.background : nil
    }

    /// Matches exactly the themes where `theme.title` is white/near-white
    /// (see `AppTheme.title`) — every nuit variant, plus Cap Canaveral
    /// clair, whose toolbar sits on a dark-blue background despite being
    /// the "light" variant. Forcing the window's own appearance to follow
    /// is the only way to recolor macOS's native title-bar/toolbar text:
    /// SwiftUI exposes no direct modifier for it (a hand-drawn `Text` we
    /// tried instead just duplicated the title as its own stray pill in the
    /// middle of the toolbar). A dark `NSWindow` appearance draws its
    /// system-provided title in light text on its own, which is what
    /// actually recolors it here.
    private var windowAppearanceIsDark: Bool {
        theme.isSoir || theme == .astronaute
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebarView(
                selection: selection, allItems: allItems, theme: theme,
                backgroundColor: sidebarBackground, onPickTheme: pickTheme
            )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView
        }
        // No custom sidebar-toggle button: `NavigationSplitView` already
        // provides one bound to `columnVisibility`, and places it per the
        // system convention — inside the sidebar itself while it's showing,
        // in the window toolbar once it's hidden. A hand-built button here
        // used to just duplicate it.
        .tint(theme.accent)
        .preferredColorScheme(windowAppearanceIsDark ? .dark : .light)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection.wrappedValue {
        case .date:
            MacFeedList(
                mode: .chrono, title: FeedMode.chrono.label, allItems: allItems,
                theme: theme, appFont: appFont, layout: layoutBinding,
                effectiveBackground: effectiveBackground, state: feedState("date"),
                scrollStore: scrollStore, scrollKey: "date"
            )
        case .read:
            MacFeedList(
                mode: .read, title: FeedMode.read.label, allItems: allItems,
                theme: theme, appFont: appFont, layout: layoutBinding,
                effectiveBackground: effectiveBackground, state: feedState("read"),
                scrollStore: scrollStore, scrollKey: "read"
            )
        case .source(let host):
            let sourceItems = allItems.filter { $0.host == host }
            MacFeedList(
                mode: .source, title: LinkItem.displaySourceName(forHost: host, in: sourceItems),
                allItems: sourceItems,
                theme: theme, appFont: appFont, layout: layoutBinding,
                effectiveBackground: effectiveBackground,
                state: feedState("source:\(host)", initialExpandedSources: [host]),
                scrollStore: scrollStore, scrollKey: "source:\(host)",
                isSingleSourceDetail: true
            )
        case .ranking:
            MacSourceRankingView(
                sourceRanks: sourceRanks, allItems: allItems, theme: theme, appFont: appFont,
                effectiveBackground: effectiveBackground
            )
        case nil:
            QuietEmptyStateView(
                theme: theme, appFont: appFont, icon: "sidebar.leading",
                title: "Aucune sélection",
                text: "Choisissez Date, Lus ou une source dans la barre latérale."
            )
            .background(effectiveBackground)
        }
    }
}
