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
    /// The app the link was shared from (simulated for now: Safari, Mastodon, Notes…).
    var sourceApp: String = ""
    var excerpt: String = ""
    var isRead: Bool = false
    /// File name (not a full path — the App Group container can move
    /// between launches) of the downloaded preview image inside
    /// `SharedStore.thumbnailsDirectoryURL()`. `nil` means no thumbnail was
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
        isPinned: Bool = false
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
    }
}
