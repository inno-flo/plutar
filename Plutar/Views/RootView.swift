import SwiftUI
import SwiftData
import UIKit

/// Selection value for the floating bottom `TabView`. Mirrors `FeedMode`
/// plus a fourth "Affichage" case that isn't a real destination — selecting
/// it just presents the settings sheet and bounces the selection back (see
/// the `onChange(of: selectedTab)` handler in `RootView.body`).
private enum RootTab: Hashable {
    case feed(FeedMode), settings
}

private struct DeletedSnapshot {
    let title: String
    let urlString: String
    let host: String
    let initial: String
    let colorHex: String
    let dateAdded: Date
    let sourceApp: String
    let excerpt: String
    /// Restored along with the rest — without it, undoing a delete in Lus
    /// brought the link back as unread, i.e. into Date rather than the view
    /// the user was actually looking at.
    let isRead: Bool
    /// Without these two, undoing the delete of a real shared link reset it
    /// to pre-enrichment state — no thumbnail, and queued to be re-fetched
    /// as if it were brand new.
    let thumbnailFileName: String?
    let metadataFetched: Bool
    let excerptFetchAttempted: Bool
    let isPinned: Bool
    /// Same for the fetched site name — without these, an undone delete
    /// showed the bare host again and queued the name to be re-fetched.
    let sourceName: String?
    let sourceNameFetchAttempted: Bool

    init(_ item: LinkItem) {
        title = item.title; urlString = item.urlString; host = item.host
        initial = item.initial; colorHex = item.colorHex; dateAdded = item.dateAdded
        sourceApp = item.sourceApp; excerpt = item.excerpt
        isRead = item.isRead
        thumbnailFileName = item.thumbnailFileName; metadataFetched = item.metadataFetched
        excerptFetchAttempted = item.excerptFetchAttempted
        isPinned = item.isPinned
        sourceName = item.sourceName; sourceNameFetchAttempted = item.sourceNameFetchAttempted
    }

    func makeLinkItem() -> LinkItem {
        LinkItem(title: title, urlString: urlString, host: host, initial: initial,
                 colorHex: colorHex, dateAdded: dateAdded, sourceApp: sourceApp,
                 excerpt: excerpt, isRead: isRead,
                 thumbnailFileName: thumbnailFileName, metadataFetched: metadataFetched,
                 excerptFetchAttempted: excerptFetchAttempted, isPinned: isPinned,
                 sourceName: sourceName, sourceNameFetchAttempted: sourceNameFetchAttempted)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    /// The system's own current light/dark setting — used to resolve the
    /// "Automatique" Apparence option to an actual theme variant.
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \LinkItem.dateAdded, order: .reverse) private var allItems: [LinkItem]
    @Query(sort: \SourceRank.count, order: .reverse) private var sourceRanks: [SourceRank]

    @AppStorage(DisplaySettingsKey.theme) private var themeRaw = AppTheme.scand.rawValue
    @AppStorage(DisplaySettingsKey.appearance) private var appearanceRaw = AppAppearance.auto.rawValue
    @AppStorage(DisplaySettingsKey.font) private var fontRaw = AppFont.rounded.rawValue
    @AppStorage(DisplaySettingsKey.layout) private var layoutRaw = LinkLayout.rail.rawValue
    /// Forces every "soir" theme's view background to pure black instead of
    /// its own defined color.
    @AppStorage(DisplaySettingsKey.blackSoirBackground) private var blackSoirBackground = false
    @AppStorage(DisplaySettingsKey.shakeToChangeTheme) private var shakeToChangeTheme = true
    /// 0→180°, animated in one continuous motion while a shake-triggered
    /// theme change plays out — see `triggerShakeThemeFlip`. Every capsule
    /// affected (link cards, the counter badge, day/source pills) reads
    /// this same angle, so they all turn in lockstep.
    @State private var themeFlipAngle: Double = 0
    /// The theme as it was just before the shake, kept only for the
    /// duration of the flip — each capsule's `FlipCard` shows this on its
    /// first face and the live (already-switched) `theme` on its second.
    @State private var themeFlipOldTheme: AppTheme?
    /// Toggled inside the same `withAnimation` block as the theme switch —
    /// see `animatedBackground` and `triggerShakeThemeFlip`.
    @State private var themeFlipRevealsNewBackground = false

    @State private var mode: FeedMode = .chrono
    @State private var selectedTab: RootTab = .feed(.chrono)
    @State private var showSettings = false

    /// Every link deleted inside the current undo window, oldest first — a
    /// batch, not a single slot. It used to be one `DeletedSnapshot?`, so a
    /// second swipe within the undo window silently overwrote the first: the
    /// toast stayed up, implying both were recoverable, while "Annuler"
    /// only ever brought back the last one and the earlier link was gone
    /// for good (the delete is committed immediately, below).
    @State private var undoSnapshots: [DeletedSnapshot] = []
    @State private var undoTask: Task<Void, Never>?

    @State private var showClearReadConfirm = false
    @State private var showMarkAllReadConfirm = false
    /// Set instead of deleting immediately — same confirmation-gated
    /// pattern as macOS's `MacSourceRankingView.hostPendingDelete`.
    @State private var rankHostPendingDelete: String?
    /// Raised by `persist()` when a write to the store fails.
    @State private var saveFailed = false

    /// Hosts currently expanded in the Sources view — empty by default, so
    /// every source starts collapsed.
    @State private var expandedSources: Set<String> = []
    /// Lus only: same globe/calendar grouping toggle as `MacFeedList` — see
    /// there and `DisplaySettingsKey.readGroupedBySource`.
    @AppStorage(DisplaySettingsKey.readGroupedBySource) private var readGroupedBySource = false
    /// Lus only: which day/source group headers are collapsed — see
    /// `MacFeedList.collapsedReadGroups`. Not persisted (plain `@State`,
    /// like its Mac counterpart): a per-session view state, not a display
    /// preference.
    @State private var collapsedReadGroups: Set<String> = []
    /// Lus, day-grouped: calendar months ("yyyy-MM") collapsed through their
    /// separator's chevron. Not persisted, like `collapsedReadGroups`.
    @State private var collapsedMonths: Set<String> = []
    /// Each tab's last scroll offset, restored when switching back to it.
    @State private var scrollStore = ScrollOffsetStore()
    /// À lire (test): the same source/date grouping and
    /// collapse controls as Lus, kept separate from Lus' own so switching
    /// tabs doesn't carry one view's grouping into the other. Not persisted.
    @State private var chronoGroupedBySource = false
    @State private var collapsedChronoGroups: Set<String> = []

