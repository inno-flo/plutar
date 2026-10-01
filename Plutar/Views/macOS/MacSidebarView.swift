import SwiftUI

/// The Mac window's sidebar (HIG "Sidebars" pattern) — replaces the old
/// top-strip `TabView`. "Date" and "Lus" are plain rows; "Sources" is a
/// disclosure group listing every host alphabetically, each with its own
/// unread count, so a source is its own navigation destination instead of
/// one row inside a shared, expand-per-source "Sources" screen.
///
/// "Classement" is its own row inside the Sources group — the standing,
/// all-time `SourceRank` tally (see `MacSourceRankingView`), not one of the
/// individual per-host rows below it.
///
/// No settings button here — `Settings` (Cmd+,) is already reachable from
/// the app menu on macOS, so a redundant sidebar button was removed. The
/// one settings-like affordance kept is the row of 4 theme dots pinned to
/// the bottom, a quick way to switch theme without opening Settings.
struct MacSidebarView: View {
    @Binding var selection: SidebarSelection?
    let allItems: [LinkItem]
    /// The theme actually displayed (already resolved against Apparence) —
    /// decides whether the dots below show the light or the nuit variants.
    let theme: AppTheme
    /// Overrides the system's own sidebar material when non-nil.
    let backgroundColor: Color?
    /// Called with the exact variant whose dot was clicked; the caller owns
    /// storing it (and Apparence), see `MacRootView.pickTheme`.
    let onPickTheme: (AppTheme) -> Void

    @State private var sourcesExpanded = true
    /// Toggled by the "Sources" row's own sort button — alphabetical
    /// (`sourceGroups`' original default) when true, ascending link count
    /// when false. "Classement" itself isn't affected — it's a fixed first
    /// row in the `DisclosureGroup`, not part of `sourceGroups`.
    @State private var sourcesSortedAlphabetically = true

    /// Leading inset that lines the dots' left edge up with the "Sources"
    /// disclosure chevron above them. An estimate of the sidebar's own
    /// row-content inset — SwiftUI doesn't expose the chevron's x position.
    private static let dotsLeadingInset: CGFloat = 10

    /// SF Symbol for a source's sidebar row — a video icon for YouTube hosts
    /// and a waveform for Spotify and Apple Music hosts (matched by
    /// substring, so `www.youtube.com`, `m.youtube.com`, `open.spotify.com`,
    /// … all count); the generic newspaper everywhere else.
    private static func sourceIcon(forHost host: String) -> String {
        let host = host.lowercased()
        if host.contains("youtube.com") { return "play.rectangle" }
        if host.contains("spotify.com") || host.contains("music.apple.com") { return "waveform" }
        return "newspaper"
    }

    /// One dot per theme family, in the Settings grid's order — the light
    /// variants' colors, or the nuit variants' while a nuit theme is active.
    private var quickThemes: [AppTheme] {
        AppTheme.selectable
            .filter { !$0.isSoir }
            .map { theme.isSoir ? $0.soirVariant : $0 }
    }

    private var unreadCount: Int { allItems.lazy.filter { !$0.isRead }.count }
    private var readCount: Int { allItems.lazy.filter { $0.isRead }.count }

    /// Alphabetical by default, unlike `FeedGrouping.makeGroups`'s own
    /// count-first sort (which suits a merged feed screen, not a sidebar
    /// list of sources) — or descending link count (most-shared first),
    /// toggled via the "Sources" row's sort button
    /// (`sourcesSortedAlphabetically`).
    private var sourceGroups: [FeedGroup] {
        let groups = FeedGrouping.makeGroups(allItems, mode: .source)
        if sourcesSortedAlphabetically {
            return groups.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        return groups.sorted { a, b in
            a.items.count != b.items.count
                ? a.items.count > b.items.count
                : a.label.localizedStandardCompare(b.label) == .orderedAscending
        }
    }

    var body: some View {
        List(selection: $selection) {
            Section("Liens partagés") {
                sidebarRow(label: "À lire", systemImage: "list.bullet.clipboard", count: unreadCount)
                    .tag(SidebarSelection.date)
                sidebarRow(label: "Lus", systemImage: "checkmark.circle", count: readCount)
                    .tag(SidebarSelection.read)
            }
            DisclosureGroup(isExpanded: $sourcesExpanded) {
                sidebarRow(label: "Classement", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(SidebarSelection.ranking)
                ForEach(sourceGroups) { group in
                    sidebarRow(
                        label: group.label,
                        // `group.id` — the real host — not `group.label`,
                        // which is the site's pretty name once fetched
                        // ("The Verge") and wouldn't match these substrings.
                        systemImage: Self.sourceIcon(forHost: group.id),
                        count: group.items.count
                    )
                    .tag(SidebarSelection.source(group.id))
                }
            } label: {
                // A click anywhere on this label toggles `sourcesExpanded`
                // via `DisclosureGroup`'s own built-in behavior — no
                // separate button/chevron needed. The sort `Button` below
                // still takes its own taps first (SwiftUI routes a tap to
                // the innermost interactive control), so it doesn't also
                // collapse/expand the group.
                HStack {
                    Label("Sources", systemImage: "globe.fill")
                    Spacer()
                    Button {
                        sourcesSortedAlphabetically.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .help("Trier par nom ou par nombre")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(backgroundColor == nil ? .automatic : .hidden)
        .background {
            if let backgroundColor {
                backgroundColor.ignoresSafeArea()
            }
        }
        .navigationTitle("Plutar")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                ForEach(quickThemes) { t in
                    themeDot(t)
                }
            }
            .padding(.leading, Self.dotsLeadingInset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The active theme family gets a ring around its dot (drawn outside the
    /// dot's own frame via negative padding, so it doesn't shift the row).
    private func themeDot(_ t: AppTheme) -> some View {
        Button {
            onPickTheme(t)
        } label: {
            Circle()
                .fill(t.dotColor)
                .frame(width: 14, height: 14)
                .overlay {
                    if t.lightVariant == theme.lightVariant {
                        Circle().stroke(Color.primary.opacity(0.7), lineWidth: 1.5).padding(-3)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("Activer le thème \(t.label)")
        .accessibilityLabel("Activer le thème \(t.label)")
    }

    /// `count` is `nil` for "Classement" — it has no live link count of its
    /// own to show, unlike every other row here.
    private func sidebarRow(label: String, systemImage: String, count: Int? = nil) -> some View {
        Label {
            HStack {
                Text(label)
                if let count {
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
