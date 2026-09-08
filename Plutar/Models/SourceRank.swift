import Foundation
import SwiftData

/// Tracks how many links have ever been added for a given host — a
/// persistent, cumulative tally that powers the "most important sources"
/// ranking in the Sources view. Unlike the live per-source link counts
/// shown elsewhere, this one does not shrink when links are deleted or
/// marked read; it only grows (or is explicitly reset to zero).
@Model
final class SourceRank {
    @Attribute(.unique) var host: String
    var count: Int

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
                // entry just created rather than inserting a duplicate — the
                // `.unique` constraint on `host` would collide on save.
                known[host] = created
            }
        }
    }
}
