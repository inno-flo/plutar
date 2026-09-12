import Foundation
import SwiftData

/// A single link collected via the share sheet (or, for now, seeded as demo data).
@Model
final class LinkItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var urlString: String
    var host: String
    /// Single-letter badge shown next to the host name.
    var initial: String
    /// Hex color for the host badge (e.g. "#E8433D").
    var colorHex: String
    /// When the link was added to Plutar — drives the chronological sort and day grouping.
    var dateAdded: Date
    /// The app the link was shared from (simulated for now: Safari, Mastodon, Notes…).
    var sourceApp: String
    var excerpt: String
    var hasThumbnail: Bool
    var isRead: Bool
    /// File name (not a full path — the App Group container can move
    /// between launches) of the downloaded preview image inside
    /// `SharedStore.thumbnailsDirectoryURL()`, when `hasThumbnail` came from
    /// a real fetch rather than demo data.
    var thumbnailFileName: String?
    /// Whether `LinkMetadataEnricher` has already tried (successfully or
    /// not) to fill in title/thumbnail for this link. Demo links are seeded
    /// with this already `true` so they're never picked up.
    var metadataFetched: Bool
    /// Whether the HTML meta-description fetch (`LinkMetadataEnricher`'s
    /// excerpt step) has already been tried for this link. Kept separate
    /// from `metadataFetched` because it's also gated on `isRead` — the
    /// excerpt only matters in Date/Sources (it feeds the Éditoriale
    /// layout), not in Lus — so `RootView.markAsUnread(_:)` resets this to
    /// give a link moved back to unread a fresh try.
    var excerptFetchAttempted: Bool

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
        hasThumbnail: Bool,
        isRead: Bool = false,
        thumbnailFileName: String? = nil,
        metadataFetched: Bool = true,
        excerptFetchAttempted: Bool = true
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
        self.hasThumbnail = hasThumbnail
        self.isRead = isRead
        self.thumbnailFileName = thumbnailFileName
        self.metadataFetched = metadataFetched
        self.excerptFetchAttempted = excerptFetchAttempted
    }
}
