import Foundation

/// One section of the feed — a day in Date/Lus, a host in Sources. Shared
/// between `RootView` (iOS) and `MacFeedList` (macOS).
///
/// `id` is deliberately *not* `label`. Two days a year apart both render as
/// "3 mars", so keying `ForEach` on the displayed text made them collide on
/// one identifier, which SwiftUI resolves by dropping or mis-animating rows.
/// In Sources the two are the same string (the host), which is why a
/// per-source expansion-state dictionary keyed on `id` round-trips
/// unchanged.
struct FeedGroup: Identifiable {
    let id: String
    let label: String
    let items: [LinkItem]
}

/// Pure grouping/labeling logic factored out of `RootView` so both iOS and
/// macOS group the same way without duplicating the day-bucketing/host-
/// ranking logic.
enum FeedGrouping {
    /// Only the links relevant to `mode` — unread ones for Date/Sources, read
    /// ones for Lus.
    static func visibleItems(_ allItems: [LinkItem], mode: FeedMode) -> [LinkItem] {
        mode == .read ? allItems.filter(\.isRead) : allItems.filter { !$0.isRead }
    }

    /// The groups a feed screen actually shows (`RootView`, `MacFeedList`) —
    /// `makeGroups`, except Lus bucketed by source instead of by day while
    /// its globe/calendar toggle (`DisplaySettingsKey.readGroupedBySource`)
    /// is on.
    static func groups(_ allItems: [LinkItem], mode: FeedMode, readGroupedBySource: Bool) -> [FeedGroup] {
        if mode == .read && readGroupedBySource {
            return makeSourceGroups(allItems.filter(\.isRead))
        }
        return makeGroups(allItems, mode: mode)
    }

    /// Buckets `visibleItems(allItems, mode:)` into day groups (Date/Lus) or
    /// host groups (Sources), in the same order `RootView`'s "groups" used
    /// to compute: days newest-first (matching `allItems`' own sort), hosts
    /// by descending live count then alphabetically.
    static func makeGroups(_ allItems: [LinkItem], mode: FeedMode) -> [FeedGroup] {
        let list = visibleItems(allItems, mode: mode)
        switch mode {
        case .chrono, .read:
            let calendar = Calendar.current
            var order: [Date] = []
            var buckets: [Date: [LinkItem]] = [:]
            for item in list {
                let day = calendar.startOfDay(for: item.dateAdded)
                if buckets[day] == nil { buckets[day] = []; order.append(day) }
                buckets[day]!.append(item)
            }
            return order.map { day in
                FeedGroup(id: dayKeyFormatter.string(from: day),
                          label: dayLabel(day),
                          items: buckets[day]!)
            }
        case .source:
            return makeSourceGroups(list)
        }
    }

    /// Buckets an arbitrary item list by host, descending by count then
    /// alphabetically — the same ranking `makeGroups(mode: .source)` uses,
    /// factored out so `MacFeedList` can group Lus by source (instead of by
    /// day) without going through `visibleItems`' unread-only filter.
    static func makeSourceGroups(_ items: [LinkItem]) -> [FeedGroup] {
        let byHost = Dictionary(grouping: items, by: \.host)
        let hosts = byHost.keys.sorted { a, b in
            let ca = byHost[a]?.count ?? 0, cb = byHost[b]?.count ?? 0
            return ca != cb ? ca > cb : a < b
        }
        return hosts.map { host in
            let hostItems = byHost[host] ?? []
            // The site's real name once `LinkMetadataEnricher` has fetched
            // it for at least one link from this host, else `LinkItem`'s own
            // hardcoded override for sites that block that fetch, else the
            // bare host ("nytimes.com").
            let label = LinkItem.displaySourceName(forHost: host, in: hostItems)
            return FeedGroup(id: host, label: label, items: hostItems)
        }
    }

    /// Collision-free identity for a day bucket — unlike the displayed
    /// label, which repeats from one year to the next. See `FeedGroup`.
    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM"
        return f
    }()

    static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        // Only the first letter gets a capital, French-style — "3 mars",
        // not "3 Mars" (`.capitalized` would capitalize every word).
        let raw = dayFormatter.string(from: day)
        let formatted = raw.prefix(1).uppercased() + raw.dropFirst()
        // French uses the ordinal "1er" for the first of the month, not "1"
        // — e.g. "1er avril", not "1 avril". Applied after the capitalization
        // above so it stays "1er", not "1Er".
        let label = calendar.component(.day, from: day) == 1
            ? formatted.replacingOccurrences(of: "1 ", with: "1er ")
            : formatted
        // Links accumulate for years in a read-later app, so a bare "3 mars"
        // would read identically for two different years. Shown only when it
        // isn't the current year, so the common case stays short.
        let year = calendar.component(.year, from: day)
        guard year != calendar.component(.year, from: Date()) else { return label }
        return "\(label) \(year)"
    }

    static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM"
        return f
    }()

    /// "Septembre 2026" — always with the year, unlike `dayLabel`. Used for
    /// Lus's month separators (`RootView`/`MacFeedList`), shown between day
    /// groups when they span more than one calendar month.
    static func monthLabel(for day: Date) -> String {
        let raw = monthFormatter.string(from: day)
        let formatted = raw.prefix(1).uppercased() + raw.dropFirst()
        return "\(formatted) \(Calendar.current.component(.year, from: day))"
    }

    /// The "yyyy-MM" prefix of a day-group id (`dayKeyFormatter`'s own
    /// "yyyy-MM-dd" format) — cheap month identity without reparsing the
    /// date, since day-group ids are already this format zero-padded and
    /// lexically sortable.
    static func monthKey(fromDayGroupID id: String) -> String {
        String(id.prefix(7))
    }

    /// Ids of the first group in each calendar month within `dayGroups`
    /// (already day-grouped, newest first) — empty unless they actually
    /// span more than one month. Shared by `RootView` (iOS) and
    /// `MacFeedList` (macOS) for Lus's own month-separator row.
    static func monthSeparatorGroupIDs(_ dayGroups: [FeedGroup]) -> Set<String> {
        let monthKeys = dayGroups.map { monthKey(fromDayGroupID: $0.id) }
        guard Set(monthKeys).count > 1 else { return [] }
        var ids: Set<String> = []
        var previousMonthKey: String?
        for (group, key) in zip(dayGroups, monthKeys) {
            if key != previousMonthKey { ids.insert(group.id) }
            previousMonthKey = key
        }
        return ids
    }
}

extension Set {
    /// Inserts `member` if absent, removes it if present — the expand/
    /// collapse toggle behind every per-group chevron (`RootView`,
    /// `MacFeedList`).
    mutating func toggle(_ member: Element) {
        if remove(member) == nil { insert(member) }
    }
}