    /// Whether the current view shows Lus' grouping/collapse controls —
    /// Lus and À lire (iPhone and iPad), not Sources.
    private var hasGroupingControls: Bool {
        mode == .read || mode == .chrono
    }
    /// The current view's source/date grouping flag (Lus or À lire).
    private var groupedBySource: Binding<Bool> {
        mode == .read ? $readGroupedBySource : $chronoGroupedBySource
    }
    /// The current view's collapsed group ids (Lus or À lire).
    private var collapsedGroups: Binding<Set<String>> {
        mode == .read ? $collapsedReadGroups : $collapsedChronoGroups
    }
    private func isCollapsed(_ group: FeedGroup) -> Bool {
        hasGroupingControls && collapsedGroups.wrappedValue.contains(group.id)
    }

    /// Which icon the expand-all/collapse-all button shows. Deliberately a
    /// separate stored flag rather than a value derived from `groups` +
    /// `expandedSources`: it should flip only when the user taps that
    /// button, or when individually expanding/collapsing sources happens to
    /// land on "every source expanded" or "every source collapsed" — not on
    /// every unrelated change to `groups` (e.g. a source emptying out after
    /// its links are marked read).
    @State private var allSourcesExpandedIcon = false

    /// The theme family picked in the "Thème" grid, before the "Apparence"
    /// setting resolves it to an actual light-or-soir variant to display.
    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .scand
    }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .auto }

    /// The theme actually displayed: `selectedTheme`'s light or soir variant,
    /// picked according to `appearance` ("Automatique" follows the system's
    /// own active light/dark setting).
    private var theme: AppTheme {
        AppTheme.resolved(selected: selectedTheme, appearance: appearance, systemColorScheme: systemColorScheme)
    }
    private var appFont: AppFont { AppFont(rawValue: fontRaw) ?? .rounded }
    private var layout: LinkLayout { LinkLayout(rawValue: layoutRaw) ?? .rail }

    /// The view background actually drawn — pure black instead of the
    /// theme's own background when the "Fond noir pour les thèmes nuit"
    /// toggle is on and the current theme is a soir variant; pure white for
    /// Tokyo, across all three views (Date/Sources/Lus).
    ///
    /// Takes `theme` explicitly so `animatedBackground` below can compute
    /// both the pre- and post-shake colors to cross-fade between.
    private func effectiveBackground(for theme: AppTheme) -> Color {
        if blackSoirBackground && theme.isSoir { return Color(hex: "#000000") }
        // Tokyo clair: pure white everywhere except Lus, which gets a light
        // gray instead.
        if theme == .tokyo { return mode == .read ? Color(hex: "#E8E8E8") : Color(hex: "#FFFFFF") }
        return theme.background
    }

    /// The screen backdrop, cross-fading between the pre- and post-shake
    /// background color while `triggerShakeThemeFlip` plays out, instead of
    /// snapping straight to the new one. A plain `Color` change under
    /// `.background()`/here isn't itself interpolated by `withAnimation` —
    /// unlike the capsules' rotation (driven by `FlipCard`'s
    /// `animatableData`), a `.opacity()` fade between two solid layers is
    /// SwiftUI's standard way to animate between two arbitrary colors.
    private var animatedBackground: some View {
        themeCrossfade { effectiveBackground(for: $0) }
    }

    /// `content` drawn for the pre-shake theme, with the post-shake one
    /// fading in on top while `triggerShakeThemeFlip` plays out — shared by
    /// `animatedBackground` and the day/source pills (`fadingDayPill`/
    /// `fadingSourceChipLabel`).
    private func themeCrossfade<Content: View>(@ViewBuilder _ content: (AppTheme) -> Content) -> some View {
        ZStack {
            content(themeFlipOldTheme ?? theme)
            if themeFlipOldTheme != nil {
                content(theme)
                    .opacity(themeFlipRevealsNewBackground ? 1 : 0)
            }
        }
        // Explicit rather than relying on the ambient `withAnimation` in
        // `triggerShakeThemeFlip` to propagate down on its own — that left
        // this fade finishing at a different moment than the capsules'
        // rotation and the day/source pills' own fade, even though all
        // three read the same state changed in the same transaction.
        .animation(.easeInOut(duration: Self.themeFlipDuration), value: themeFlipRevealsNewBackground)
    }

    /// Shared by every part of a shake's theme change — the capsule
    /// rotation (`FlipCard`, driven by `themeFlipAngle`), the backdrop fade
    /// (`animatedBackground`) and the day/source pills' own fade
    /// (`fadingDayPill`/`fadingSourceChipLabel`) — so all three start and
    /// finish at the exact same instant instead of merely sharing a
    /// `withAnimation` block that each could still resolve on its own timing.
    private static let themeFlipDuration: Double = 0.6

    private var visibleItems: [LinkItem] {
        FeedGrouping.visibleItems(allItems, mode: mode)
    }

    /// Count shown in the header badge — the number of links in the current view
    /// (unread links for Date/Sources, read links for Lus), so it grows when a
    /// link is added and shrinks when one is marked read (leaving Date/Sources).
    private var currentCount: Int { visibleItems.count }

    /// The 15 most-shared sources — merges any rows CloudKit sync left
    /// sharing the same host (see `SourceRank`'s comment) instead of
    /// assuming `sourceRanks` is already collision-free, then keeps only
    /// the top 15 (already sorted descending by `aggregated`).
    private var rankedSources: [(host: String, count: Int)] {
        Array(SourceRank.aggregated(sourceRanks).prefix(15))
    }

    /// The link-count counters' background (the top badge and the
    /// Sources/Lus pastille alike), per theme — every theme has its own,
    /// so neither falls back to `chip` any more. Copenhague uses
    /// an ochre yellow (a darker variant for soir); Kamakura uses its own
    /// slate blue-gray (a darker variant for soir); Cap Canaveral uses plain
    /// white, Cap Canaveral soir a light gray. Tokyo's counter swapped hues
    /// with its pill (`chip`): red here (was black), a dark red in soir
    /// (was dark gray) — the pill itself now carries the black/gray side of
    /// the swap, see `AppTheme.chip`. Copenhague's and Tokyo's are exactly
    /// `AppTheme.dotColor`, which mirrors them.
    private func counterBackground(for theme: AppTheme) -> Color {
        switch theme {
        case .scand, .scandSoir, .tokyo, .tokyoSoir: return theme.dotColor
        case .blanc: return Color(hex: "#798891")
        case .blancSoir: return Color(hex: "#546067")
        case .astronaute: return .white
        case .astronauteSoir: return Color(hex: "#6D6D6D")
        }
    }

    /// Cap Canaveral's own "international orange" for counter text, paired
    /// with `counterBackground`'s white; Cap Canaveral soir uses
    /// `chipText` — the same combination the Sources pastille's own count
    /// badge already falls back to. Copenhague pairs its ochre counter with
    /// dark ink instead of the pastille's white (contrast audit: white on
    /// that ochre was ~2.2:1). Nil everywhere else, so callers fall back to
    /// their own default foreground.
    private func counterForegroundOverride(for theme: AppTheme) -> Color? {
        switch theme {
        case .astronaute: return theme.accent
        case .astronauteSoir: return theme.chipText
        case .scand: return theme.ink(1)
        // Kamakura soir: its counter's dark fallback text (`background`)
        // was ~2.7:1 on that gray; pale ink matches the light variant's
        // own pattern instead.
        case .blancSoir: return theme.ink(1)
        // Tokyo soir: same gray as the ranking rows' own count text.
        case .tokyoSoir: return theme.ink(0.5)
        default: return nil
        }
    }

    private var groups: [FeedGroup] {
        if mode == .chrono && hasGroupingControls && chronoGroupedBySource {
            return FeedGrouping.makeSourceGroups(visibleItems)
        }
        return FeedGrouping.groups(allItems, mode: mode, readGroupedBySource: readGroupedBySource)
    }

    /// Lus, day-grouped only: ids of the first day group in each calendar
    /// month — but only once links actually span more than one month, so a
    /// single month shows no separators. Empty in every other mode/grouping.
    private func monthSeparatorGroupIDs(in groups: [FeedGroup]) -> Set<String> {
        guard mode == .read, !readGroupedBySource else { return [] }
        return FeedGrouping.monthSeparatorGroupIDs(groups)
    }

    private func toggleSource(_ id: String) {
        // Read once, up front: `groups` is a computed property that eagerly
        // regroups and sorts every visible link, and reading it twice inline
        // below did all of that twice per tap. It depends on `mode` and the
        // items, never on `expandedSources`, so its value is the same either
        // side of the mutation — and computing it outside the transaction
        // keeps that work out of the animation.
        let currentGroups = groups
        withAnimation(.easeInOut(duration: 0.25)) {
            expandedSources.toggle(id)
            // Only the two "every source" extremes move the icon; anything
            // in between leaves it as it was.
            if !currentGroups.isEmpty && currentGroups.allSatisfy({ expandedSources.contains($0.id) }) {
                allSourcesExpandedIcon = true
            } else if expandedSources.isEmpty {
                allSourcesExpandedIcon = false
            }
        }
    }

    /// Lus and À lire: collapses/expands just this one group —
    /// same membership convention as `MacFeedList.collapsedReadGroups`
    /// (present = collapsed).
    private func toggleGroupCollapse(_ id: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            collapsedGroups.wrappedValue.toggle(id)
        }
    }

    private func toggleAllSources() {
        withAnimation(.easeInOut(duration: 0.25)) {
            allSourcesExpandedIcon.toggle()
            expandedSources = allSourcesExpandedIcon ? Set(groups.map(\.id)) : []
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(FeedMode.allCases, id: \.self) { m in
                Tab(m.label, systemImage: m.icon, value: RootTab.feed(m)) {
                    feedScreen
                }
            }
            // Not a real destination — see `RootTab.settings` and the
            // `onChange(of: selectedTab)` handler below.
            Tab("Affichage", systemImage: "gear", value: RootTab.settings) {
                settingsTabPlaceholder
            }
        }
        // `Tab` has no per-item `.tint()`, so the tab bar's own color comes
        // from whatever `.tint()` is active right here, at the TabView
        // itself — set to the day/source chip's color. Further down the
        // chain, `.tint(theme.accent)` resets the environment back to the
        // accent color for everything presented from this point on
        // (sheets, alerts), without affecting the tab bar chrome already
        // resolved above.
        .tint(theme.tabTint)
        // Native iOS 26 floating tab bar: not full width, and shrinks while
        // scrolling the feed then restores once scrolling stops. Same
        // floating bar on iPad as on iPhone — no sidebar: `sidebarAdaptable`
        // gave a system-drawn sidebar with no supported way to pin a plain
        // icon-only button to its bottom (only whole tabs can be pinned,
        // always with their label), so kept things simple instead.
        .tabBarMinimizeBehavior(.onScrollDown)
        .onShake {
            guard shakeToChangeTheme else { return }
            triggerShakeThemeFlip()
        }
        .onChange(of: selectedTab) { _, newValue in
            switch newValue {
            case .settings:
                showSettings = true
                // Reverting the selection in the same tick can make the tab
                // bar's highlight snap to the first tab instead of back to
                // the current one — defer it to the next run loop turn.
                Task { @MainActor in
                    selectedTab = .feed(mode)
                }
            case .feed(let newMode):
                mode = newMode
            }
        }
        .onChange(of: mode) { _, newMode in
            selectedTab = .feed(newMode)
        }
        .tint(theme.accent)
        // Native chrome (the floating tab bar, sheets, alerts) picks its own
        // label/material colors from light vs. dark mode. Forcing it to
        // match the theme's own darkness (rather than the system's) used to
        // be unconditional here, to keep e.g. a dark theme's unselected tab
        // icons/text legible against the floating tab bar's own background.
        // The "Apparence" setting now controls this explicitly: "Claire"/
        // "Sombre" force one or the other regardless of theme or system;
        // "Automatique" (nil) hands it back to iOS's own active system
        // appearance instead.
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                // The grid highlights whichever pill matches what's actually
                // on screen right now (`theme`, not the raw `selectedTheme`
                // stored on disk) — in "Automatique", that pill changes on
                // its own when the system's light/dark setting does, rather
                // than staying stuck on whichever pill was last tapped.
                // Tapping a specific light or soir pill is itself a manual
                // override, though: it takes priority over "Apparence" by
                // forcing it to match (Claire/Sombre) rather than leaving it
                // on Automatique.
                theme: Binding(
                    get: { theme },
                    set: { newTheme in
                        themeRaw = newTheme.rawValue
                        // Left on "Automatique" rather than forced to an
                        // explicit light/dark when it's already Automatique
                        // and the picked theme's own light/soir variant
                        // already matches the live system setting — e.g.
                        // system in Clair, Automatique selected, picking
                        // another *light* theme shouldn't silently switch
                        // Apparence to "Claire". Only an actually mismatched
                        // pick (or an already-explicit Apparence) still
                        // forces it.
                        appearanceRaw = newTheme.appearanceAfterPicking(
                            current: appearance, systemColorScheme: systemColorScheme
                        ).rawValue
                    }
                ),
                appearance: Binding(get: { appearance }, set: { appearanceRaw = $0.rawValue }),
                appFont: Binding(get: { appFont }, set: { fontRaw = $0.rawValue }),
                blackSoirBackground: $blackSoirBackground,
                shakeToChangeTheme: $shakeToChangeTheme,
                layout: Binding(get: { layout }, set: { layoutRaw = $0.rawValue }),
                onClearAll: { clearAll(); showSettings = false },
                onResetRanking: { resetSourceRanking(); showSettings = false },
                onClose: { showSettings = false },
                chipColor: theme.chip
            )
        }
        .alert(
            "Supprimer les liens lus",
            isPresented: $showClearReadConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { clearRead() }
        }
        .alert(
            "Marquer tous les liens comme lus",
            isPresented: $showMarkAllReadConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            // Every link currently shown (Date view: all unread links), in
            // one go.
            Button("Marquer comme lus") { markAsRead(visibleItems) }
        }
        // `.alert`, not `.confirmationDialog` — the latter can render as a
        // compact popover anchored near the triggering context menu instead
        // of centered, unlike every other confirmation in this file (all
        // `.alert`, all reliably centered regardless of what triggered them).
        .alert(
            "Supprimer \(rankHostPendingDelete.map { SourceRank.displayName(forHost: $0, in: allItems) } ?? "cette source") du classement",
            isPresented: Binding(
                get: { rankHostPendingDelete != nil },
                set: { if !$0 { rankHostPendingDelete = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                if let host = rankHostPendingDelete { deleteSourceRank(for: host) }
            }
        }
        .saveFailureAlert(isPresented: $saveFailed)
    }

    /// Stand-in shown under the "Affichage" tab. That tab is never really
    /// visited — selecting it opens the settings sheet and bounces the
    /// selection back on the next run loop turn — but TabView does switch to
    /// it for that one frame, so it needs to render *something* that doesn't
    /// read as a flash.
    ///
    /// It used to render `feedScreen`, which made TabView build and keep
    /// alive a fourth full NavigationStack + List of every link, identical to
    /// the other three and re-invalidated along with them: four times the
    /// row layout, the cell caches, and the `groups` recomputation, for a
    /// destination nobody ever looks at.
    ///
    /// Keeps the counter badge — the only thing sitting at the top of all
    /// three real screens — in exactly the spot and size `feedScreen` puts
    /// it, so the top of the display is pixel-identical across the bounce
    /// and there's nothing there to flash. The empty body below it is
    /// covered by the settings sheet rising over it.
    private var settingsTabPlaceholder: some View {
        animatedBackground
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) {
                floatingCounterBadge
            }
    }

    /// The actual feed screen — identical content shown under all three feed
    /// tabs; which links it shows is driven by the shared `mode` state, not
    /// by which tab is selected.
    private var feedScreen: some View {
        // Computed once per render and reused below — `groups` is a
        // non-memoized computed property (a full `FeedGrouping.makeGroups`
        // pass), and the month-separator check used to recompute it for
        // every single group inside the `ForEach`, on top of every
        // `groups.isEmpty` test below.
        let groups = self.groups
        let monthSeparatorIDs = monthSeparatorGroupIDs(in: groups)
        return NavigationStack {
            ZStack(alignment: .bottomLeading) {
                animatedBackground.ignoresSafeArea()

                List {
                    ForEach(groups) { group in
                        Section {
                            // The group chip isn't a real Section header below —
                            // List/UITableView pins plain-style Section headers to
                            // the top while scrolling, and swapping the pinned
                            // chip for the next one's caused the List's top
                            // scroll-edge glass effect to flash opaque for a
                            // frame in every view (Date's day pill, Sources'
                            // source chip + its mark-read button). It's placed
                            // as a normal row here instead so the whole chip —
                            // in Sources, button included — just scrolls by
                            // with everything else, nothing pinned to swap.
                            if monthSeparatorIDs.contains(group.id),
                               let date = FeedGrouping.dayKeyFormatter.date(from: group.id) {
                                monthSeparator(
                                    FeedGrouping.monthLabel(for: date),
                                    monthKey: FeedGrouping.monthKey(fromDayGroupID: group.id)
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            if !isInCollapsedMonth(group) {
                                groupHeader(group)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                            if !isInCollapsedMonth(group)
                                && (mode != .source || expandedSources.contains(group.id))
                                && !isCollapsed(group) {
                                ForEach(group.items) { item in
                                    linkRow(item)
                                }
                            }
                        }
                    }

                    // When Sources has no links left but the ranking still
                    // does, the empty-state block is placed as a normal row
                    // here — above the ranking section below — instead of
                    // as an overlay, so the two never sit on top of each
                    // other; it just scrolls with everything else.
                    if mode == .source && groups.isEmpty && !sourceRanks.isEmpty {
                        QuietEmptyStateView(
                            theme: theme,
                            appFont: appFont,
                            icon: "moon.stars",
                            title: "Aucun lien partagé",
                            text: "Partagez une page depuis Safari ou n'importe quelle app, puis choisissez Plutar dans la feuille de partage.",
                            fillHeight: false
                        )
                        .padding(.top, 40)
                        .padding(.bottom, 20)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    // Cumulative ranking, most-to-least important — a
                    // persistent tally (see `SourceRank`) that keeps
                    // growing regardless of links being deleted, so it
                    // survives clearing the feed.
                    if mode == .source && !sourceRanks.isEmpty {
                        Section {
                            ForEach(Array(rankedSources.enumerated()), id: \.element.host) { index, rank in
                                sourceRankRow(rank: index + 1, host: rank.host, count: rank.count)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                            }
                        } header: {
                            Text("Les 15 sources les plus partagées")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.ink(0.55))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets())
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                // + the first row's 5pt top inset = 22pt
                                // down to the first source name.
                                .padding(.bottom, 17)
                        }
                    }
                }
                .listStyle(.plain)
                // The plain list's default 44pt minimum row height was what
                // actually spaced out the ranking rows (text + their 5pt
                // insets is only ~32pt); lifting it lets those insets alone
                // set the gap. Link rows are taller than 44pt anyway.
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
                .rememberScrollOffset(in: scrollStore, key: "\(mode)-\(readGroupedBySource)-\(chronoGroupedBySource)")
                // There's no supported API to force CloudKit to pull sooner
                // — sync itself stays automatic/background, same as before.
                // What pull-to-refresh actually does here: re-runs the same
                // enrichment pass `PlutarApp` already does on launch/
                // foreground, so a link enriched or thumbnailed on the
                // *other* device doesn't have to wait for this one to
                // relaunch or background-and-foreground before catching up.
                .refreshable {
                    await LinkMetadataEnricher.enrichPendingLinks(in: modelContext)
                }
                // No `.animation(_:value: expandedSources)` here: the only
                // two places that mutate `expandedSources` (`toggleSource`
                // and `toggleAllSources`) already wrap it in `withAnimation`,
                // so this modifier animated the same mutation a second time
                // — two transactions racing on one batch update. Driving it
                // from the mutation side alone also covers the floating
                // expand/collapse button's own icon swap, which lives
                // outside this List and so was never covered here.
                .overlay(alignment: .center) {
                    // The Sources-with-ranking case is handled above as a
                    // row inside the List itself, not here — an overlay
                    // would sit on top of the ranking section instead of
                    // scrolling above it.
                    if groups.isEmpty && !(mode == .source && !sourceRanks.isEmpty) {
                        // Sources mirrors Date's empty state exactly (icon,
                        // title, subtitle) — only Lus differs.
                        QuietEmptyStateView(
                            theme: theme,
                            appFont: appFont,
                            icon: "moon.stars",
                            title: mode == .read ? "Aucun lien lu" : "Aucun lien partagé",
                            text: mode == .read
                                ? "Les liens ouverts ou marqués comme lus apparaîtront ici"
                                : "Partagez une page depuis Safari ou n'importe quelle app, puis choisissez Plutar dans la feuille de partage."
                        )
                    }
                }

                if !groups.isEmpty {
                    floatingButtons(groups)
                }

                undoToast
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            // No title bar in any view — the counter takes its place in all
            // three. A reserved safe-area inset (rather than a ZStack
            // overlay) so it never overlaps the list's own content — in
            // Sources, the first source's chip can carry its own mark-as-
            // read button right at the top, and the two were colliding when
            // the counter merely floated on top.
            .safeAreaInset(edge: .top, spacing: 0) {
                floatingCounterBadge
            }
        }
    }

    /// One link: its card (turning with the others on a shake), tap to
    /// open, context menu and swipe actions.
    private func linkRow(_ item: LinkItem) -> some View {
        FlipCard(angle: themeFlipAngle, axis: (x: 1, y: 0, z: 0)) { showsNewFace in
            LinkRowView(item: item, layout: layout, theme: flippedTheme(showsNewFace: showsNewFace), appFont: appFont)
        }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
            .contentShape(Rectangle())
            .onTapGesture { open(item) }
            .contextMenu {
                Button("Copier l'URL") {
                    UIPasteboard.general.string = item.urlString
                }
                Button {
                    togglePin(item)
                } label: {
                    Label(item.isPinned ? "Détacher le lien" : "Épingler le lien",
                          systemImage: item.isPinned ? "pin.slash" : "pin")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { requestDelete([item]) } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                .tint(theme.deleteSwipeTint)
            }
            .swipeActions(edge: .leading) {
                Button {
                    if mode == .read { markAsUnread(item) } else { markAsRead([item]) }
                } label: {
                    Label(mode == .read ? "Marquer non lu" : "Marquer lu", systemImage: "checkmark.circle.fill")
                }
                .tint(mode == .read ? theme.markUnreadSwipeTint : theme.markReadSwipeTint)
            }
            // Plain opacity — without it, a newly-inserted row
            // can pop in at full height as soon as List
            // measures it, instead of fading in like a removed
            // row fades out. A directional `.move` transition
            // was tried here but made the last row in a
            // source's list animate differently from the rest.
            .transition(.opacity)
    }

    /// The bottom-trailing floating buttons, stacked in the same spot in
    /// every view.
    private func floatingButtons(_ groups: [FeedGroup]) -> some View {
        VStack(spacing: 14) {
            switch mode {
            case .read:
                // Clear-read above, grouping/collapse control below —
                // same spot and stacking Sources uses for its own
                // toggle-all + mark-all-read pair.
                floatingButton(icon: "trash") { showClearReadConfirm = true }
                readGroupingControl(groups)
            case .source:
                // Toggle-all above, mark-all-read below — same spot the
                // Date mark-all-read button sits in.
                floatingButton(
                    icon: allSourcesExpandedIcon ? "inset.filled.topthird.middlethird.bottomthird.rectangle" : "text.square.filled",
                    flipped: !allSourcesExpandedIcon
                ) {
                    toggleAllSources()
                }
                floatingButton(icon: "checkmark.circle.fill") { showMarkAllReadConfirm = true }
            case .chrono:
                floatingButton(icon: "checkmark.circle.fill") { showMarkAllReadConfirm = true }
                // Test: Lus' grouping/collapse control, below
                // mark-all-read.
                if hasGroupingControls {
                    readGroupingControl(groups)
                }
            }
        }
        .padding(.trailing, 18)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    /// The link-count pill, floating on its own with no surrounding title
    /// bar, in the same top-trailing spot a header used to place it. Only
    /// `counterBadgeContent` — the actual 44×44 box, not this whole
    /// `Spacer()`-padded row — is wrapped in `FlipCard`: a `FlipCard`
    /// spinning/scaling the whole row used to visibly shift the badge
    /// sideways, because a rotation or `.scaleEffect` transforms a view
    /// around *its own* center, and this row's center sits out in the
    /// middle of the `Spacer()`, nowhere near where the badge actually is.
    private var floatingCounterBadge: some View {
        HStack(spacing: 14) {
            Spacer()
            // A fixed 44×44 slot — the same box `floatingButton` uses —
            // positioned by the same Spacer + trailing-padding pattern as
            // every other floating button below, so its center always lands
            // on their shared horizontal center. The actual badge is
            // centered on top of it via `.overlay`, which lets it grow
            // symmetrically outward from that fixed center as its digit
            // count changes, rather than shifting the center left as its
            // one free (left) edge moves.
            Color.clear
                .frame(width: 44, height: 44)
                .overlay {
                    FlipCard(angle: themeFlipAngle, axis: (x: 1, y: 0, z: 0)) { showsNewFace in
                        counterBadgeContent(theme: flippedTheme(showsNewFace: showsNewFace))
                    }
                }
        }
        .padding(.top, 14)
        .padding(.trailing, 18)
        .padding(.bottom, 10)
    }

    /// Takes `theme` explicitly (rather than reading the property directly)
    /// so the shake flip can render this badge's pre- and post-shake faces
    /// side by side while it turns — see `floatingCounterBadge`.
    private func counterBadgeContent(theme: AppTheme) -> some View {
        Text("\(currentCount)")
            .font(appFont.font(size: 20, weight: .bold))
            // minWidth used to be 40 — wide enough on its own to swallow the
            // width difference between 1 and 2 digits (both simply clamped
            // to the floor), so the badge looked the same size regardless
            // of digit count. Lowered so a single digit's natural width
            // dictates its own size and 2/3-digit counts visibly grow past
            // it instead.
            .frame(minWidth: 24, minHeight: 36)
            // `floatingCounterBadge` hosts this inside an `.overlay` on a
            // fixed 44×44 box, which proposes that same 44pt width back to
            // this `Text` — without `fixedSize()`, a 3-digit count (needing
            // more than 44pt with its padding/capsule) got squeezed into
            // that proposal and truncated to an ellipsis instead of
            // growing past it as the comment above assumes.
            .fixedSize()
            .padding(.horizontal, 8)
            // Copenhague: the counter badge alone swaps to an ochre yellow
            // in every view (a darker variant for soir), leaving the
            // day/source pill on its usual `chip`.
            .background(counterBackground(for: theme))
            .foregroundStyle(counterForegroundOverride(for: theme) ?? theme.chipText)
            .clipShape(Capsule())
    }

    /// Whether every currently visible group is collapsed — same shape as
    /// `MacFeedList.allReadGroupsCollapsed`, driving the collapse icon below.
    private func allReadGroupsCollapsed(in groups: [FeedGroup]) -> Bool {
        !groups.isEmpty && groups.allSatisfy { collapsedGroups.wrappedValue.contains($0.id) }
    }

    /// Lus only: the grouping toggle (globe/calendar) and collapse-all/
    /// expand-all toggle (inset.filled…rectangle/square.fill.text.grid.1x2,
    /// the latter mirrored), joined into one capsule —
    /// same two controls `MacFeedList`'s toolbar exposes as separate
    /// buttons, grouped here the way its 3-way presentation switcher joins
    /// icons into a single block instead of each floating on its own like
    /// the other circular buttons. Stacked vertically — this sits directly
    /// above the trash button in the same bottom-trailing corner, so a
    /// horizontal pill would be wider than that single circular button
    /// beneath it.
    private func readGroupingControl(_ groups: [FeedGroup]) -> some View {
        let allCollapsed = allReadGroupsCollapsed(in: groups)
        return VStack(spacing: 0) {
            groupingControlButton(icon: groupedBySource.wrappedValue ? "calendar" : "globe.fill") {
                // Collapsed-group ids belong to whichever grouping was
                // active when they were collapsed (day keys vs. hosts), so
                // they can't carry over as-is — but the all-or-nothing
                // "everything folded" state itself should: re-derived
                // against the new grouping's own ids instead of just
                // dropped. A partial (some-but-not-all) collapse has no
                // equivalent in the other grouping, so only the two
                // extremes survive the switch.
                groupedBySource.wrappedValue.toggle()
                collapsedGroups.wrappedValue = allCollapsed ? Set(self.groups.map(\.id)) : []
            }
            Divider().frame(width: 20).opacity(0.3)
            groupingControlButton(
                icon: allCollapsed ? "square.fill.text.grid.1x2" : "inset.filled.topthird.middlethird.bottomthird.rectangle",
                flipped: allCollapsed
            ) {
                collapsedGroups.wrappedValue = allCollapsed ? [] : Set(groups.map(\.id))
            }
        }
        .frame(width: 44)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    /// One half of `readGroupingControl` — same icon size/color as
    /// `floatingButton` (and thus the trash button above it), but without
    /// its own individual glass background (the capsule around both halves
    /// supplies that instead).
    private func groupingControlButton(icon: String, flipped: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .scaleEffect(x: flipped ? -1 : 1, y: 1)
                .foregroundStyle(theme.ink(1))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    /// Shared look for the bottom-corner circular action buttons (settings,
    /// clear-read, expand/collapse all) — same size, background material and
    /// icon treatment so they line up visually regardless of which corner
    /// they sit in.
    ///
    /// Uses the real Liquid Glass material (`glassEffect`) rather than a
    /// plain `Material` background, so it actually follows the system's
    /// Liquid Glass appearance setting (Settings → Display & Brightness).
    private func floatingButton(icon: String, flipped: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .scaleEffect(x: flipped ? -1 : 1, y: 1)
                .foregroundStyle(theme.ink(1))
        }
        // The fixed size belongs on the button itself, not just the icon
        // inside it — sizing only the inner Image left the outer shape
        // glassEffect/circle actually clips at the mercy of the label's own
        // reported size, which wasn't reliably a perfect square.
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    /// Lus, day-grouped only — the month name plus a 1pt rule beneath it,
    /// shown above the first day group of each calendar month once links
    /// span more than one (see `monthSeparatorGroupIDs`).
    private func monthSeparator(_ label: String, monthKey: String) -> some View {
        let isCollapsed = collapsedMonths.contains(monthKey)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    collapsedMonths.toggle(monthKey)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(label)
                    Spacer(minLength: 0)
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.6)
                }
                .font(appFont.font(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink(0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(theme.ink(0.15))
                .frame(height: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    /// Lus, day-grouped: whether `group` belongs to a month collapsed via its
    /// separator's chevron — its header and links are hidden then.
    private func isInCollapsedMonth(_ group: FeedGroup) -> Bool {
        mode == .read && !readGroupedBySource
            && collapsedMonths.contains(FeedGrouping.monthKey(fromDayGroupID: group.id))
    }

    /// Chip shown as each Section's header. In Sources it also acts as the
    /// collapse/expand toggle for that source and carries a link-count badge;
    /// in Date it's a plain, non-interactive day label.
    private func groupHeader(_ group: FeedGroup) -> some View {
        // Centered alignment keeps the mark-all-read icon on the same
        // vertical line as the count badge and chevron inside the chip.
        HStack(alignment: .center, spacing: 10) {
            // Date mirrors Sources: the day chip stays a plain non-interactive
            // label, with its own mark-as-read button trailing it — same
            // 44pt tap target and icon treatment as Sources' per-source button.
            // Lus instead reuses Sources' own tappable chip (count + chevron)
            // once collapse/expand exists there too — tapping it toggles just
            // this one group, and the trash button only makes sense (and
            // only shows) while a group is actually expanded.
            switch mode {
            case .source:
                Button {
                    toggleSource(group.id)
                } label: {
                    fadingSourceChipLabel(group, isExpanded: expandedSources.contains(group.id))
                }
                .buttonStyle(.plain)
            case .read, .chrono where hasGroupingControls:
                Button {
                    toggleGroupCollapse(group.id)
                } label: {
                    fadingSourceChipLabel(group, isExpanded: !isCollapsed(group))
                }
                .buttonStyle(.plain)
            case .chrono:
                fadingDayPill(group)
            }

            Spacer(minLength: 0)

            switch mode {
            // Only while expanded — marks every link from this source as
            // read, which empties it out of the (unread-only) Sources
            // view, so the source disappears from the list.
            case .source where expandedSources.contains(group.id):
                headerIconButton("checkmark.circle.fill") { markAsRead(group.items) }
            // Pinned links stay in À lire — this button only
            // touches the rest of the day's links.
            // Test: no per-day button while À lire has Lus' grouping
            // controls — only the floating mark-all-read one.
            case .chrono where !hasGroupingControls && !isCollapsed(group):
                headerIconButton("checkmark.circle.fill") { markAsRead(group.items.filter { !$0.isPinned }) }
            case .read where !isCollapsed(group):
                headerIconButton("trash.circle.fill") { requestDelete(group.items) }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        // The chip's own leading padding (14) plus its label's internal
        // padding (14) put the source name — or "Aujourd'hui" — 28pt from
        // the row edge, 4pt short of a link title's 32pt (14 listRowInset +
        // 18 LinkRowView padding) — nudged to match.
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
    }

    /// A group header's trailing action — same 44pt box as the floating
    /// buttons below, so the icon glyph lands on the same vertical line as
    /// "Tout marquer comme lu" and "Présentation liste/condensé".
    private func headerIconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.ink(0.55))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    /// Takes `theme` and `isExpanded` explicitly (rather than reading
    /// `theme`/`expandedSources` directly) so the shake transition can
    /// cross-fade this chip's pre- and post-shake colors — see
    /// `fadingSourceChipLabel` — and so Lus can reuse the same chip look for
    /// its own collapsed groups, keyed on `collapsedReadGroups` instead of
    /// `expandedSources`.
    private func sourceChipLabel(_ group: FeedGroup, theme: AppTheme, isExpanded: Bool) -> some View {
        HStack(spacing: 7) {
            Text(group.label)
                .font(appFont.font(size: 16.5, weight: .bold))
            // The count only shows while collapsed — once expanded, the
            // links themselves are right there below.
            if !isExpanded {
                Text("\(group.items.count)")
                    .font(appFont.font(size: 16.5, weight: .bold))
                    .foregroundStyle(counterForegroundOverride(for: theme) ?? theme.chipText)
                    .frame(minWidth: 17, minHeight: 17)
                    .padding(.horizontal, 4)
                    // Copenhague: same ochre yellow as the other link counters.
                    .background(counterBackground(for: theme))
                    .clipShape(Capsule())
            }
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .opacity(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(theme.chip)
        .foregroundStyle(theme.chipText)
        .clipShape(Capsule())
    }

    /// `sourceChipLabel` cross-fading between its pre- and post-shake
    /// colors during `triggerShakeThemeFlip` — the rotation effect used
    /// elsewhere (link cards, the counter badge) turned out not to read at
    /// all on this chip once it shared a stack with a live sibling button,
    /// even restructured to remove that sibling; a plain fade, the same
    /// technique `animatedBackground` uses for the screen backdrop, was
    /// dropped in instead rather than keep chasing the rotation.
    private func fadingSourceChipLabel(_ group: FeedGroup, isExpanded: Bool) -> some View {
        // Explicit, and pinned to the exact same duration as
        // `animatedBackground`'s — see `themeCrossfade`.
        themeCrossfade { sourceChipLabel(group, theme: $0, isExpanded: isExpanded) }
    }

    /// The day pill ("Aujourd'hui", "Hier", a date) shown in Date/Lus —
    /// takes `theme` explicitly for the same reason as `sourceChipLabel`.
    private func dayPill(_ group: FeedGroup, theme: AppTheme) -> some View {
        Text(group.label)
            .font(appFont.font(size: 16.5, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(theme.chip)
            .foregroundStyle(theme.chipText)
            .clipShape(Capsule())
    }

    /// `dayPill` cross-fading between its pre- and post-shake colors — see
    /// `fadingSourceChipLabel`.
    private func fadingDayPill(_ group: FeedGroup) -> some View {
        themeCrossfade { dayPill(group, theme: $0) }
    }

    /// A plain row — rank, name, count, no gauge/bar-chart background —
    /// identical in spirit to macOS's own `MacSourceRankingView.rankRow`.
    private func sourceRankRow(rank: Int, host: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                // Black in clair themes (Cap Canaveral clair: the source
                // names' own `title` color instead); soir keeps its muted
                // ink, black would vanish on its dark background.
                .foregroundStyle(theme.isSoir ? theme.ink(0.4) : theme == .astronaute ? theme.title : .black)
                .frame(width: 22, alignment: .center)
            // The domain suffix (".com", ".fr", ".net"…) is dropped for the
            // ranking specifically — see `SourceRank.displayName`. Same as
            // macOS's `MacSourceRankingView`.
            Text(SourceRank.displayName(forHost: host, in: allItems))
                // Soir themes: match the rank/count's own muted ink tone
                // instead of the full-strength title color.
                .foregroundStyle(theme.isSoir ? theme.ink(0.5) : theme.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            // Centered in the same 44pt box `floatingCounterBadge` uses, so
            // the counts share the top counter's vertical axis.
            Text("\(count)")
                .foregroundStyle(theme.ink(0.5))
                .frame(minWidth: 44)
        }
        .font(.system(size: 16.5, weight: .bold, design: .rounded))
        // 14 listRowInset + 18 = 32pt, the same offset as a source chip's
        // name (18 header padding + 14 chip padding), so the rank digits
        // line up under the source names above. 14 + 4 trailing matches
        // the counter's 18pt trailing padding.
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .contextMenu {
            Button("Supprimer cette source…", role: .destructive) {
                rankHostPendingDelete = host
            }
        }
    }

    private var undoToast: some View {
        Group {
            if !undoSnapshots.isEmpty {
                undoToastContent
            }
        }
        // On the conditional content itself, this modifier would stop
        // watching the instant `undoSnapshots.isEmpty` flips true and the
        // view is removed from the tree — too late to animate its own exit.
        // Attached to the always-present `Group` wrapping it instead, so the
        // toast's remove transition is covered by an actual animation
        // rather than popping out instantly; `requestDelete`'s
        // auto-dismiss and `performUndo` no longer need their own
        // `withAnimation` for this.
        .animation(.easeInOut(duration: 0.3), value: undoSnapshots.isEmpty)
    }

    private var undoToastContent: some View {
        VStack {
                Spacer()
                HStack {
                    Text(undoSnapshots.count == 1
                         ? "Supprimé"
                         : "\(undoSnapshots.count) supprimés")
                        .font(.system(size: 13.5))
                        .tracking(0.4)
                        .lineLimit(1)
                    Spacer()
                    // Explicit style + contentShape + its own padding: the
                    // text alone (10.5pt, no frame) was a tiny, easy-to-miss
                    // tap target that made the button feel unresponsive.
                    Button(action: performUndo) {
                        Text("Annuler")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .buttonStyle(.plain)
                    .tint(theme.accentSoft)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .background(theme.ink(1))
                .foregroundStyle(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 96)
        }
        .zIndex(2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Actions

    /// Saves the context and reports a failure instead of dropping it — see
    /// `ModelContext.persist(_:)`.
    private func persist(_ operation: String = #function) {
        if !modelContext.persist(operation) { saveFailed = true }
    }

    private func open(_ item: LinkItem) {
        // A pinned link stays in À lire when opened — only an explicit
        // "Marquer comme lu" (swipe or context menu) or delete moves it on.
        if !item.isPinned {
            markAsRead([item])
        }
        if let url = URL(string: item.urlString) {
            openURL(url)
        }
    }

    private func togglePin(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isPinned.toggle()
            persist()
        }
    }

    /// One link (swipe, open), a whole day/source group, or every link
    /// currently shown ("Tout marquer comme lu").
    private func markAsRead(_ items: [LinkItem]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            for item in items { item.isRead = true }
            persist()
        }
    }

    private func markAsUnread(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isRead = false
            // A link moved back to unread re-enters Date/Sources, where the
            // excerpt is worth having again (Éditoriale) — give
            // LinkMetadataEnricher a fresh try rather than leaving it as it
            // was left back when it was last unread.
            item.excerptFetchAttempted = false
            persist()
        }
    }

    /// One swiped link, or every link in a Lus day group at once — all
    /// covered by the same undo toast (its count reflects the whole group).
    private func requestDelete(_ items: [LinkItem]) {
        for item in items {
            undoSnapshots.append(DeletedSnapshot(item))
            modelContext.delete(item)
        }
        persist()
        // Each delete restarts the window, so the user always gets the full
        // 1.5 seconds from their own last swipe rather than from the first
        // one in the batch.
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { discardUndoSnapshots() }
        }
    }

    /// Called once the undo window actually expires without `performUndo`
    /// — only then is a delete truly final, so only then is it safe to
    /// remove the thumbnail file each snapshot still points at (undoing
    /// before this restores the `LinkItem` pointing at that same file).
    private func discardUndoSnapshots() {
        for snapshot in undoSnapshots {
            SharedStore.deleteThumbnailFile(named: snapshot.thumbnailFileName)
        }
        undoSnapshots.removeAll()
    }

    /// Restores every link deleted in the current window, not just the last.
    private func performUndo() {
        guard !undoSnapshots.isEmpty else { return }
        for snapshot in undoSnapshots {
            modelContext.insert(snapshot.makeLinkItem())
        }
        persist()
        undoTask?.cancel()
        undoSnapshots.removeAll()
    }

    private func clearAll() {
        modelContext.deleteLinks(allItems)
        persist()
    }

    private func clearRead() {
        modelContext.deleteLinks(allItems.filter(\.isRead))
        persist()
    }

    /// Zeroes out the persistent source-importance tally — see `SourceRank`.
    private func resetSourceRanking() {
        for rank in sourceRanks { modelContext.delete(rank) }
        persist()
    }

    /// Removes every underlying `SourceRank` row for `host` — `rankedSources`
    /// already merges same-host rows for display (see `SourceRank.aggregated`),
    /// so there can be more than one to delete. Same as macOS's
    /// `MacSourceRankingView.deleteRank(for:)`.
    private func deleteSourceRank(for host: String) {
        for rank in sourceRanks where rank.host == host {
            modelContext.delete(rank)
        }
        persist()
    }

    /// Steps to the next theme, in `AppTheme.allCases`' declared order,
    /// within the currently displayed one's own light/soir family — a clear
    /// theme shaken from cycles to the next clear theme, a soir one to the
    /// next soir one, wrapping back to the first once the family is
    /// exhausted. Leaves `appearanceRaw` untouched so "Automatique" keeps
    /// following the system rather than getting silently pinned to whichever
    /// variant the new pick happens to be. Font, layout and every other
    /// Affichage setting are untouched too: only `themeRaw` changes.
    private func shakeToRandomizeTheme() {
        let family = AppTheme.allCases.filter { $0.isSoir == theme.isSoir }
        guard let currentIndex = family.firstIndex(of: theme) else { return }
        let next = family[(currentIndex + 1) % family.count]
        themeRaw = next.rawValue
    }

    /// The theme a capsule's `FlipCard` should show for one of its two
    /// faces during a shake flip: the frozen pre-shake theme on the first
    /// face, the live (already-switched) one on the second.
    private func flippedTheme(showsNewFace: Bool) -> AppTheme {
        showsNewFace ? theme : (themeFlipOldTheme ?? theme)
    }

    /// Snapshots the current theme, switches to the next one, then turns
    /// link cards and the counter badge from the old to the new in one
    /// continuous horizontal-axis rotation — the same technique
    /// `LinkRowView`'s title/image reveal uses — while `animatedBackground`
    /// and the day/source pills (`fadingDayPill`/`fadingSourceChipLabel`)
    /// cross-fade their colors in step instead.
    private func triggerShakeThemeFlip() {
        themeFlipOldTheme = theme
        themeFlipAngle = 0
        themeFlipRevealsNewBackground = false
        withAnimation(.easeInOut(duration: Self.themeFlipDuration)) {
            shakeToRandomizeTheme()
            themeFlipAngle = 180
            themeFlipRevealsNewBackground = true
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.themeFlipDuration))
            // Not resetting `themeFlipRevealsNewBackground` here — it was
            // the actual bug: flipping it back to false re-triggered the
            // `.animation(value:)`-driven fade on every fading view (an
            // unwanted extra 1→0 animation of a layer about to be removed
            // anyway), which is what made the old theme flash back
            // momentarily before the new one settled "for good". Clearing
            // `themeFlipOldTheme` alone removes the old/new overlay
            // structurally — instantly, no animation needed — and
            // `triggerShakeThemeFlip` already resets
            // `themeFlipRevealsNewBackground` to false itself before the
            // next flip starts.
            themeFlipOldTheme = nil
            // 180° and 0° render identically (see FlipCard) — resetting
            // silently here, rather than leaving it at 180, means the next
            // shake's animation always has the same 0→180 span to work with.
            themeFlipAngle = 0
        }
    }
}
