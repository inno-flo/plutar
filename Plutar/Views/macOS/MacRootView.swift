import SwiftUI
import SwiftData

/// macOS's window content: a HIG-style sidebar (`MacSidebarView`) driving a
/// detail column (`MacFeedList`), replacing the old top-strip `TabView`.
/// "Date" and "Lus" are plain sidebar rows; each source is its own row under
/// a disclosed "Sources" group, so picking one shows just that source's
/// links rather than a shared, expand-per-source "Sources" screen. Display
/// settings live in a real `Settings` scene (Cmd+,) — see `MacSettingsView`.
/// No shake-to-theme here either (`ShakeGesture`/`FlipCard` are UIKit-only
/// and stay out of this target's sources).
struct MacRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \LinkItem.dateAdded, order: .reverse) private var allItems: [LinkItem]

    @AppStorage(DisplaySettingsKey.theme) private var themeRaw = AppTheme.scand.rawValue
    @AppStorage(DisplaySettingsKey.appearance) private var appearanceRaw = AppAppearance.auto.rawValue
    @AppStorage(DisplaySettingsKey.font) private var fontRaw = AppFont.rounded.rawValue
    @AppStorage(DisplaySettingsKey.layout) private var layoutRaw = LinkLayout.rail.rawValue
    @AppStorage(DisplaySettingsKey.showThumbnails) private var showThumbnails = true
    @AppStorage(DisplaySettingsKey.blackSoirBackground) private var blackSoirBackground = false

    @State private var selection: SidebarSelection? = .date
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selectedTheme: AppTheme { AppTheme(rawValue: themeRaw) ?? .scand }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .auto }
    private var theme: AppTheme {
        AppTheme.resolved(selected: selectedTheme, appearance: appearance, systemColorScheme: systemColorScheme)
    }
    private var appFont: AppFont { AppFont(rawValue: fontRaw) ?? .rounded }
    private var layout: LinkLayout { LinkLayout(rawValue: layoutRaw) ?? .rail }
    /// `MacFeedList`'s toolbar picker needs to change the layout, not just
    /// read it — a plain `LinkLayout` value can't do that, so this wraps
    /// `layoutRaw` (the actual `@AppStorage` source of truth) as a
    /// `Binding<LinkLayout>` instead.
    private var layoutBinding: Binding<LinkLayout> {
        Binding(
            get: { layout },
            set: { layoutRaw = $0.rawValue }
        )
    }

    /// Same resolution as `RootView.effectiveBackground` — see there for why
    /// Tokyo and the "Fond noir" toggle are special-cased.
    private var effectiveBackground: Color {
        if blackSoirBackground && theme.isSoir { return Color(hex: "#000000") }
        if theme == .tokyo { return Color(hex: "#FFFFFF") }
        return theme.background
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebarView(selection: $selection, allItems: allItems)
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
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .date:
            MacFeedList(
                mode: .chrono, title: FeedMode.chrono.label, allItems: allItems,
                theme: theme, appFont: appFont, layout: layoutBinding,
                showThumbnails: showThumbnails, effectiveBackground: effectiveBackground
            )
        case .read:
            MacFeedList(
                mode: .read, title: FeedMode.read.label, allItems: allItems,
                theme: theme, appFont: appFont, layout: layoutBinding,
                showThumbnails: showThumbnails, effectiveBackground: effectiveBackground
            )
        case .source(let host):
            MacFeedList(
                mode: .source, title: host,
                allItems: allItems.filter { $0.host == host },
                theme: theme, appFont: appFont, layout: layoutBinding,
                showThumbnails: showThumbnails, effectiveBackground: effectiveBackground,
                isSingleSourceDetail: true, initialExpandedSources: [host]
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
