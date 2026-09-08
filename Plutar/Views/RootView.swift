import SwiftUI
import SwiftData

private enum FeedMode: String, CaseIterable {
    case chrono, source, read

    var label: String {
        switch self {
        case .chrono: return "Date"
        case .source: return "Sources"
        case .read: return "Lus"
        }
    }

    var icon: String {
        switch self {
        case .chrono: return "calendar"
        case .source: return "globe"
        case .read: return "checkmark.circle"
        }
    }
}

/// Selection value for the floating bottom `TabView`. Mirrors `FeedMode`
/// plus a fourth "Affichage" case that isn't a real destination — selecting
/// it just presents the settings sheet and bounces the selection back (see
/// the `onChange(of: selectedTab)` handler in `RootView.body`).
private enum RootTab: Hashable {
    case chrono, source, read, settings

    init(_ mode: FeedMode) {
        switch mode {
        case .chrono: self = .chrono
        case .source: self = .source
        case .read: self = .read
        }
    }

    var feedMode: FeedMode? {
        switch self {
        case .chrono: return .chrono
        case .source: return .source
        case .read: return .read
        case .settings: return nil
        }
    }
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
    let hasThumbnail: Bool
    /// Restored along with the rest — without it, undoing a delete in Lus
    /// brought the link back as unread, i.e. into Date rather than the view
    /// the user was actually looking at.
    let isRead: Bool

    init(_ item: LinkItem) {
        title = item.title; urlString = item.urlString; host = item.host
        initial = item.initial; colorHex = item.colorHex; dateAdded = item.dateAdded
        sourceApp = item.sourceApp; excerpt = item.excerpt; hasThumbnail = item.hasThumbnail
        isRead = item.isRead
    }

    func makeLinkItem() -> LinkItem {
        LinkItem(title: title, urlString: urlString, host: host, initial: initial,
                 colorHex: colorHex, dateAdded: dateAdded, sourceApp: sourceApp,
                 excerpt: excerpt, hasThumbnail: hasThumbnail, isRead: isRead)
    }
}

