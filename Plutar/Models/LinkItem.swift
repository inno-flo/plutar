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
        isRead: Bool = false
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
    }
}
