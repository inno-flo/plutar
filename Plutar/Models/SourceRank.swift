import Foundation
import SwiftData

/// Tracks how many links have ever been added for a given host — a
/// persistent, cumulative tally that powers the "most important sources"
/// ranking in the Lus view (iOS) / the Classement row (macOS). Unlike the live per-source link counts
/// shown elsewhere, this one does not shrink when links are deleted or
/// marked read; it only grows (or is explicitly reset to zero).
// `host` used to carry `@Attribute(.unique)` — dropped along with
// `LinkItem.id`'s, see the comment there: SwiftData+CloudKit doesn't
// support unique constraints. `bump(_:in:)`'s fetch-then-insert-or-update
// still keeps one row per host within a single call/context, but it can no
// longer prevent two *different* processes (the app and a share extension,
// or two CloudKit-synced devices) from each inserting their own row for the
// same brand-new host before either has synced — CloudKit has no
// server-side uniqueness either, so both rows can persist. `aggregated(_:)`
// below is the read-side fix: every place that displays the ranking merges
// same-host rows instead of assuming the fetched array is already
// collision-free the way the old `.unique` index guaranteed.
@Model
final class SourceRank {
    var host: String = ""
    var count: Int = 0

    init(host: String, count: Int = 0) {
        self.host = host
        self.count = count
    }

    /// Finds (or creates) the rank entry for `host` and bumps it by one.
    ///
    /// Fetches just this host's entry rather than every rank — not a
    /// database constraint (there is none any more, see the type-level
    /// comment above), just a lookup.
    static func bump(_ host: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<SourceRank>(predicate: #Predicate { $0.host == host })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.count += 1
        } else {
            context.insert(SourceRank(host: host, count: 1))
        }
    }

    /// One entry per host, ready to display — merges together any rows that
    /// ended up sharing the same host (see the type-level comment above)
    /// instead of assuming `ranks` is already collision-free. Sorted the
    /// same way the `@Query(sort: \SourceRank.count, order: .reverse)` this
    /// is fed from is (descending count), with host name as a deterministic
    /// tie-break so the order doesn't depend on fetch/merge order.
    static func aggregated(_ ranks: [SourceRank]) -> [(host: String, count: Int)] {
        var totals: [String: Int] = [:]
        for rank in ranks { totals[rank.host, default: 0] += rank.count }
        return totals
            .map { (host: $0.key, count: $0.value) }
            .sorted { a, b in a.count != b.count ? a.count > b.count : a.host < b.host }
    }

    /// Name shown for `host` in the ranking (iOS Lus ranking and macOS
    /// `MacSourceRankingView`) — the site's own name when known (see
    /// `LinkItem.displaySourceName(forHost:in:)`), else the domain with its
    /// suffix (".com", ".fr", ".net"…) dropped: "nytimes", not "nytimes.com".
    /// Elsewhere (the link cards' host line) the full domain is kept.
    static func displayName(forHost host: String, in items: [LinkItem]) -> String {
        let name = LinkItem.displaySourceName(forHost: host, in: items)
        if name != host { return name }
        return host.split(separator: ".").first.map(String.init) ?? host
    }
}
