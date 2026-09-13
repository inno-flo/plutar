import SwiftUI
import SwiftData

/// The macOS feed list for one detail selection (Date/Lus/a single source) —
/// one instance per `MacRootView.detailView` case. Mirrors
/// `RootView.feedScreen`'s grouping and actions (mark read/unread, delete,
/// clear read, mark all read, expand/collapse sources), but with
/// Mac-idiomatic interactions: a context menu instead of swipe actions, and
/// toolbar buttons instead of the floating circular ones iOS uses. No
/// shake-to-theme, no undo toast (macOS's own Edit > Undo would be the
/// natural fit for that — left for later, deleting here is a plain
/// confirmation-gated action for now).
///
/// The old "Sources les plus partagées" ranking (backed by `SourceRank`) is
/// hidden for now — no home in the sidebar-driven layout yet, see
/// `MacRootView`/`MacSidebarView`. Revisit once it has a place to live.
struct MacFeedList: View {
    let mode: FeedMode
    /// Navigation title — `mode.label` for Date/Lus, the source's full host
    /// name for a single-source detail (`MacRootView` passes both).
    let title: String
    let allItems: [LinkItem]
    let theme: AppTheme
    let appFont: AppFont
    @Binding var layout: LinkLayout
    let showThumbnails: Bool
    let effectiveBackground: Color
    /// True when this instance shows one already-selected source's links
    /// (from the sidebar), as opposed to the merged, expand-per-source
    /// "Sources" screen `mode == .source` used to mean on its own. Suppresses
    /// the per-group expand/collapse chevron and the toolbar's "expand all"
    /// button, since there's always exactly one group here and it should
    /// just start open.
    var isSingleSourceDetail: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var expandedSources: Set<String>
    /// A single click now only selects a row (native macOS List selection,
    /// with its usual highlight color) — it used to open the link directly,
    /// which meant there was no way to select a row first the way iOS lets
    /// you before swiping. Double-click still opens.
    @State private var selectedItemID: LinkItem.ID?
    @State private var showClearReadConfirm = false
    @State private var showMarkAllReadConfirm = false
    /// Set instead of deleting immediately — both the row context menu's
    /// "Supprimer" and a source/day group's trash button used to delete
    /// right away with no confirmation, unlike every other destructive
    /// action here (`showClearReadConfirm`/`showMarkAllReadConfirm` above).
    @State private var itemPendingDelete: LinkItem?
    @State private var groupItemsPendingDelete: [LinkItem]?
    /// Raised by `persist()` when a write to the store fails — mirrors
    /// `RootView.saveFailed`, so a failed save isn't silently swallowed on
    /// macOS the way a bare log line would leave it.
    @State private var saveFailed = false

    init(
        mode: FeedMode, title: String, allItems: [LinkItem], theme: AppTheme, appFont: AppFont,
        layout: Binding<LinkLayout>, showThumbnails: Bool, effectiveBackground: Color,
        isSingleSourceDetail: Bool = false, initialExpandedSources: Set<String> = []
    ) {
        self.mode = mode
        self.title = title
        self.allItems = allItems
        self.theme = theme
        self.appFont = appFont
        self._layout = layout
        self.showThumbnails = showThumbnails
        self.effectiveBackground = effectiveBackground
        self.isSingleSourceDetail = isSingleSourceDetail
        self._expandedSources = State(initialValue: initialExpandedSources)
    }

    private var groups: [FeedGroup] { FeedGrouping.makeGroups(allItems, mode: mode) }

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
        // Computed once per render and reused below — `groups` is a
        // non-memoized computed property (a full `FeedGrouping.makeGroups`
        // pass), and this view used to call it repeatedly (`ForEach`, the
        // empty-state check, toolbar conditions) which redid that work
        // several times per body evaluation — the same waste
        // `RootView.toggleSource` already guards against on iOS with its own
        // `currentGroups` local.
        let currentGroups = groups
        let sourcesAllExpanded = allSourcesExpanded(in: currentGroups)

