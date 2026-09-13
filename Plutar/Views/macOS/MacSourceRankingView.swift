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

    /// Merges any rows CloudKit sync left sharing the same host (see
    /// `SourceRank`'s own comment) instead of assuming `sourceRanks` is
    /// already collision-free.
    private var ranked: [(host: String, count: Int)] { SourceRank.aggregated(sourceRanks) }

    var body: some View {
        Group {
            if ranked.isEmpty {
                QuietEmptyStateView(
                    theme: theme, appFont: appFont, icon: "chart.bar.horizontal.page",
                    title: "Aucun classement",
                    text: "Le classement apparaîtra une fois des liens partagés."
                )
            } else {
                List {
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
            Spacer()
            Text("\(count)")
                .foregroundStyle(theme.ink(0.5))
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
    }
}
