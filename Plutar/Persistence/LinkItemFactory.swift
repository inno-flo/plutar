import Foundation
import SwiftData

/// Builds a real `LinkItem` from a URL shared via the iOS share sheet.
/// The demo data in `SeedData` hand-picks a color per host; a shared link
/// can arrive from any host, so its badge color is derived deterministically
/// from the host name instead — same host always gets the same color, no
/// lookup table to maintain.
enum LinkItemFactory {
    /// A handful of colors pulled from the mockup's source palette
    /// (`SeedData`'s `*Color` constants), reused here so real links land in
    /// the same visual family as the demo ones rather than introducing a
    /// second palette.
    private static let palette = [
        "#E8433D", "#6C5CE7", "#2F5FD0", "#222222",
        "#B01E24", "#FF8000", "#1F9D55", "#C2185B",
    ]

    private static func color(for host: String) -> String {
        let hash = host.unicodeScalars.reduce(into: 0) { $0 = $0 &* 31 &+ Int($1.value) }
        let index = abs(hash) % palette.count
        return palette[index]
    }

    /// Strips a leading "www." the way `SeedData.urlHost` does for the demo
    /// sources, so `theverge.com` links from either source group the same.
    private static func displayHost(from url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host.lowercased()
    }

    /// - Parameters:
    ///   - url: the shared link itself.
    ///   - title: page title supplied by the share extension host, if any.
    ///   - sourceApp: the app the share sheet was invoked from, when known.
    static func makeLinkItem(
        url: URL,
        title: String?,
        sourceApp: String = "Partage"
    ) -> LinkItem {
        let host = displayHost(from: url)
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LinkItem(
            title: (resolvedTitle?.isEmpty == false) ? resolvedTitle! : host,
            urlString: url.absoluteString,
            host: host,
            initial: String(host.first ?? "?").uppercased(),
            colorHex: color(for: host),
            dateAdded: Date(),
            sourceApp: sourceApp,
            excerpt: "",
            hasThumbnail: false,
            metadataFetched: false,
            excerptFetchAttempted: false
        )
    }

    /// Saves the link and bumps its host's cumulative rank, mirroring what
    /// `PlutarApp.seedIfNeeded()` does for the demo data — kept in one place
    /// so the app and the share extension can't drift on how a new link is
    /// recorded.
    @discardableResult
    static func save(url: URL, title: String?, sourceApp: String = "Partage", in context: ModelContext) throws -> LinkItem {
        let item = makeLinkItem(url: url, title: title, sourceApp: sourceApp)
        context.insert(item)
        SourceRank.bump(item.host, in: context)
        try context.save()
        return item
    }
}