        // Not `List(selection:)` — macOS draws that selection as a ring
        // behind the row regardless of `listRowBackground`/`listRowInsets`
        // (a distinct highlight layer under the row content, not something
        // those modifiers reach), which is exactly the ring this was meant
        // to replace. Tracking `selectedItemID` as plain state instead, set
        // from a single-tap below, leaves the card's own accent fill (via
        // `isSelected` on `LinkRowView`) as the only visual for selection.
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
                    if mode != .source || isSingleSourceDetail || expandedSources.contains(group.id) {
                        ForEach(group.items) { item in
                            LinkRowView(
                                item: item, layout: layout, theme: theme, appFont: appFont,
                                showThumbnails: showThumbnails, showFavicons: false,
                                showsPlaceholderThumbnail: false,
                                isSelected: selectedItemID == item.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 1) { selectedItemID = item.id }
                            .onTapGesture(count: 2) { open(item) }
                            .contextMenu { rowContextMenu(item) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { itemPendingDelete = item } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                                .tint(theme.deleteSwipeTint)
                            }
                            .swipeActions(edge: .leading) {
                                if item.isRead {
                                    Button { markAsUnread(item) } label: {
                                        Label("Marquer non lu", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(theme.markUnreadSwipeTint)
                                } else {
                                    Button { markAsRead(item) } label: {
                                        Label("Marquer lu", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(theme.markReadSwipeTint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(effectiveBackground)
        .overlay {
            if currentGroups.isEmpty {
                QuietEmptyStateView(
                    theme: theme, appFont: appFont, icon: "moon.stars",
                    title: mode == .read ? "Aucun lien lu" : "Aucun lien partagé",
                    text: mode == .read
                        ? "Les liens ouverts ou marqués comme lus apparaîtront ici"
                        : "Les liens partagés depuis iPhone apparaîtront ici une fois synchronisés."
                )
            }
        }
        .navigationTitle(title)
        .toolbar {
            // Two separate groups — macOS puts a gap between distinct
            // `ToolbarItemGroup`s on its own. The 3 layout icons render as
            // one joined segmented block (native chrome, dividers between
            // icons, a highlight behind the selected one); the mark-as-
            // read/clear button stays a single plain toolbar button, apart
            // from that block rather than sharing a background with it.
            ToolbarItemGroup {
                layoutSwitcher
            }
            ToolbarItemGroup {
                if mode == .source && !isSingleSourceDetail && !currentGroups.isEmpty {
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
                    .help("Tout supprimer")
                } else if !currentGroups.isEmpty {
                    Button {
                        showMarkAllReadConfirm = true
                    } label: {
                        Label("Tout marquer comme lu", systemImage: "checkmark.circle")
                    }
                    .help("Tout marquer comme lus")
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
            Button("Marquer comme lus", role: .destructive) { markAllAsRead() }
        }
        .confirmationDialog(
            "Supprimer ce lien ?",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { if !$0 { itemPendingDelete = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                if let item = itemPendingDelete { delete(item) }
            }
        }
        .confirmationDialog(
            "Supprimer ces liens ?",
            isPresented: Binding(
                get: { groupItemsPendingDelete != nil },
                set: { if !$0 { groupItemsPendingDelete = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                if let items = groupItemsPendingDelete { deleteGroup(items) }
            }
        }
        .alert("Enregistrement impossible", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La dernière modification n'a pas pu être enregistrée et sera perdue à la fermeture de l'app.")
        }
    }

    /// One joined segmented block for the 3 `LinkLayout` icons — a real
    /// `Picker` in `.segmented` style, not a hand-rolled capsule, so it gets
    /// macOS's own chrome: dividers between icons and a highlight behind
    /// whichever one is selected, matching how e.g. Finder's view-mode
    /// switcher looks. `.help()` on each icon still names its function.
    private var layoutSwitcher: some View {
        Picker("Présentation du fil", selection: $layout) {
            ForEach(LinkLayout.allCases) { l in
                Image(systemName: l.symbolName)
                    .scaleEffect(x: l.symbolIsMirrored ? -1 : 1, y: 1)
                    .help(l.label)
                    .tag(l)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func rowContextMenu(_ item: LinkItem) -> some View {
        if item.isRead {
            Button("Marquer non lu") { markAsUnread(item) }
        } else {
            Button("Marquer lu") { markAsRead(item) }
        }
        Button("Supprimer", role: .destructive) { itemPendingDelete = item }
    }

    private func groupHeader(_ group: FeedGroup) -> some View {
        HStack(spacing: 8) {
            if mode == .source && !isSingleSourceDetail {
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
            } else if mode == .source {
                Text(group.label)
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
                    groupItemsPendingDelete = group.items
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
        mode == .chrono || isSingleSourceDetail || (mode == .source && expandedSources.contains(group.id))
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
