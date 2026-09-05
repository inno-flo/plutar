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

    @AppStorage("plutar.theme") private var themeRaw = AppTheme.couchant.rawValue
    @AppStorage("plutar.font") private var fontRaw = AppFont.futura.rawValue
    @AppStorage("plutar.layout") private var layoutRaw = LinkLayout.rail.rawValue
    @AppStorage("plutar.showThumbnails") private var showThumbnails = true

    @State private var mode: FeedMode = .chrono
    @State private var showSettings = false
    @State private var pendingShare: SeedData.PoolEntry?

    @State private var undoSnapshot: DeletedSnapshot?
    @State private var undoTask: Task<Void, Never>?

    @State private var showClearReadConfirm = false

    /// Hosts currently expanded in the Sources view — empty by default, so
    /// every source starts collapsed.
    @State private var expandedSources: Set<String> = []

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

    /// True once every source group is expanded — drives which icon the
    /// expand-all/collapse-all button shows.
    private var allSourcesExpanded: Bool {
        !groups.isEmpty && groups.allSatisfy { expandedSources.contains($0.label) }
    }

    private func toggleSource(_ label: String) {
        if expandedSources.contains(label) {
            expandedSources.remove(label)
        } else {
            expandedSources.insert(label)
        }
    }

    private func toggleAllSources() {
        expandedSources = allSourcesExpanded ? [] : Set(groups.map(\.label))
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: day).capitalized
    }

    var body: some View {
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
                                            if mode != .read {
                                                Button {
                                                    markAsRead(item)
                                                } label: {
                                                    Label("Lu", systemImage: "checkmark.square")
                                                }
                                                .tint(.gray)
                                            }
                                        }
                                }
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }

                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if groups.isEmpty {
                        EmptyStateView(
                            theme: theme,
                            title: mode == .read ? "Aucun lien lu" : "Fil vide",
                            text: mode == .read
                                ? "Les liens ouverts apparaîtront ici, grisés dans le fil."
                                : "Partagez une page depuis Safari ou n'importe quelle app, puis choisissez Plutar dans la feuille de partage.",
                            showsSimulateButton: mode != .read,
                            onSimulateShare: { pendingShare = SeedData.pool.randomElement() }
                        )
                    }
                }

                settingsButton
                if mode == .read && !groups.isEmpty {
                    clearReadButton
                } else if mode == .source && !groups.isEmpty {
                    toggleAllSourcesButton
                }
                undoToast
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .background(
                        theme.background.opacity(0.75)
                            .background(.ultraThinMaterial)
                    )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Alternate navigation, tried alongside the top tab row and
                // the floating gear button — nothing removed yet, per request.
                bottomTabBar
            }
        }
        .tint(theme.accent)
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
        .confirmationDialog(
            "Supprimer tous les liens lus ?",
            isPresented: $showClearReadConfirm,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { clearRead() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text("plutar")
                    .font(.system(size: 34, weight: .heavy, design: .default))
                    .italic()
                    .foregroundStyle(theme.accent)
                Spacer()
                Text("\(min(currentCount, 99))")
                    .font(.system(size: 22, weight: .heavy))
                    .frame(minWidth: 40, minHeight: 36)
                    .padding(.horizontal, 8)
                    .background(theme.accent)
                    .foregroundStyle(theme.countForeground)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            HStack(spacing: 6) {
                ForEach(FeedMode.allCases, id: \.self) { m in
                    Button {
                        mode = m
                    } label: {
                        Text(m.label)
                    }
                    .buttonStyle(TabButtonStyle(isActive: mode == m, theme: theme))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    /// Alternate navigation being tried alongside the top tab row and the
    /// floating gear button (Affichage opens the same settings sheet as
    /// that gear button, rather than switching `mode`).
    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(FeedMode.allCases, id: \.self) { m in
                tabBarItem(label: m.label, icon: m.icon, isActive: mode == m) {
                    mode = m
                }
            }
            tabBarItem(label: "Affichage", icon: "gear", isActive: false) {
                showSettings = true
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            theme.background.opacity(0.75)
                .background(.ultraThinMaterial)
        )
    }

    private func tabBarItem(label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isActive ? theme.accent : theme.ink(0.5))
            .frame(maxWidth: .infinity)
        }
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
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    private var settingsButton: some View {
        floatingButton(icon: "gear") { showSettings = true }
            .padding(.leading, 18)
            .padding(.bottom, 30)
    }

    private var clearReadButton: some View {
        floatingButton(icon: "trash") { showClearReadConfirm = true }
            .padding(.trailing, 18)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var toggleAllSourcesButton: some View {
        floatingButton(
            icon: allSourcesExpanded ? "inset.filled.topthird.middlethird.bottomthird.rectangle" : "text.square.filled",
            flipped: !allSourcesExpanded
        ) {
            toggleAllSources()
        }
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
            Button {
                toggleSource(group.label)
            } label: {
                sourceChipLabel(group)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        } else {
            Text(group.label)
                .font(.system(size: 12.5, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
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
                .font(.system(size: 12.5, weight: .bold))
            Text("\(group.items.count)")
                .font(.system(size: 10, weight: .heavy))
                .frame(minWidth: 17, minHeight: 17)
                .padding(.horizontal, 4)
                .background(theme.chipText.opacity(0.22))
                .clipShape(Capsule())
            Image(systemName: expandedSources.contains(group.label) ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(theme.chip)
        .foregroundStyle(theme.chipText)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var undoToast: some View {
        if let snapshot = undoSnapshot {
            VStack {
                Spacer()
                HStack {
                    Text("Supprimé · \(snapshot.title)")
                        .font(.system(size: 11.5))
                        .tracking(0.4)
                        .lineLimit(1)
                    Spacer()
                    Button("Annuler", action: performUndo)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .tint(theme.accentSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(theme.ink(1))
                .foregroundStyle(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 96)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.2), value: undoSnapshot != nil)
        }
    }

    // MARK: Actions

    private func open(_ item: LinkItem) {
        item.isRead = true
        try? modelContext.save()
        if let url = URL(string: item.urlString) {
            openURL(url)
        }
    }

    private func markAsRead(_ item: LinkItem) {
        item.isRead = true
        try? modelContext.save()
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

    /// Wipes the store and drops the 40 demo links back in, freshly
    /// timestamped — the same seed used on first launch.
    private func regenerateLinks() {
        for item in allItems { modelContext.delete(item) }
        for item in SeedData.makeLinkItems() { modelContext.insert(item) }
        try? modelContext.save()
    }

    private func save(_ entry: SeedData.PoolEntry) {
        modelContext.insert(entry.makeLinkItem())
        try? modelContext.save()
    }
}

private struct TabButtonStyle: ButtonStyle {
    let isActive: Bool
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .bold))
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(isActive ? theme.tabActive : theme.ink(0.07))
            .foregroundStyle(isActive ? theme.background : theme.ink(0.52))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
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
