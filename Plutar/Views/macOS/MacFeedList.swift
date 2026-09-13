import SwiftUI
import SwiftData

/// The macOS feed list for one `FeedMode` (Date/Sources/Lus) — one instance
/// per `Tab` in `MacRootView`. Mirrors `RootView.feedScreen`'s grouping and
/// actions (mark read/unread, delete, clear read, mark all read, expand/
/// collapse sources), but with Mac-idiomatic interactions: a context menu
/// instead of swipe actions, and toolbar buttons instead of the floating
/// circular ones iOS uses. No shake-to-theme, no undo toast (macOS's own
/// Edit > Undo would be the natural fit for that — left for later, deleting
/// here is a plain confirmation-gated action for now).
struct MacFeedList: View {
    let mode: FeedMode
    let allItems: [LinkItem]
    let sourceRanks: [SourceRank]
    let theme: AppTheme
    let appFont: AppFont
    @Binding var layout: LinkLayout
    let showThumbnails: Bool
    let effectiveBackground: Color

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var expandedSources: Set<String> = []
    @State private var showClearReadConfirm = false
    @State private var showMarkAllReadConfirm = false
    /// Raised by `persist()` when a write to the store fails — mirrors
    /// `RootView.saveFailed`, so a failed save isn't silently swallowed on
    /// macOS the way a bare log line would leave it.
    @State private var saveFailed = false

    private var groups: [FeedGroup] { FeedGrouping.makeGroups(allItems, mode: mode) }
    /// One entry per host — merges any rows CloudKit sync left sharing the
    /// same host (see `SourceRank`'s comment) instead of assuming
    /// `sourceRanks` is already collision-free.
    private var rankedSources: [(host: String, count: Int)] { SourceRank.aggregated(sourceRanks) }

    /// Whether every group in `groups` is expanded — a real set check, not
    /// `expandedSources.count == groups.count` (which used to drive both the
    /// toolbar icon and `toggleAllSources()`): that count comparison goes
    /// true by coincidence whenever a stale id lingers in `expandedSources`
    /// for a source that has since emptied out of `groups`, e.g. after
    /// marking every link under one expanded source as read individually
    /// rather than via "mark source as read". Takes `groups` explicitly
    /// (rather than reading the computed property again) so `body` can pass
    /// the one copy it already computed instead of triggering another
    /// `FeedGrouping.makeGroups` pass.
    private func allSourcesExpanded(in groups: [FeedGroup]) -> Bool {
        !groups.isEmpty && groups.allSatisfy { expandedSources.contains($0.id) }
    }

