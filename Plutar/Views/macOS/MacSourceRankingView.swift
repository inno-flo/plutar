import SwiftUI

/// The standing "most shared sources" ranking — an all-time, cumulative
/// `SourceRank` tally, unlike the live per-source unread counts shown
/// elsewhere (it never shrinks when links are read or deleted). Shown when
/// the sidebar's "Classement" row, under Sources, is selected.
struct MacSourceRankingView: View {
    let sourceRanks: [SourceRank]
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
        Group {
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
                        .listRowSeparator(.hidden)

                    ForEach(Array(ranked.enumerated()), id: \.element.host) { index, rank in
                        rankRow(rank: index + 1, host: rank.host, count: rank.count)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
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
        try? modelContext.save()
    }

    private func displayName(_ host: String) -> String {
        host.split(separator: ".").first.map(String.init) ?? host
    }

    private func rankRow(rank: Int, host: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .foregroundStyle(theme.ink(0.4))
                .frame(width: 22, alignment: .leading)
            Text(displayName(host))
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
        .padding(.vertical, 4)
    }
}
