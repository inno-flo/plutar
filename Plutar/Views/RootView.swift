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

    init(_ item: LinkItem) {
        title = item.title; urlString = item.urlString; host = item.host
        initial = item.initial; colorHex = item.colorHex; dateAdded = item.dateAdded
        sourceApp = item.sourceApp; excerpt = item.excerpt; hasThumbnail = item.hasThumbnail
    }

    func makeLinkItem() -> LinkItem {
        LinkItem(title: title, urlString: urlString, host: host, initial: initial,
                 colorHex: colorHex, dateAdded: dateAdded, sourceApp: sourceApp,
                 excerpt: excerpt, hasThumbnail: hasThumbnail)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \LinkItem.dateAdded, order: .reverse) private var allItems: [LinkItem]
    @Query(sort: \SourceRank.count, order: .reverse) private var sourceRanks: [SourceRank]

    @AppStorage("plutar.theme") private var themeRaw = AppTheme.couchant.rawValue
    @AppStorage("plutar.font") private var fontRaw = AppFont.futura.rawValue
    @AppStorage("plutar.layout") private var layoutRaw = LinkLayout.rail.rawValue
    @AppStorage("plutar.showThumbnails") private var showThumbnails = true

    @State private var mode: FeedMode = .chrono
    @State private var selectedTab: RootTab = .chrono
    @State private var showSettings = false
    @State private var pendingShare: SeedData.PoolEntry?

    @State private var undoSnapshot: DeletedSnapshot?
    @State private var undoTask: Task<Void, Never>?

    @State private var showClearReadConfirm = false
    @State private var showMarkAllReadConfirm = false
    @State private var showResetRankingConfirm = false

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

    private var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .couchant }
    }
    private var appFont: AppFont { AppFont(rawValue: fontRaw) ?? .futura }
    private var layout: LinkLayout {
        get { LinkLayout(rawValue: layoutRaw) ?? .rail }
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

    private var groups: [(label: String, items: [LinkItem])] {
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
            return order.map { day in (dayLabel(day), buckets[day]!) }
        case .source:
            let byHost = Dictionary(grouping: list, by: \.host)
            let hosts = byHost.keys.sorted { a, b in
                let ca = byHost[a]?.count ?? 0, cb = byHost[b]?.count ?? 0
                return ca != cb ? ca > cb : a < b
            }
            return hosts.map { host in (host, byHost[host] ?? []) }
        }
    }

    private func toggleSource(_ label: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if expandedSources.contains(label) {
                expandedSources.remove(label)
            } else {
                expandedSources.insert(label)
            }
            // Only the two "every source" extremes move the icon; anything
            // in between leaves it as it was.
            if !groups.isEmpty && groups.allSatisfy({ expandedSources.contains($0.label) }) {
                allSourcesExpandedIcon = true
            } else if expandedSources.isEmpty {
                allSourcesExpandedIcon = false
            }
        }
    }

    private func toggleAllSources() {
        withAnimation(.easeInOut(duration: 0.25)) {
            allSourcesExpandedIcon.toggle()
            expandedSources = allSourcesExpandedIcon ? Set(groups.map(\.label)) : []
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        let formatted = f.string(from: day)
        // French uses the ordinal "1er" for the first of the month, not "1"
        // — e.g. "1er avril", not "1 avril".
        let withOrdinal = calendar.component(.day, from: day) == 1
            ? formatted.replacingOccurrences(of: " 1 ", with: " 1er ")
            : formatted
        return withOrdinal.capitalized
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(FeedMode.allCases, id: \.self) { m in
                Tab(m.label, systemImage: m.icon, value: RootTab(m)) {
                    feedScreen
                }
            }
            // Not a real destination — see `RootTab.settings` and the
            // `onChange(of: selectedTab)` handler below. Its content mirrors
            // the feed (instead of e.g. `Color.clear`) so the instant that
            // TabView actually switches to it — before we bounce the
            // selection back — there's nothing visually different to flash.
            Tab("Affichage", systemImage: "gear", value: RootTab.settings) {
                feedScreen
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
        // label/material colors from light vs. dark mode. Without this, a
        // dark theme (e.g. Crépuscule) still gets light-mode system chrome,
        // and its unselected tab icons/text can end up nearly invisible
        // against the floating tab bar's own background.
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                theme: Binding(get: { theme }, set: { themeRaw = $0.rawValue }),
                appFont: Binding(get: { appFont }, set: { fontRaw = $0.rawValue }),
                showThumbnails: $showThumbnails,
                layout: Binding(get: { layout }, set: { layoutRaw = $0.rawValue }),
                onClearAll: { clearAll(); showSettings = false },
                onRegenerate: { regenerateLinks(); showSettings = false },
                onClose: { showSettings = false }
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
    }

    /// The actual feed screen — identical content shown under all three feed
    /// tabs; which links it shows is driven by the shared `mode` state, not
    /// by which tab is selected.
    private var feedScreen: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                theme.background.ignoresSafeArea()

                List {
                    ForEach(groups, id: \.label) { group in
                        Section {
                            if mode != .source || expandedSources.contains(group.label) {
                                ForEach(group.items) { item in
                                    LinkRowView(item: item, layout: layout, theme: theme, appFont: appFont, showThumbnails: showThumbnails)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                                        .contentShape(Rectangle())
                                        .onTapGesture { open(item) }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { requestDelete(item) } label: {
                                                Label("Supprimer", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            if mode == .read {
                                                Button {
                                                    markAsUnread(item)
                                                } label: {
                                                    Label("Non lu", systemImage: "checkmark.circle")
                                                }
                                                .tint(.green)
                                            } else {
                                                Button {
                                                    markAsRead(item)
                                                } label: {
                                                    Label("Lu", systemImage: "checkmark.circle.fill")
                                                }
                                                .tint(.gray)
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
                        } header: {
                            groupHeader(group)
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
                .animation(.easeInOut(duration: 0.25), value: expandedSources)
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
            // No title bar in any view. The counter shows in Date and
            // Sources — removed from Lus. A reserved safe-area inset
            // (rather than a ZStack overlay) so it never overlaps the
            // list's own content — in Sources, the first source's chip can
            // carry its own mark-as-read button right at the top, and the
            // two were colliding when the counter merely floated on top.
            .safeAreaInset(edge: .top, spacing: 0) {
                if mode == .chrono || mode == .source {
                    floatingCounterBadge
                }
            }
        }
    }

    /// The link-count pill, floating on its own with no surrounding title
    /// bar, in the same top-trailing spot a header used to place it.
    private var floatingCounterBadge: some View {
        HStack {
            Spacer()
            Text("\(min(currentCount, 99))")
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
    private func groupHeader(_ group: (label: String, items: [LinkItem])) -> some View {
        if mode == .source {
            // Centered alignment keeps the mark-all-read icon on the same
            // vertical line as the count badge and chevron inside the chip.
            HStack(alignment: .center, spacing: 10) {
                Button {
                    toggleSource(group.label)
                } label: {
                    sourceChipLabel(group)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // Only while expanded — marks every link from this source as
                // read, which empties it out of the (unread-only) Sources
                // view, so the source disappears from the list.
                if expandedSources.contains(group.label) {
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

    private func sourceChipLabel(_ group: (label: String, items: [LinkItem])) -> some View {
        HStack(spacing: 7) {
            Text(group.label)
                .font(.system(size: 16.5, weight: .bold))
            Text("\(group.items.count)")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(theme == .marine ? .white : theme.chipText)
                .frame(minWidth: 17, minHeight: 17)
                .padding(.horizontal, 4)
                .background(theme.chipText.opacity(0.22))
                .clipShape(Capsule())
            Image(systemName: expandedSources.contains(group.label) ? "chevron.up" : "chevron.down")
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
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var undoToast: some View {
        if undoSnapshot != nil {
            VStack {
                Spacer()
                HStack {
                    Text("Supprimé")
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
            .animation(.easeOut(duration: 0.2), value: undoSnapshot != nil)
        }
    }

    // MARK: Actions

    private func open(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isRead = true
            try? modelContext.save()
        }
        if let url = URL(string: item.urlString) {
            openURL(url)
        }
    }

    private func markAsRead(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isRead = true
            try? modelContext.save()
        }
    }

    private func markAsUnread(_ item: LinkItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            item.isRead = false
            try? modelContext.save()
        }
    }

    private func markSourceAsRead(_ items: [LinkItem]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            for item in items { item.isRead = true }
            try? modelContext.save()
        }
    }

    private func requestDelete(_ item: LinkItem) {
        let snapshot = DeletedSnapshot(item)
        modelContext.delete(item)
        try? modelContext.save()
        undoSnapshot = snapshot
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { undoSnapshot = nil }
        }
    }

    private func performUndo() {
        guard let snapshot = undoSnapshot else { return }
        modelContext.insert(snapshot.makeLinkItem())
        try? modelContext.save()
        undoTask?.cancel()
        undoSnapshot = nil
    }

    private func clearAll() {
        for item in allItems { modelContext.delete(item) }
        try? modelContext.save()
    }

    private func clearRead() {
        for item in allItems where item.isRead { modelContext.delete(item) }
        try? modelContext.save()
    }

    /// Marks every link currently shown (Date view: all unread links) as
    /// read in one go.
    private func markAllAsRead() {
        withAnimation(.easeInOut(duration: 0.25)) {
            for item in visibleItems { item.isRead = true }
            try? modelContext.save()
        }
    }

    /// Wipes the store and drops the 40 demo links back in, freshly
    /// timestamped — the same seed used on first launch.
    private func regenerateLinks() {
        for item in allItems { modelContext.delete(item) }
        for item in SeedData.makeLinkItems() {
            modelContext.insert(item)
            SourceRank.bump(item.host, in: modelContext)
        }
        try? modelContext.save()
    }

    private func save(_ entry: SeedData.PoolEntry) {
        let item = entry.makeLinkItem()
        modelContext.insert(item)
        SourceRank.bump(item.host, in: modelContext)
        try? modelContext.save()
    }

    /// Zeroes out the persistent source-importance tally — see `SourceRank`.
    private func resetSourceRanking() {
        for rank in sourceRanks { modelContext.delete(rank) }
        try? modelContext.save()
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