/// One section of the feed — a day in Date/Lus, a host in Sources.
///
/// `id` is deliberately *not* `label`. Two days a year apart both render as
/// "3 mars", so keying `ForEach` on the displayed text made them collide on
/// one identifier, which SwiftUI resolves by dropping or mis-animating rows.
/// In Sources the two are the same string (the host), which is why the
/// expansion state in `expandedSources` round-trips unchanged.
private struct FeedGroup: Identifiable {
    let id: String
    let label: String
    let items: [LinkItem]
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    /// The system's own current light/dark setting — used to resolve the
    /// "Automatique" Apparence option to an actual theme variant.
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \LinkItem.dateAdded, order: .reverse) private var allItems: [LinkItem]
    @Query(sort: \SourceRank.count, order: .reverse) private var sourceRanks: [SourceRank]

    @AppStorage("plutar.theme") private var themeRaw = AppTheme.scand.rawValue
    @AppStorage("plutar.appearance") private var appearanceRaw = AppAppearance.auto.rawValue
    @AppStorage("plutar.font") private var fontRaw = AppFont.rounded.rawValue
    @AppStorage("plutar.layout") private var layoutRaw = LinkLayout.rail.rawValue
    @AppStorage("plutar.showThumbnails") private var showThumbnails = true
    @AppStorage("plutar.showFavicons") private var showFavicons = true
    /// Forces every "soir" theme's view background to pure black instead of
    /// its own defined color.
    @AppStorage("plutar.blackSoirBackground") private var blackSoirBackground = false

    @State private var mode: FeedMode = .chrono
    @State private var selectedTab: RootTab = .chrono
    @State private var showSettings = false
    @State private var pendingShare: SeedData.PoolEntry?

    /// Every link deleted inside the current undo window, oldest first — a
    /// batch, not a single slot. It used to be one `DeletedSnapshot?`, so a
    /// second swipe within the 5 seconds silently overwrote the first: the
    /// toast stayed up, implying both were recoverable, while "Annuler"
    /// only ever brought back the last one and the earlier link was gone
    /// for good (the delete is committed immediately, below).
    @State private var undoSnapshots: [DeletedSnapshot] = []
    @State private var undoTask: Task<Void, Never>?

    @State private var showClearReadConfirm = false
    @State private var showMarkAllReadConfirm = false
    @State private var showResetRankingConfirm = false
    /// Raised by `persist()` when a write to the store fails.
    @State private var saveFailed = false

    /// Hosts currently expanded in the Sources view — empty by default, so
    /// every source starts collapsed.
    @State private var expandedSources: Set<String> = []

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
    private var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .auto }
    }

    /// The theme actually displayed: `selectedTheme`'s light or soir variant,
    /// picked according to `appearance` ("Automatique" follows the system's
    /// own active light/dark setting).
    private var theme: AppTheme {
        switch appearance {
        case .light: return selectedTheme.lightVariant
        case .dark: return selectedTheme.soirVariant
        case .auto: return systemColorScheme == .dark ? selectedTheme.soirVariant : selectedTheme.lightVariant
        }
    }
    private var appFont: AppFont { AppFont(rawValue: fontRaw) ?? .rounded }
    private var layout: LinkLayout {
        get { LinkLayout(rawValue: layoutRaw) ?? .rail }
    }

    /// The view background actually drawn — pure black instead of the
    /// theme's own background when the "Fond noir pour les thèmes nuit"
    /// toggle is on and the current theme is a soir variant; pure white for
    /// Tokyo, across all three views (Date/Sources/Lus).
    private var effectiveBackground: Color {
        if blackSoirBackground && theme.isSoir { return Color(hex: "#000000") }
        if theme == .tokyo { return Color(hex: "#FFFFFF") }
        return theme.background
    }

    private var visibleItems: [LinkItem] {
        mode == .read ? allItems.filter(\.isRead) : allItems.filter { !$0.isRead }
    }

    /// Count shown in the header badge — the number of links in the current view
    /// (unread links for Date/Sources, read links for Lus), so it grows when a
    /// link is added and shrinks when one is marked read (leaving Date/Sources).
    private var currentCount: Int { visibleItems.count }

    /// Highest tally in the source ranking — the reference each row's width
    /// is scaled against (see `sourceRankRow`).
    private var maxSourceRankCount: Int { sourceRanks.map(\.count).max() ?? 1 }

    private var groups: [FeedGroup] {
        let list = visibleItems
        switch mode {
        case .chrono, .read:
            let calendar = Calendar.current
            var order: [Date] = []
            var buckets: [Date: [LinkItem]] = [:]
            for item in list {
                let day = calendar.startOfDay(for: item.dateAdded)
                if buckets[day] == nil { buckets[day] = []; order.append(day) }
                buckets[day]!.append(item)
            }
            return order.map { day in
                FeedGroup(id: Self.dayKeyFormatter.string(from: day),
                          label: dayLabel(day),
                          items: buckets[day]!)
            }
        case .source:
            let byHost = Dictionary(grouping: list, by: \.host)
            let hosts = byHost.keys.sorted { a, b in
                let ca = byHost[a]?.count ?? 0, cb = byHost[b]?.count ?? 0
                return ca != cb ? ca > cb : a < b
            }
            return hosts.map { host in
                FeedGroup(id: host, label: host, items: byHost[host] ?? [])
            }
        }
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
            if expandedSources.contains(id) {
                expandedSources.remove(id)
            } else {
                expandedSources.insert(id)
            }
            // Only the two "every source" extremes move the icon; anything
            // in between leaves it as it was.
            if !currentGroups.isEmpty && currentGroups.allSatisfy({ expandedSources.contains($0.id) }) {
                allSourcesExpandedIcon = true
            } else if expandedSources.isEmpty {
                allSourcesExpandedIcon = false
            }
        }
    }

    private func toggleAllSources() {
        withAnimation(.easeInOut(duration: 0.25)) {
            allSourcesExpandedIcon.toggle()
            expandedSources = allSourcesExpandedIcon ? Set(groups.map(\.id)) : []
        }
    }

    /// Built once instead of per call: `groups` is a computed property with
    /// no memoization, re-evaluated several times per `feedScreen` body, and
    /// it labels every day bucket — so a per-call `DateFormatter()` (one of
    /// the most expensive objects in Foundation to construct) was being
    /// allocated hundreds of times per render pass. Safe to share because
    /// `RootView`, like every `View`, is `@MainActor`-isolated.
    /// Collision-free identity for a day bucket — unlike the displayed
    /// label, which repeats from one year to the next. See `FeedGroup`.
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM"
        return f
    }()

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        // Only the first letter gets a capital, French-style — "3 mars",
        // not "3 Mars" (`.capitalized` would capitalize every word).
        let raw = Self.dayFormatter.string(from: day)
        let formatted = raw.prefix(1).uppercased() + raw.dropFirst()
        // French uses the ordinal "1er" for the first of the month, not "1"
        // — e.g. "1er avril", not "1 avril". Applied after the capitalization
        // above so it stays "1er", not "1Er".
        let label = calendar.component(.day, from: day) == 1
            ? formatted.replacingOccurrences(of: "1 ", with: "1er ")
            : formatted
        // Links accumulate for years in a read-later app, so a bare "3 mars"
        // would read identically for two different years. Shown only when it
        // isn't the current year, so the common case stays short.
        let year = calendar.component(.year, from: day)
        guard year != calendar.component(.year, from: Date()) else { return label }
        return "\(label) \(year)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(FeedMode.allCases, id: \.self) { m in
                Tab(m.label, systemImage: m.icon, value: RootTab(m)) {
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
        .tint(theme.chip)
        // Native iOS 26 floating tab bar: not full width, and shrinks while
        // scrolling the feed then restores once scrolling stops.
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .settings {
                showSettings = true
                // Reverting the selection in the same tick can make the tab
                // bar's highlight snap to the first tab instead of back to
                // the current one — defer it to the next run loop turn.
                Task { @MainActor in
                    selectedTab = RootTab(mode)
                }
            } else if let newMode = newValue.feedMode {
                mode = newMode
            }
        }
        .onChange(of: mode) { _, newMode in
            selectedTab = RootTab(newMode)
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
                // The grid picks the theme family, but tapping a specific
                // light or soir pill is itself a manual override: it takes
                // priority over "Apparence" by forcing it to match
                // (Claire/Sombre) rather than leaving it on Automatique.
                theme: Binding(
                    get: { selectedTheme },
                    set: {
                        themeRaw = $0.rawValue
                        appearanceRaw = ($0.isSoir ? AppAppearance.dark : .light).rawValue
                    }
                ),
                appearance: Binding(get: { appearance }, set: { appearanceRaw = $0.rawValue }),
                appFont: Binding(get: { appFont }, set: { fontRaw = $0.rawValue }),
                showThumbnails: $showThumbnails,
                showFavicons: $showFavicons,
                blackSoirBackground: $blackSoirBackground,
                layout: Binding(get: { layout }, set: { layoutRaw = $0.rawValue }),
                onClearAll: { clearAll(); showSettings = false },
                onRegenerate: { regenerateLinks(); showSettings = false },
                onClose: { showSettings = false },
                chipColor: theme.chip
            )
        }
        .sheet(item: $pendingShare) { entry in
            ShareSimulationSheet(
                entry: entry,
                onOther: { pendingShare = SeedData.pool.filter { $0.id != entry.id }.randomElement() ?? entry },
                onSave: { save(entry); pendingShare = nil },
                onCancel: { pendingShare = nil }
            )
            .presentationDetents([.height(220)])
        }
        .alert(
            "Supprimer les liens lus",
            isPresented: $showClearReadConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { clearRead() }
        }
        .alert(
            "Marquer les liens comme lus",
            isPresented: $showMarkAllReadConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Marquer comme lus") { markAllAsRead() }
        }
        .alert(
            "Réinitialiser le classement des sources",
            isPresented: $showResetRankingConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Réinitialiser", role: .destructive) { resetSourceRanking() }
        }
        .alert("Enregistrement impossible", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La dernière modification n'a pas pu être enregistrée et sera perdue à la fermeture de l'app.")
        }
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
        effectiveBackground
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) {
                floatingCounterBadge
            }
    }

    /// The actual feed screen — identical content shown under all three feed
    /// tabs; which links it shows is driven by the shared `mode` state, not
    /// by which tab is selected.
    private var feedScreen: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                effectiveBackground.ignoresSafeArea()

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
                            groupHeader(group)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            if mode != .source || expandedSources.contains(group.id) {
                                ForEach(group.items) { item in
                                    LinkRowView(item: item, layout: layout, theme: theme, appFont: appFont, showThumbnails: showThumbnails, showFavicons: showFavicons)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                                        .contentShape(Rectangle())
                                        .onTapGesture { open(item) }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { requestDelete(item) } label: {
                                                Label("Supprimer", systemImage: "trash")
                                            }
                                            .tint(theme.deleteSwipeTint)
                                        }
                                        .swipeActions(edge: .leading) {
                                            if mode == .read {
                                                Button {
                                                    markAsUnread(item)
                                                } label: {
                                                    Label("Non lu", systemImage: "checkmark.circle")
                                                }
                                                .tint(theme.markUnreadSwipeTint)
                                            } else {
                                                Button {
                                                    markAsRead(item)
                                                } label: {
                                                    Label("Lu", systemImage: "checkmark.circle.fill")
                                                }
                                                .tint(theme.markReadSwipeTint)
                                            }
                                        }
                                        // Plain opacity — without it, a newly-inserted row
                                        // can pop in at full height as soon as List
                                        // measures it, instead of fading in like a removed
                                        // row fades out. A directional `.move` transition
                                        // was tried here but made the last row in a
                                        // source's list animate differently from the rest.
                                        .transition(.opacity)
                                }
                            }
                        }
                    }

                    // Cumulative ranking, most-to-least important — a
                    // persistent tally (see `SourceRank`) that keeps
                    // growing regardless of links being deleted, so it
                    // survives clearing the feed.
                    if mode == .source && !sourceRanks.isEmpty {
                        Section {
                            ForEach(Array(sourceRanks.enumerated()), id: \.element.host) { index, rank in
                                sourceRankRow(rank: index + 1, entry: rank, maxCount: maxSourceRankCount)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                            }

                            Button(role: .destructive) {
                                showResetRankingConfirm = true
                            } label: {
                                Text("Réinitialiser le classement")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(1.2)
                                    .textCase(.uppercase)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 14)
                        } header: {
                            Text("Classement des sources")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.ink(0.55))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets())
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // No `.animation(_:value: expandedSources)` here: the only
                // two places that mutate `expandedSources` (`toggleSource`
                // and `toggleAllSources`) already wrap it in `withAnimation`,
                // so this modifier animated the same mutation a second time
                // — two transactions racing on one batch update. Driving it
                // from the mutation side alone also covers the floating
                // expand/collapse button's own icon swap, which lives
                // outside this List and so was never covered here.
                .overlay {
                    if groups.isEmpty {
                        // Sources mirrors Date's empty state exactly (icon,
                        // title, subtitle) — only Lus differs.
                        QuietEmptyStateView(
                            theme: theme,
                            appFont: appFont,
                            icon: "moon.stars",
                            title: mode == .read ? "Aucun lien lu" : "Aucun lien partagé",
                            text: mode == .read
                                ? "Les liens ouverts ou marqués comme lus apparaîtront ici"
                                : "Partagez une page depuis Safari ou n'importe quelle app, puis choisissez Plutar dans la feuille de partage.",
                            showsSimulateButton: mode != .read,
                            onSimulateShare: { pendingShare = SeedData.pool.randomElement() }
                        )
                    }
                }

                if mode == .read && !groups.isEmpty {
                    clearReadButton
                } else if mode == .source && !groups.isEmpty {
                    // Toggle-all above, mark-all-read below — same spot the
                    // Date mark-all-read button sits in.
                    VStack(spacing: 14) {
                        floatingButton(
                            icon: allSourcesExpandedIcon ? "inset.filled.topthird.middlethird.bottomthird.rectangle" : "text.square.filled",
                            flipped: !allSourcesExpandedIcon
                        ) {
                            toggleAllSources()
                        }
                        floatingButton(icon: "checkmark.circle.fill") {
                            showMarkAllReadConfirm = true
                        }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if mode == .chrono && !groups.isEmpty {
                    markAllReadButton
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

    /// The link-count pill, floating on its own with no surrounding title
    /// bar, in the same top-trailing spot a header used to place it.
    private var floatingCounterBadge: some View {
        HStack {
            Spacer()
            Text("\(currentCount)")
                .font(.system(size: 22, weight: .heavy))
                .frame(minWidth: 40, minHeight: 36)
                .padding(.horizontal, 8)
                .background(theme.chip)
                .foregroundStyle(theme.countForeground)
                .clipShape(Capsule())
        }
        .padding(.top, 14)
        .padding(.trailing, 18)
        .padding(.bottom, 10)
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
                .font(.system(size: 20, weight: .semibold))
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

    private var clearReadButton: some View {
        floatingButton(icon: "trash") { showClearReadConfirm = true }
            .padding(.trailing, 18)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var markAllReadButton: some View {
        floatingButton(icon: "checkmark.circle.fill") { showMarkAllReadConfirm = true }
            .padding(.trailing, 18)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    /// Chip shown as each Section's header. In Sources it also acts as the
    /// collapse/expand toggle for that source and carries a link-count badge;
    /// in Date/Lus it's a plain, non-interactive day label.
    @ViewBuilder
    private func groupHeader(_ group: FeedGroup) -> some View {
        if mode == .source {
            // Centered alignment keeps the mark-all-read icon on the same
            // vertical line as the count badge and chevron inside the chip.
            HStack(alignment: .center, spacing: 10) {
                Button {
                    toggleSource(group.id)
                } label: {
                    sourceChipLabel(group)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // Only while expanded — marks every link from this source as
                // read, which empties it out of the (unread-only) Sources
                // view, so the source disappears from the list.
                if expandedSources.contains(group.id) {
                    Button {
                        markSourceAsRead(group.items)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(theme.ink(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        } else {
            Text(group.label)
                .font(.system(size: 16.5, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(theme.chip)
                .foregroundStyle(theme.chipText)
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets())
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
        }
    }

    private func sourceChipLabel(_ group: FeedGroup) -> some View {
        HStack(spacing: 7) {
            Text(group.label)
                .font(.system(size: 16.5, weight: .bold))
            Text("\(group.items.count)")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(theme.chipText)
                .frame(minWidth: 17, minHeight: 17)
                .padding(.horizontal, 4)
                .background(theme.chipText.opacity(0.22))
                .clipShape(Capsule())
            Image(systemName: expandedSources.contains(group.id) ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .opacity(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(theme.chip)
        .foregroundStyle(theme.chipText)
        .clipShape(Capsule())
    }

    /// A row's width is proportional to its share of `maxCount` (the
    /// top-ranked source's own count) — a bar-chart-like read on
    /// importance, not just the numeral shown at its trailing edge.
    private func sourceRankRow(rank: Int, entry: SourceRank, maxCount: Int) -> some View {
        GeometryReader { proxy in
            let ratio = maxCount > 0 ? CGFloat(entry.count) / CGFloat(maxCount) : 1
            let width = max(proxy.size.width * ratio, 140)
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(theme.ink(0.4))
                    .frame(width: 22, alignment: .leading)
                Text(entry.host)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(entry.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.ink(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: width, alignment: .leading)
            // Filled with the view's own background (not `card`) and outlined
            // in the theme's chip/counter color, across every theme.
            .background(effectiveBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.chip, lineWidth: 1)
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var undoToast: some View {
        if !undoSnapshots.isEmpty {
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
                            .font(.system(size: 10.5, weight: .semibold))
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
            .animation(.easeOut(duration: 0.2), value: undoSnapshots.isEmpty)
        }
    }

    // MARK: Actions

    /// Saves the context and reports a failure instead of dropping it.
    ///
    /// Every mutation here used to end in a bare `try? modelContext.save()`,
    /// so a full disk or a constraint violation vanished without a trace:
    /// the in-memory objects looked updated, nothing reached the store, and
    /// neither the user nor the console ever heard about it.
    private func persist(_ operation: String = #function) {
        do {
            try modelContext.save()
        } catch {
            PlutarLog.store.error(
                "Save failed during \(operation, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            saveFailed = true
        }
    }

    private func open(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isRead = true
            persist()
        }
        if let url = URL(string: item.urlString) {
            openURL(url)
        }
    }

    private func markAsRead(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isRead = true
            persist()
        }
    }

    private func markAsUnread(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isRead = false
            persist()
        }
    }

    private func markSourceAsRead(_ items: [LinkItem]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            for item in items { item.isRead = true }
            persist()
        }
    }

    private func requestDelete(_ item: LinkItem) {
        undoSnapshots.append(DeletedSnapshot(item))
        modelContext.delete(item)
        persist()
        // Each delete restarts the window, so the user always gets the full
        // 5 seconds from their own last swipe rather than from the first
        // one in the batch.
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { undoSnapshots.removeAll() }
        }
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
        for item in allItems { modelContext.delete(item) }
        persist()
    }

    private func clearRead() {
        for item in allItems where item.isRead { modelContext.delete(item) }
        persist()
    }

    /// Marks every link currently shown (Date view: all unread links) as
    /// read in one go.
    private func markAllAsRead() {
        withAnimation(.easeInOut(duration: 0.25)) {
            for item in visibleItems { item.isRead = true }
            persist()
        }
    }

    /// Wipes the store and drops 200 demo links back in, freshly timestamped
    /// and with each of the 6 test sources' quantity randomized anew.
    private func regenerateLinks() {
        for item in allItems { modelContext.delete(item) }
        let items = SeedData.makeLinkItems()
        for item in items { modelContext.insert(item) }
        SourceRank.bump(items.map(\.host), in: modelContext)
        persist()
    }

    private func save(_ entry: SeedData.PoolEntry) {
        let item = entry.makeLinkItem()
        modelContext.insert(item)
        SourceRank.bump(item.host, in: modelContext)
        persist()
    }

    /// Zeroes out the persistent source-importance tally — see `SourceRank`.
    private func resetSourceRanking() {
        for rank in sourceRanks { modelContext.delete(rank) }
        persist()
    }
}

private struct ShareSimulationSheet: View {
    let entry: SeedData.PoolEntry
    let onOther: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Feuille de partage")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                Spacer()
                Button("Annuler", action: onCancel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: entry.colorHex).opacity(0.25))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.system(size: 13.5)).lineLimit(1)
                    Text(entry.host)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator))

            HStack(spacing: 10) {
                Button("Autre page", action: onOther)
                    .buttonStyle(.bordered)
                Button("Enregistrer dans Plutar", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
    }
}