    var body: some View {
        // Computed once per render and reused below — `groups`/
        // `rankedSources` are non-memoized computed properties (each a full
        // `FeedGrouping.makeGroups`/`SourceRank.aggregated` pass), and this
        // view used to call them repeatedly (`ForEach`, both empty-state
        // checks, three toolbar conditions) which redid that work up to 6
        // times per body evaluation — the same waste `RootView.toggleSource`
        // already guards against on iOS with its own `currentGroups` local.
        let currentGroups = groups
        let ranked = rankedSources
        let maxRankCount = ranked.map(\.count).max() ?? 1
        let sourcesAllExpanded = allSourcesExpanded(in: currentGroups)

        List {
            ForEach(currentGroups) { group in
                Section {
                    // Not a real Section header below — List pins plain-style
                    // Section headers to the top while scrolling, which for a
                    // date/source label swapping in and out on every scroll
                    // reads as UI stuck at the top of the window rather than
                    // part of the feed. Placed as a normal row instead, like
                    // iOS's `RootView.feedScreen`, so it scrolls by with
                    // everything else.
                    groupHeader(group)
                        .listRowSeparator(.hidden)
                    if mode != .source || expandedSources.contains(group.id) {
                        ForEach(group.items) { item in
                            LinkRowView(
                                item: item, layout: layout, theme: theme, appFont: appFont,
                                showThumbnails: showThumbnails, showFavicons: false,
                                showsPlaceholderThumbnail: false
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { open(item) }
                            .contextMenu { rowContextMenu(item) }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }

            if mode == .source && currentGroups.isEmpty && !sourceRanks.isEmpty {
                QuietEmptyStateView(
                    theme: theme, appFont: appFont, icon: "moon.stars",
                    title: "Aucun lien partagé",
                    text: "Les liens partagés depuis iPhone apparaîtront ici une fois synchronisés.",
                    fillHeight: false
                )
                .listRowSeparator(.hidden)
            }

            if mode == .source && !sourceRanks.isEmpty {
                Section("Sources les plus partagées") {
                    ForEach(Array(ranked.enumerated()), id: \.element.host) { index, rank in
                        sourceRankRow(rank: index + 1, host: rank.host, count: rank.count, maxCount: maxRankCount)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(effectiveBackground)
        .overlay {
            if currentGroups.isEmpty && !(mode == .source && !sourceRanks.isEmpty) {
                QuietEmptyStateView(
                    theme: theme, appFont: appFont, icon: "moon.stars",
                    title: mode == .read ? "Aucun lien lu" : "Aucun lien partagé",
                    text: mode == .read
                        ? "Les liens ouverts ou marqués comme lus apparaîtront ici"
                        : "Les liens partagés depuis iPhone apparaîtront ici une fois synchronisés."
                )
            }
        }
        .navigationTitle(mode.label)
        .toolbar {
            ToolbarItemGroup {
                // A `Picker` here would work but its closed-state button
                // shows the *selected* Label (icon + text), which reads as
                // an oversized toolbar button next to the others — a `Menu`
                // instead lets the closed button show just the icon, with
                // the full icon+text+checkmark rows only in the open list.
                Menu {
                    ForEach(LinkLayout.allCases) { l in
                        Button {
                            layout = l
                        } label: {
                            Label {
                                Text(l.label)
                            } icon: {
                                Image(systemName: l.symbolName)
                                    .scaleEffect(x: l.symbolIsMirrored ? -1 : 1, y: 1)
                            }
                            if l == layout {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Image(systemName: layout.symbolName)
                        .scaleEffect(x: layout.symbolIsMirrored ? -1 : 1, y: 1)
                }
                .help("Présentation du fil")

                if mode == .source && !currentGroups.isEmpty {
                    Button {
                        toggleAllSources()
                    } label: {
                        Label("Développer/réduire tout", systemImage: sourcesAllExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                if mode == .read && !currentGroups.isEmpty {
                    Button(role: .destructive) {
                        showClearReadConfirm = true
                    } label: {
                        Label("Vider les lus", systemImage: "trash")
                    }
                } else if !currentGroups.isEmpty {
                    Button {
                        showMarkAllReadConfirm = true
                    } label: {
                        Label("Tout marquer comme lu", systemImage: "checkmark.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Supprimer les liens lus",
            isPresented: $showClearReadConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { clearRead() }
        }
        .confirmationDialog(
            "Marquer tous les liens comme lus",
            isPresented: $showMarkAllReadConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Marquer comme lus") { markAllAsRead() }
        }
        .alert("Enregistrement impossible", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La dernière modification n'a pas pu être enregistrée et sera perdue à la fermeture de l'app.")
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ item: LinkItem) -> some View {
        if item.isRead {
            Button("Marquer non lu") { markAsUnread(item) }
        } else {
            Button("Marquer lu") { markAsRead(item) }
        }
        Button("Supprimer", role: .destructive) { delete(item) }
    }

    private func groupHeader(_ group: FeedGroup) -> some View {
        HStack(spacing: 8) {
            if mode == .source {
                Button {
                    toggleSource(group.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(group.label)
                        Text("\(group.items.count)")
                            .foregroundStyle(theme.ink(0.5))
                        Image(systemName: expandedSources.contains(group.id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .opacity(0.6)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(group.label)
            }
            Spacer()
            if expandedSourcesButtonVisible(group) {
                Button {
                    markSourceAsRead(group.items)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.plain)
            } else if mode == .read {
                Button {
                    deleteGroup(group.items)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .font(appFont.font(size: 13, weight: .semibold))
        .foregroundStyle(theme.ink(0.6))
        // Matches `LinkRowView.cardFace`'s own `.padding(.horizontal, 18)` —
        // its card background spans the full row, so the link's title text
        // sits 18pt in from the row edge; this row has no such background,
        // so without this padding its text started right at the row edge,
        // out of line with the title below it.
        .padding(.horizontal, 18)
    }

    private func expandedSourcesButtonVisible(_ group: FeedGroup) -> Bool {
        mode == .chrono || (mode == .source && expandedSources.contains(group.id))
    }

    private func sourceRankDisplayName(_ host: String) -> String {
        host.split(separator: ".").first.map(String.init) ?? host
    }

    private func sourceRankRow(rank: Int, host: String, count: Int, maxCount: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .foregroundStyle(theme.ink(0.4))
                .frame(width: 22, alignment: .leading)
            Text(sourceRankDisplayName(host))
                .foregroundStyle(theme.isSoir ? theme.ink(0.5) : theme.title)
            Spacer()
            Text("\(count)")
                .foregroundStyle(theme.ink(0.5))
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
    }

    // MARK: Actions — mirrors RootView's, without the undo/animation chrome.

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            PlutarLog.store.error("Save failed (macOS): \(String(describing: error), privacy: .public)")
            saveFailed = true
        }
    }

    private func open(_ item: LinkItem) {
        item.isRead = true
        persist()
        if let url = URL(string: item.urlString) { openURL(url) }
    }

    private func markAsRead(_ item: LinkItem) {
        item.isRead = true
        persist()
    }

    private func markAsUnread(_ item: LinkItem) {
        item.isRead = false
        item.excerptFetchAttempted = false
        persist()
    }

    private func markSourceAsRead(_ items: [LinkItem]) {
        for item in items { item.isRead = true }
        persist()
    }

    private func delete(_ item: LinkItem) {
        modelContext.delete(item)
        persist()
    }

    private func deleteGroup(_ items: [LinkItem]) {
        for item in items { modelContext.delete(item) }
        persist()
    }

    private func clearRead() {
        for item in allItems where item.isRead { modelContext.delete(item) }
        persist()
    }

    private func markAllAsRead() {
        for item in FeedGrouping.visibleItems(allItems, mode: mode) { item.isRead = true }
        persist()
    }

    private func toggleSource(_ id: String) {
        if expandedSources.contains(id) {
            expandedSources.remove(id)
        } else {
            expandedSources.insert(id)
        }
    }

    private func toggleAllSources() {
        // Read once, like `RootView.toggleSource`'s own `currentGroups` —
        // this is an event handler (one tap), not a render, so there's no
        // waste concern here; kept consistent with `body`'s pattern anyway.
        let currentGroups = groups
        if allSourcesExpanded(in: currentGroups) {
            expandedSources = []
        } else {
            expandedSources = Set(currentGroups.map(\.id))
        }
    }
}
