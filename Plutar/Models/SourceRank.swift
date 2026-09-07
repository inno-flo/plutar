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
        let descriptor = FetchDescriptor<SourceRank>(
            predicate: #Predicate { $0.host == host }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.count += 1
        } else {
            context.insert(SourceRank(host: host, count: 1))
        }
    }
}
