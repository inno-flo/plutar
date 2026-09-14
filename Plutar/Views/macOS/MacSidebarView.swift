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
/// No settings affordance here — `Settings` (Cmd+,) is already reachable
/// from the app menu on macOS, so a redundant sidebar button was removed.
struct MacSidebarView: View {
    @Binding var selection: SidebarSelection?
    let allItems: [LinkItem]

    @State private var sourcesExpanded = true

    private var unreadCount: Int { allItems.lazy.filter { !$0.isRead }.count }
    private var readCount: Int { allItems.lazy.filter { $0.isRead }.count }

    /// Alphabetical, unlike `FeedGrouping.makeGroups`'s own count-first sort
    /// (which suits a merged feed screen, not a sidebar list of sources).
    private var sourceGroups: [FeedGroup] {
        FeedGrouping.makeGroups(allItems, mode: .source)
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        List(selection: $selection) {
            Section("Liens partagés") {
                sidebarRow(label: "À lire", systemImage: "calendar", count: unreadCount)
                    .tag(SidebarSelection.date)
                sidebarRow(label: "Lus", systemImage: "checkmark.circle", count: readCount)
                    .tag(SidebarSelection.read)
            }
            DisclosureGroup(isExpanded: $sourcesExpanded) {
                sidebarRow(label: "Classement", systemImage: "chart.bar.horizontal.page")
                    .tag(SidebarSelection.ranking)
                ForEach(sourceGroups) { group in
                    sidebarRow(
                        label: group.label,
                        systemImage: "newspaper",
                        count: group.items.count
                    )
                    .tag(SidebarSelection.source(group.id))
                }
            } label: {
                Label {
                    HStack {
                        Text("Sources")
                        Spacer()
                        // Was the unread count — redundant with "À lire"'s
                        // own count just above — replaced with an explicit
                        // collapse/expand control in that same trailing spot.
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                sourcesExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: sourcesExpanded ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(sourcesExpanded ? "Réduire" : "Développer")
                    }
                } icon: {
                    Image(systemName: "globe")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Plutar")
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
