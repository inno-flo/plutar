import SwiftUI
import SwiftData
import AppKit

/// The per-view UI state of one `MacFeedList` (Date, Lus, or a single
/// source), owned by `MacRootView` and keyed by sidebar selection — so
/// switching to another sidebar item and back finds each view as it was left
/// instead of rebuilding it from scratch.
struct MacFeedViewState {
    /// Lus: collapsed day/source groups — see `MacFeedList`.
    var collapsedReadGroups: Set<String> = []
    /// Lus, day-grouped: collapsed calendar months ("yyyy-MM" keys).
    var collapsedMonths: Set<String> = []
    var selectedItemID: UUID?
}

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
    let effectiveBackground: Color
    /// True when this instance shows one already-selected source's links
    /// (from the sidebar): there's exactly one group, with no header.
    var isSingleSourceDetail: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    /// Wires "Marquer lu"/"Marquer non lu"/"Tout marquer comme lu" into the window's Edit >
    /// Annuler — neither had any effect on it before, unlike delete (which
    /// already gets a confirmation dialog instead).
    @Environment(\.undoManager) private var undoManager

    /// Owned by `MacRootView` (see `MacFeedViewState`), so it outlives this
    /// view when another sidebar item is selected.
    @Binding var state: MacFeedViewState
    /// Scroll offsets of every feed view — see `ScrollOffsetStore`; this view's
    /// own entry is keyed by `scrollKey`.
    let scrollStore: ScrollOffsetStore
    let scrollKey: String
    /// Lus only: when true, `groups` below buckets by source (ranked by
    /// link count, like Sources) instead of by day. Toggled by the globe
    /// toolbar button, which swaps to "calendar" while this is active.
    /// `@AppStorage`, not plain `@State` — stays as the user last set it
    /// (across launches and other `MacFeedList` instances, e.g. switching
    /// to another sidebar item and back) until changed again; day grouping
    /// is the default on first launch.
    @AppStorage(DisplaySettingsKey.readGroupedBySource) private var readGroupedBySource = false
    /// Lus only: which day/source group headers are collapsed (their links
    /// hidden) — membership means collapsed, so the default (nothing in the
    /// set) is every group expanded, same as before this feature existed.
    /// Toggled per-group by double-clicking its header, or all at once by
    /// the collapse-all/expand-all toolbar button next to the globe/
    /// calendar one.
    private var collapsedReadGroups: Set<String> {
        get { state.collapsedReadGroups }
        nonmutating set { state.collapsedReadGroups = newValue }
    }
    private var collapsedMonths: Set<String> {
        get { state.collapsedMonths }
        nonmutating set { state.collapsedMonths = newValue }
    }
    /// A single click now only selects a row (native macOS List selection,
    /// with its usual highlight color) — it used to open the link directly,
    /// which meant there was no way to select a row first the way iOS lets
    /// you before swiping. Double-click still opens.
    private var selectedItemID: LinkItem.ID? {
        get { state.selectedItemID }
        nonmutating set { state.selectedItemID = newValue }
    }
    /// Bumped once, shortly after the app's very first feed list appears, to
    /// rebuild its `List` — see the `.id` on it below.
    @State private var listGeneration = 0
    @State private var scrollPosition = ScrollPosition()
    private static var didInitialListRebuild = false
    @State private var showMarkAllReadConfirm = false
    /// Set instead of deleting immediately — both the row context menu's
    /// "Supprimer" and a source/day group's trash button used to delete
    /// right away with no confirmation, unlike every other destructive
    /// action here (`showClearReadConfirm`/`showMarkAllReadConfirm` above).
    @State private var itemPendingDelete: LinkItem?
    /// Raised by `persist()` when a write to the store fails — mirrors
    /// `RootView.saveFailed`, so a failed save isn't silently swallowed on
    /// macOS the way a bare log line would leave it.
    @State private var saveFailed = false

    init(
        mode: FeedMode, title: String, allItems: [LinkItem], theme: AppTheme, appFont: AppFont,
        layout: Binding<LinkLayout>, effectiveBackground: Color, state: Binding<MacFeedViewState>,
        scrollStore: ScrollOffsetStore, scrollKey: String,
        isSingleSourceDetail: Bool = false
    ) {
        self.mode = mode
        self.title = title
        self.allItems = allItems
        self.theme = theme
        self.appFont = appFont
        self._layout = layout
        self.effectiveBackground = effectiveBackground
        self.isSingleSourceDetail = isSingleSourceDetail
        self._state = state
        self.scrollStore = scrollStore
        self.scrollKey = scrollKey
    }

    private var groups: [FeedGroup] {
        FeedGrouping.groups(allItems, mode: mode, readGroupedBySource: readGroupedBySource)
    }

    /// Lus, day-grouped only: ids of the first day group in each calendar
    /// month, once links actually span more than one — see
    /// `FeedGrouping.monthSeparatorGroupIDs`. Empty in every other mode/
    /// grouping, same as the iOS `RootView` counterpart.
    private func monthSeparatorGroupIDs(in groups: [FeedGroup]) -> Set<String> {
        guard mode == .read, !readGroupedBySource else { return [] }
        return FeedGrouping.monthSeparatorGroupIDs(groups)
    }

    /// Whether every group in `groups` is collapsed — drives Lus's collapse-
    /// all/expand-all toolbar button. Applies to day *or* source groups
    /// depending on `readGroupedBySource`. Takes `groups` explicitly so
    /// `body` can pass the one copy it already computed.
    private func allReadGroupsCollapsed(in groups: [FeedGroup]) -> Bool {
        !groups.isEmpty && groups.allSatisfy { collapsedReadGroups.contains($0.id) }
    }

    var body: some View {
        // Computed once per render and reused below — `groups` is a
        // non-memoized computed property (a full `FeedGrouping.makeGroups`
        // pass), and this view used to call it repeatedly (`ForEach`, the
        // empty-state check, toolbar conditions) which redid that work
        // several times per body evaluation.
        let currentGroups = groups
        let readAllCollapsed = allReadGroupsCollapsed(in: currentGroups)
        // Same for the month-separator ids — this used to be a computed
        // property read once per group inside the `ForEach`, each read
        // redoing the whole grouping.
        let monthSeparatorIDs = monthSeparatorGroupIDs(in: currentGroups)

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
                    //
                    // Skipped entirely for a single-source detail: its own
                    // name is already the toolbar title, and its "mark as
                    // read" icon just duplicates the toolbar's own button.
                    if !isSingleSourceDetail {
                        if monthSeparatorIDs.contains(group.id),
                           let date = FeedGrouping.dayKeyFormatter.date(from: group.id) {
                            monthSeparator(
                                FeedGrouping.monthLabel(for: date),
                                monthKey: FeedGrouping.monthKey(fromDayGroupID: group.id)
                            )
                            .listRowSeparator(.hidden)
                        }
                        if !isInCollapsedMonth(group) {
                            groupHeader(group)
                                .listRowSeparator(.hidden)
                        }
                    }
                    if !isInCollapsedMonth(group)
                        && !(mode == .read && collapsedReadGroups.contains(group.id)) {
                        ForEach(group.items) { item in
                            LinkRowView(
                                item: item, layout: layout, theme: theme, appFont: appFont,
                                showHost: !isSingleSourceDetail,
                                isSelected: selectedItemID == item.id,
                                plainStyle: true
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 1) { selectedItemID = item.id }
                            .onTapGesture(count: 2) { open(item) }
                            .contextMenu { rowContextMenu(item) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                // Unlike the trash-icon buttons (`itemPendingDelete`,
                                // confirmed via `confirmationDialog` below), a swipe
                                // is itself already a deliberate, two-step gesture —
                                // requiring a second confirmation on top of it is the
                                // odd one out next to every other swipe-to-delete list
                                // on the platform, so this deletes straight away.
                                Button(role: .destructive) { delete([item]) } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                                .tint(theme.deleteSwipeTint)
                            }
                            .swipeActions(edge: .leading) {
                                Button { toggleRead(item) } label: {
                                    Label(item.isRead ? "Marquer non lu" : "Marquer lu", systemImage: "checkmark.circle.fill")
                                }
                                .tint(item.isRead ? theme.markUnreadSwipeTint : theme.markReadSwipeTint)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // On the app's first launch, the first list's rows can be measured
        // before the window/column reaches its final width and keep a stale,
        // too-short height — clipped cells until something forces a rebuild
        // (switching the presentation did). Rebuilding the `List` once, a
        // moment after it first appears, does the same. Once per launch:
        // later lists are created at their final size.
        .id(listGeneration)
        .task {
            guard !Self.didInitialListRebuild else { return }
            Self.didInitialListRebuild = true
            try? await Task.sleep(for: .milliseconds(40))
            listGeneration += 1
        }
        .rememberScrollOffset(in: scrollStore, key: scrollKey, position: $scrollPosition)
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
            // Three separate groups — macOS puts a gap between distinct
            // `ToolbarItemGroup`s on its own. The 3 layout icons render as
            // one joined segmented block (native chrome, dividers between
            // icons, a highlight behind the selected one); the globe
            // placeholder and the mark-as-read/clear button each stay their
            // own single plain toolbar button, apart from that block and
            // from each other rather than sharing a background.
            if mode == .read && !currentGroups.isEmpty {
                ToolbarItemGroup {
                    Button {
                        // Collapsed-group ids belong to whichever grouping
                        // was active when they were collapsed (day keys vs.
                        // hosts), so they can't carry over as-is — but the
                        // all-or-nothing "everything folded" state itself
                        // should: re-derived against the new grouping's own
                        // ids instead of just dropped. A partial (some-but-
                        // not-all) collapse has no equivalent in the other
                        // grouping, so only the two extremes survive.
                        readGroupedBySource.toggle()
                        collapsedReadGroups = readAllCollapsed ? Set(groups.map(\.id)) : []
                    } label: {
                        Label(
                            readGroupedBySource ? "Grouper par date" : "Grouper par source",
                            systemImage: readGroupedBySource ? "calendar" : "newspaper.fill"
                        )
                    }
                    .help(readGroupedBySource ? "Grouper par date" : "Grouper par source")
                }
                ToolbarItemGroup {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            collapsedReadGroups = readAllCollapsed ? [] : Set(currentGroups.map(\.id))
                        }
                    } label: {
                        // Showing "collapse all" until every group actually
                        // is collapsed, then "expand all" — matches whatever
                        // double-clicking individual headers already did,
                        // not just this button's own last click. Same icon
                        // pair as iOS's own equivalent control.
                        Image(systemName: readAllCollapsed ? "square.fill.text.grid.1x2" : "inset.filled.topthird.middlethird.bottomthird.rectangle")
                            .scaleEffect(x: readAllCollapsed ? -1 : 1, y: 1)
                    }
                    .help(readAllCollapsed ? "Tout déplier" : "Tout replier")
                }
            }
            ToolbarItemGroup {
                layoutSwitcher
            }
            ToolbarItemGroup {
                if mode != .read && !currentGroups.isEmpty {
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
            "Marquer tous les liens comme lus",
            isPresented: $showMarkAllReadConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Marquer comme lus", role: .destructive) {
                markAsRead(FeedGrouping.visibleItems(allItems, mode: mode), actionName: "Tout marquer comme lu")
            }
        }
        .confirmationDialog(
            "Supprimer ce lien",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { if !$0 { itemPendingDelete = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                if let item = itemPendingDelete { delete([item]) }
            }
        }
        .saveFailureAlert(isPresented: $saveFailed)
    }

    /// One joined segmented block for the 3 `LinkLayout` icons — a real
    /// `Picker` in `.segmented` style, not a hand-rolled capsule, so it gets
    /// macOS's own chrome: dividers between icons and a highlight behind
    /// whichever one is selected, matching how e.g. Finder's view-mode
    /// switcher looks. `.help()` on each icon still names its function.
    private var layoutSwitcher: some View {
        Picker("Présentation du fil", selection: $layout) {
            ForEach(LinkLayout.allCases) { l in
                // `Picker(.segmented)` bakes each `Image` into a static
                // `NSSegmentedControl` segment image — neither a plain
                // `.scaleEffect` nor an `.environment(\.layoutDirection)`
                // (which *did* pick the symbol's own right-to-left variant,
                // confirmed visually, but got lost once `.imageScale` was
                // added alongside it) survives that conversion reliably.
                // Baking the flip into the image's own pixels via
                // `Self.symbolImage`, with an explicit point size matching
                // what `.imageScale(.large)` produced, is deterministic
                // regardless of how the Picker bakes its segments.
                Image(nsImage: Self.symbolImage(l.symbolName, mirrored: l.symbolIsMirrored))
                    .help(l.presentationHelp)
                    .tag(l)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// An SF Symbol as an `NSImage`, horizontally flipped at the pixel
    /// level when `mirrored` — see `layoutSwitcher`'s own comment for why
    /// baking this in is more reliable than a SwiftUI-side modifier inside
    /// a segmented `Picker`. `.large` matches the size the mirrored icon
    /// needs to visually match its two un-mirrored, default-size siblings.
    private static func symbolImage(_ name: String, mirrored: Bool) -> NSImage {
        let configuration: NSImage.SymbolConfiguration? = mirrored ? .init(scale: .large) : nil
        let base = (NSImage(systemSymbolName: name, accessibilityDescription: nil))
            .flatMap { image in configuration.flatMap { image.withSymbolConfiguration($0) } ?? image }
            ?? NSImage()
        guard mirrored else { return base }
        let flipped = NSImage(size: base.size, flipped: false) { rect in
            NSGraphicsContext.current?.cgContext.translateBy(x: rect.width, y: 0)
            NSGraphicsContext.current?.cgContext.scaleBy(x: -1, y: 1)
            base.draw(in: rect)
            return true
        }
        // Keeps the symbol rendering as a template (tintable, theme-aware)
        // image rather than a fixed-color bitmap — `draw(in:)` above copies
        // pixels, not this flag, so it has to be set again on the result.
        flipped.isTemplate = base.isTemplate
        return flipped
    }

    @ViewBuilder
    private func rowContextMenu(_ item: LinkItem) -> some View {
        Button(item.isRead ? "Marquer non lu" : "Marquer lu") { toggleRead(item) }
        Button("Copier l'URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.urlString, forType: .string)
        }
        Button {
            togglePin(item)
        } label: {
            Label(item.isPinned ? "Détacher le lien" : "Épingler le lien",
                  systemImage: item.isPinned ? "pin.slash" : "pin")
                .labelStyle(.titleAndIcon)
        }
        // Ellipsis: this doesn't delete outright — it opens the
        // confirmationDialog below (itemPendingDelete), same convention as
        // any other menu command needing more input before it completes.
        Button("Supprimer…", role: .destructive) { itemPendingDelete = item }
    }

    /// Day-label color (Date/Lus) — an accent borrowed from the iPhone
    /// version for Tokyo clair (red, `RootView.counterBackground`, i.e.
    /// `theme.dotColor`; not `theme.chip`, which is black for Tokyo),
    /// Copenhague clair (its ochre yellow, `theme.dotColor`) and Cap Canaveral clair
    /// ("international orange", `RootView.counterForegroundOverride`); the
    /// muted ink every other theme uses.
    private var dayLabelColor: Color {
        switch theme {
        case .tokyo, .scand: return theme.dotColor
        case .astronaute: return theme.accent
        default: return theme.ink(0.6)
        }
    }

    /// Lus, day-grouped only — the month name and year, with no rule,
    /// shown above the first day group of each calendar month once links
    /// span more than one (see `monthSeparatorGroupIDs`), with a chevron
    /// collapsing/expanding that whole month.
    private func monthSeparator(_ label: String, monthKey: String) -> some View {
        let isCollapsed = collapsedMonths.contains(monthKey)
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                collapsedMonths.toggle(monthKey)
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                Spacer(minLength: 0)
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.6)
            }
            .font(appFont.font(size: 13, weight: .semibold))
            .foregroundStyle(theme.ink(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        // Same gap above and below the month/year label.
        .padding(.vertical, 20)
    }

    /// Lus, day-grouped: whether `group` belongs to a month collapsed via
    /// its separator's chevron — its header and links are hidden then.
    private func isInCollapsedMonth(_ group: FeedGroup) -> Bool {
        mode == .read && !readGroupedBySource
            && collapsedMonths.contains(FeedGrouping.monthKey(fromDayGroupID: group.id))
    }

    private func groupHeader(_ group: FeedGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(group.label)
                        .foregroundStyle(dayLabelColor)
                    // Lus only — a link-count pastille, only while the group
                    // is collapsed, same as iOS.
                    if mode == .read && collapsedReadGroups.contains(group.id) {
                        Text("\(group.items.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.ink(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.ink(0.12))
                            .clipShape(Capsule())
                    }
                }
                // Lus only — Date has no collapse feature. Toggles just this
                // one group, independent of the toolbar's collapse-all/
                // expand-all button.
                .onTapGesture(count: 1) {
                    guard mode == .read else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        collapsedReadGroups.toggle(group.id)
                    }
                }
                Spacer()
            }
            .font(appFont.font(size: 17, weight: .semibold))
            .foregroundStyle(theme.ink(0.6))
            // `plainStyle` rows have no card to visually separate groups
            // anymore — a 2pt rule under every date/source label instead,
            // as wide as the card it replaces.
            Rectangle()
                .fill(theme.ink(0.15))
                .frame(maxWidth: .infinity)
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Matches `LinkRowView.cardFace`'s own `.padding(.horizontal, 18)` —
        // its card background spans the full row, so the link's title text
        // sits 18pt in from the row edge; this row has no such background,
        // so without this padding its text started right at the row edge,
        // out of line with the title below it.
        .padding(.horizontal, 18)
    }

    // MARK: Actions — mirrors RootView's, without the undo/animation chrome.

    private func persist(_ operation: String = #function) {
        if !modelContext.persist(operation) { saveFailed = true }
    }

    /// Bundle id for Firefox — forced open (below) needs the app's own URL,
    /// which `NSWorkspace` only hands out by bundle id, not by name.
    private static let firefoxBundleID = "org.mozilla.firefox"

    private func open(_ item: LinkItem) {
        // A pinned link stays in À lire on double-click too — only an
        // explicit "Marquer lu" or delete moves it on.
        if !item.isPinned {
            item.isRead = true
            persist()
        }
        guard let url = URL(string: item.urlString) else { return }
        // The Verge's own site renders its article pages oddly in whatever
        // this Mac's default browser is — forced to Firefox regardless,
        // rather than leaving it to `openURL`'s system default. Falls back
        // to that default if Firefox isn't installed, rather than silently
        // doing nothing.
        if item.host == "theverge.com",
           let firefoxURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.firefoxBundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: firefoxURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            openURL(url)
        }
    }

    /// Registers `undo` on the environment's `UndoManager` under the given
    /// menu name, targeting the manager itself — there's no reference-type
    /// owner here to hang it on the usual way (`MacFeedList` is a `View`
    /// struct), and the manager is stable across renders, unlike `self`.
    private func registerUndo(actionName: String, _ undo: @escaping () -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoManager) { _ in undo() }
        undoManager.setActionName(actionName)
    }

    /// Shared by every read/unread change below (row, group header, "Tout
    /// marquer comme lu") — registers the reverse toggle as this same
    /// action's undo, and that reverse toggle registers the original as its
    /// own undo in turn, so Edit > Annuler/Rétablir both keep working no
    /// matter how many times either is pressed.
    private func setReadState(for items: [LinkItem], to isRead: Bool, actionName: String) {
        for item in items {
            item.isRead = isRead
            // A link moved back to unread re-enters À lire, where the
            // excerpt is worth having again — see `RootView.markAsUnread`.
            if !isRead { item.excerptFetchAttempted = false }
        }
        persist()
        registerUndo(actionName: actionName) {
            self.setReadState(for: items, to: !isRead, actionName: actionName)
        }
    }

    private func markAsRead(_ items: [LinkItem], actionName: String = "Marquer lu") {
        setReadState(for: items, to: true, actionName: actionName)
    }

    /// Row context menu / leading swipe: read ↔ unread.
    private func toggleRead(_ item: LinkItem) {
        setReadState(for: [item], to: !item.isRead, actionName: item.isRead ? "Marquer non lu" : "Marquer lu")
    }

    private func togglePin(_ item: LinkItem) {
        item.isPinned.toggle()
        persist()
    }

    private func delete(_ items: [LinkItem]) {
        modelContext.deleteLinks(items)
        persist()
    }
}
