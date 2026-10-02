import Foundation
import SwiftData

/// A single link collected via the share sheet.
// `id`/`host` used to carry `@Attribute(.unique)`. SwiftData's CloudKit
// integration doesn't support unique constraints (CloudKit has no
// server-side uniqueness enforcement), so both were dropped when the store
// moved to a CloudKit-backed `ModelConfiguration` — see `SharedStore`.
// Nothing in the codebase relied on the database itself rejecting a
// duplicate `id`/`host`; `SourceRank.bump` already does its own
// fetch-then-insert-or-update instead of depending on a DB-level collision.
@Model
final class LinkItem {
    var id: UUID = UUID()
    var title: String = ""
    var urlString: String = ""
    var host: String = ""
    /// Single-letter badge shown next to the host name.
    var initial: String = ""
    /// Hex color for the host badge (e.g. "#E8433D").
    var colorHex: String = "#000000"
    /// When the link was added to Plutar — drives the chronological sort and day grouping.
    var dateAdded: Date = Date.now
    /// The app the link was shared from — "Safari" when Safari ran
    /// `SharePreprocessor.js`, the generic "Partage" otherwise (see
    /// `SharedLinkExtraction`).
    var sourceApp: String = ""
    var excerpt: String = ""
    var isRead: Bool = false
    /// File name (not a full path — the App Group container can move
    /// between launches) of the downloaded preview image inside
    /// `SharedStore.thumbnailsDirectoryURL`. `nil` means no thumbnail was
    /// fetched (or the fetch found none) — the sole source of truth for
    /// whether this link has one.
    var thumbnailFileName: String?
    /// Whether `LinkMetadataEnricher` has already tried (successfully or
    /// not) to fill in title/thumbnail for this link.
    var metadataFetched: Bool = true
    /// Whether the HTML meta-description fetch (`LinkMetadataEnricher`'s
    /// excerpt step) has already been tried for this link. Kept separate
    /// from `metadataFetched` because it's also gated on `isRead` — the
    /// excerpt only matters in Date/Sources (it feeds the Éditoriale
    /// layout), not in Lus — so `RootView.markAsUnread(_:)` resets this to
    /// give a link moved back to unread a fresh try.
    var excerptFetchAttempted: Bool = true
    /// Pinned links stay in À lire even when tapped/opened or double-clicked
    /// (macOS) — a tap normally marks a link read, but a pinned one is
    /// meant to stick around until explicitly marked read or deleted. The
    /// per-date "Tout marquer comme lu" button also skips pinned links.
    var isPinned: Bool = false
    /// The site's own human-readable name (e.g. "The New York Times"),
    /// fetched from the page's `og:site_name`/`application-name` meta tag —
    /// `nil` until `LinkMetadataEnricher` has tried, or if the page had
    /// neither. Wherever the source is shown to the user, this is preferred
    /// over the bare `host` ("nytimes.com"); `host` itself stays untouched
    /// since it's still what grouping/ranking/dedup key on.
    var sourceName: String?
    /// Whether `LinkMetadataEnricher` has already tried (successfully or
    /// not) to fill in `sourceName` for this link. Separate from
    /// `metadataFetched`/`excerptFetchAttempted` and not gated on read
    /// state — unlike the excerpt, the source name is shown everywhere
    /// (Sources, Classement, every row), not just Date/Sources.
    var sourceNameFetchAttempted: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        host: String,
        initial: String,
        colorHex: String,
        dateAdded: Date,
        sourceApp: String,
        excerpt: String,
        isRead: Bool = false,
        thumbnailFileName: String? = nil,
        metadataFetched: Bool = true,
        excerptFetchAttempted: Bool = true,
        isPinned: Bool = false,
        sourceName: String? = nil,
        sourceNameFetchAttempted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.host = host
        self.initial = initial
        self.colorHex = colorHex
        self.dateAdded = dateAdded
        self.sourceApp = sourceApp
        self.excerpt = excerpt
        self.isRead = isRead
        self.thumbnailFileName = thumbnailFileName
        self.metadataFetched = metadataFetched
        self.excerptFetchAttempted = excerptFetchAttempted
        self.isPinned = isPinned
        self.sourceName = sourceName
        self.sourceNameFetchAttempted = sourceNameFetchAttempted
    }

    /// Hardcoded overrides for hosts whose own site blocks the plain HTTP
    /// fetch `LinkMetadataEnricher` uses to read `og:site_name` — DataDome,
    /// Cloudflare and similar anti-bot protections return an error page (or
    /// a flat 403) before any HTML ever reaches us, so no amount of retrying
    /// will ever pick up a real name for these. Add an entry here (matching
    /// the same normalized, "www."-stripped, lowercased form `host` is
    /// always stored in) only once a specific host is confirmed to need it
    /// — this is a manual list precisely because the automatic path already
    /// covers every site that doesn't block it.
    private static let knownSourceNames: [String: String] = [
        "nytimes.com": "The New York Times",
    ]

    /// The best name to show for `host` — `sourceName` once fetched, else
    /// the hardcoded override above, else the bare host as a last resort.
    static func displaySourceName(forHost host: String) -> String {
        knownSourceNames[host] ?? host
    }

    /// The name to show for this specific link — see the static overload
    /// above for the same fallback chain, with `sourceName` (this link's own
    /// fetched value) tried first.
    var displaySourceName: String {
        sourceName ?? LinkItem.displaySourceName(forHost: host)
    }

    /// The name to show for `host` as a whole (a Sources group, the macOS
    /// single-source title, the ranking): the site's real name once
    /// `LinkMetadataEnricher` has fetched it for at least one link from this
    /// host among `items`, else the static fallback chain above.
    static func displaySourceName(forHost host: String, in items: [LinkItem]) -> String {
        items.first { $0.host == host && $0.sourceName != nil }?.sourceName
            ?? displaySourceName(forHost: host)
    }
}
