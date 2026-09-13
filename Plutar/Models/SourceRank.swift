import Foundation
import SwiftData

/// Tracks how many links have ever been added for a given host — a
/// persistent, cumulative tally that powers the "most important sources"
/// ranking in the Sources view. Unlike the live per-source link counts
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
    static func bump(_ host: String, in context: ModelContext) {
        bump([host], in: context)
    }

    /// Bumps every host in `hosts` — repeats included, one increment each.
    ///
    /// Does a single fetch of the existing entries up front and resolves the
    /// rest in memory. The per-host version used to run its own predicate
    /// fetch, so seeding or regenerating the 200 demo links fired 200 round
    /// trips to the store on the main thread — at first launch, before the
    /// first frame was ever drawn. There are only ever a handful of hosts,
    /// so fetching them all at once is cheaper than one lookup.
    static func bump(_ hosts: [String], in context: ModelContext) {
        guard !hosts.isEmpty else { return }
        var known: [String: SourceRank] = [:]
        for rank in (try? context.fetch(FetchDescriptor<SourceRank>())) ?? [] {
            known[rank.host] = rank
        }
        for host in hosts {
            if let existing = known[host] {
                existing.count += 1
            } else {
                let created = SourceRank(host: host, count: 1)
                context.insert(created)
                // Kept so a repeat of the same host in `hosts` increments the
                // entry just created rather than inserting a duplicate within
                // this same call — not a database constraint (there is none
                // any more, see the type-level comment above), just this
                // function's own in-memory bookkeeping.
                known[host] = created
            }
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
        var order: [String] = []
        for rank in ranks {
            if totals[rank.host] == nil { order.append(rank.host) }
            totals[rank.host, default: 0] += rank.count
        }
        return order
            .map { (host: $0, count: totals[$0] ?? 0) }
            .sorted { a, b in a.count != b.count ? a.count > b.count : a.host < b.host }
    }
}
