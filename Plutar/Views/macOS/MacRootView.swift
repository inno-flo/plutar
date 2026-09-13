import SwiftUI
import SwiftData

/// macOS's window content: the three iOS feeds (Date/Sources/Lus) as a
/// native top-strip `TabView`, per the HIG tab-views pattern — unlike iOS's
/// floating bottom `TabView` with a decoy 4th "Affichage" tab, macOS has no
/// 4th tab; display settings live in a real `Settings` scene (Cmd+,) — see
/// `MacSettingsView`. No shake-to-theme here either (`ShakeGesture`/
/// `FlipCard` are UIKit-only and stay out of this target's sources).
struct MacRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \LinkItem.dateAdded, order: .reverse) private var allItems: [LinkItem]
    @Query(sort: \SourceRank.count, order: .reverse) private var sourceRanks: [SourceRank]

    @AppStorage(DisplaySettingsKey.theme) private var themeRaw = AppTheme.scand.rawValue
    @AppStorage(DisplaySettingsKey.appearance) private var appearanceRaw = AppAppearance.auto.rawValue
    @AppStorage(DisplaySettingsKey.font) private var fontRaw = AppFont.rounded.rawValue
    @AppStorage(DisplaySettingsKey.layout) private var layoutRaw = LinkLayout.rail.rawValue
    @AppStorage(DisplaySettingsKey.showThumbnails) private var showThumbnails = true
    @AppStorage(DisplaySettingsKey.blackSoirBackground) private var blackSoirBackground = false

    private var selectedTheme: AppTheme { AppTheme(rawValue: themeRaw) ?? .scand }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .auto }
    private var theme: AppTheme {
        AppTheme.resolved(selected: selectedTheme, appearance: appearance, systemColorScheme: systemColorScheme)
    }
    private var appFont: AppFont { AppFont(rawValue: fontRaw) ?? .rounded }
    private var layout: LinkLayout { LinkLayout(rawValue: layoutRaw) ?? .rail }

    /// Same resolution as `RootView.effectiveBackground` — see there for why
    /// Tokyo and the "Fond noir" toggle are special-cased.
    private var effectiveBackground: Color {
        if blackSoirBackground && theme.isSoir { return Color(hex: "#000000") }
        if theme == .tokyo { return Color(hex: "#FFFFFF") }
        return theme.background
    }

    var body: some View {
        // Each `Tab` owns its own `MacFeedList`, which builds its own
        // `FeedGrouping.makeGroups` pass for its `mode` — unlike iOS, which
        // shares one `feedScreen` across tabs by switching a single `mode`
        // state. That's inherent to macOS's persistent tab strip (all three
        // tabs are real, addressable destinations here, not a shared
        // screen + a decoy 4th tab), and the value-based `Tab` API only
        // builds a tab's content when it's actually selected — so the
        // per-tab grouping cost is paid at most once per visited tab, not
        // for all three on every render. `MacFeedList.body` additionally
        // memoizes its own `groups`/`rankedSources` per render (see there)
        // so a visited tab's own cost stays a single pass too.
        TabView {
            ForEach(FeedMode.allCases, id: \.self) { mode in
                Tab(mode.label, systemImage: mode.icon) {
                    MacFeedList(
                        mode: mode,
                        allItems: allItems,
                        sourceRanks: sourceRanks,
                        theme: theme,
                        appFont: appFont,
                        layout: layout,
                        showThumbnails: showThumbnails,
                        effectiveBackground: effectiveBackground
                    )
                }
            }
        }
        .tint(theme.accent)
    }
}
