import SwiftUI
import SwiftData

/// The standing "most shared sources" ranking — an all-time, cumulative
/// `SourceRank` tally, unlike the live per-source unread counts shown
/// elsewhere (it never shrinks when links are read or deleted). Shown when
/// the sidebar's "Classement" row, under Sources, is selected.
struct MacSourceRankingView: View {
    let sourceRanks: [SourceRank]
    /// Only consulted for `SourceRank.displayName` — a host has no name of its own
    /// on `SourceRank`, so this looks one up from any link that shares it.
    let allItems: [LinkItem]
    let theme: AppTheme
    let appFont: AppFont
    let effectiveBackground: Color

    @Environment(\.modelContext) private var modelContext
    /// Set instead of deleting immediately — same confirmation-gated
    /// pattern as `MacFeedList`'s own pending-delete state.
    @State private var hostPendingDelete: String?

    /// The 15 most-shared sources — merges any rows CloudKit sync left
    /// sharing the same host (see `SourceRank`'s own comment) instead of
    /// assuming `sourceRanks` is already collision-free, then keeps only
    /// the top 15 (already sorted descending by `aggregated`).
    private var ranked: [(host: String, count: Int)] {
        Array(SourceRank.aggregated(sourceRanks).prefix(15))
    }

    var body: some View {
        let ranked = self.ranked
        return Group {
            if ranked.isEmpty {
                QuietEmptyStateView(
                    theme: theme, appFont: appFont, icon: "chart.line.uptrend.xyaxis",
                    title: "Aucun classement",
                    text: "Le classement apparaîtra une fois des liens partagés."
                )
            } else {
                List {
                    // A normal row, not a real `Section` header — see
                    // `MacFeedList`'s own group header for why: List pins
                    // plain-style Section headers to the top while
                    // scrolling, which reads as UI stuck to the window
                    // rather than part of the list.
                    Text("Les 15 sources les plus partagées")
                        .font(appFont.font(size: 13, weight: .semibold))
                        .foregroundStyle(theme.ink(0.6))
                        .padding(.horizontal, 18)
                        // + the list's own row insets ≈ 22pt down to the
                        // first source name — same gap as iOS's `RootView`.
                        .padding(.bottom, 14)
                        .listRowSeparator(.hidden)

                    ForEach(Array(ranked.enumerated()), id: \.element.host) { index, rank in
                        rankRow(rank: index + 1, host: rank.host, count: rank.count)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
                // Rows are spaced by the list's own insets alone (no extra
                // vertical padding, no minimum row height) — half the gap
                // they used to have, same as iOS's `RootView`.
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
            }
        }
        .background(effectiveBackground)
        // Plain `navigationTitle`, not a custom `.principal` toolbar item
        // like `MacFeedList` uses for its own themed title — with no other
        // toolbar buttons alongside it here, a lone `.principal` item
        // renders as its own pill/button rather than plain text.
        .navigationTitle("Classement")
        .confirmationDialog(
            "Supprimer cette source du classement ?",
            isPresented: Binding(
                get: { hostPendingDelete != nil },
                set: { if !$0 { hostPendingDelete = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                if let host = hostPendingDelete { deleteRank(for: host) }
            }
        }
    }

    /// Removes every underlying `SourceRank` row for `host` — `ranked`
    /// already merges same-host rows for display (see `aggregated(_:)`), so
    /// there can be more than one to delete.
    private func deleteRank(for host: String) {
        for rank in sourceRanks where rank.host == host {
            modelContext.delete(rank)
        }
        // Logged rather than a bare `try?` — see `ModelContext.persist(_:)`.
        modelContext.persist()
    }

    private func rankRow(rank: Int, host: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                // Same as iOS's `RootView.sourceRankRow`: black in clair
                // themes (Cap Canaveral clair: the names' `title` color);
                // soir keeps its muted ink.
                .foregroundStyle(theme.isSoir ? theme.ink(0.4) : theme == .astronaute ? theme.title : .black)
                .frame(width: 22, alignment: .center)
            Text(SourceRank.displayName(forHost: host, in: allItems))
                .foregroundStyle(theme.isSoir ? theme.ink(0.5) : theme.title)
                .contextMenu {
                    Button("Supprimer cette source…", role: .destructive) {
                        hostPendingDelete = host
                    }
                }
            Spacer()
            Text("\(count)")
                .foregroundStyle(theme.ink(0.5))
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .padding(.horizontal, 18)
    }
}
