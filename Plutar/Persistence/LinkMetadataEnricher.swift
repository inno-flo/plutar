import Foundation
import LinkPresentation
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Fills in what the share extension couldn't get from the source app:
/// a real title (in place of the host-name fallback), an excerpt, and a
/// preview image — by fetching the link itself, the way a browser's link
/// preview does. Runs in the main app only (network + image decoding don't
/// fit the extension's short execution budget), triggered from
/// `PlutarApp` whenever the app becomes active.
// `ModelContext.mainContext` — the only context this ever runs on — is only
// safe to touch from the main actor. Everything here that reads/writes
// `context` or a `LinkItem` is pinned to `@MainActor` for that reason; the
// actual slow part of each step (the network call inside
// `fetchLinkMetadata`/`fetchMetaDescription`, plain nonisolated `async`
// functions below) still runs off the main thread — awaiting a nonisolated
// async function from `@MainActor` code hops off it for the call and back
// once it returns, so the fetch itself never blocks the UI. Previously
// nothing here was actor-pinned, so after the first `await` execution could
// resume on a background thread while still mutating `LinkItem`/
// `ModelContext` — the likely cause of a freeze-then-crash observed in
// testing, with a handful of links left half-enriched once the app relaunched.
@MainActor
enum LinkMetadataEnricher {
    /// Processes a handful of not-yet-enriched links per call rather than
    /// every pending one at once, so a burst of shared links (or a cold
    /// start with several still pending) doesn't fire a pile of concurrent
    /// network requests the moment the app opens.
    static func enrichPendingLinks(in context: ModelContext, limit: Int = 8) async {
        await enrichTitleAndThumbnail(in: context, limit: limit)
        await enrichFromHTML(in: context, limit: limit)
        await redownloadMissingThumbnails(in: context, limit: limit)
    }

    /// Up to `limit` links matching `predicate` — `fetchLimit` rather than
    /// fetching every pending link and keeping only a prefix.
    private static func pending(_ predicate: Predicate<LinkItem>, in context: ModelContext, limit: Int) -> [LinkItem] {
        var descriptor = FetchDescriptor<LinkItem>(predicate: predicate)
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Title (fallback replacement only) and preview image, via
    /// `LPMetadataProvider` — regardless of read state: cheap enough, and a
    /// freshly shared link is essentially always still unread by the time
    /// this runs anyway.
    private static func enrichTitleAndThumbnail(in context: ModelContext, limit: Int) async {
        let items = pending(#Predicate { $0.metadataFetched == false }, in: context, limit: limit)
        guard !items.isEmpty else { return }
        for item in items {
            await fetchTitleAndThumbnail(for: item)
        }
        context.persist()
    }

    private static func fetchTitleAndThumbnail(for item: LinkItem) async {
        // Marked done up front, not after: a link that fails (dead URL, no
        // network, no metadata) should be left alone afterwards rather than
        // retried on every single launch.
        defer { item.metadataFetched = true }

        guard let url = URL(string: item.urlString) else { return }
        guard let meta = await fetchLinkMetadata(for: url) else {
            // Was silent — a site that blocks non-browser fetches (bot
            // protection like DataDome/Cloudflare, a paywall, geo-blocking)
            // left no trace anywhere, and since `metadataFetched` above is
            // set unconditionally, the link is stuck with no thumbnail
            // forever with nothing in the console explaining why.
            PlutarLog.store.notice("LinkMetadataEnricher: fetchLinkMetadata returned nil for \(item.host, privacy: .public)")
            return
        }

        // Only replace the title if it's still one of the fallbacks
        // LinkItemFactory used (the bare host, or the raw URL
        // when the source app supplied no title at all) — never overwrite a
        // title the user or the source app actually typed/provided.
        let isFallbackTitle = item.title == item.host || item.title == item.urlString
        if let title = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty, isFallbackTitle {
            item.title = title
        }
        if let fileName = await saveThumbnail(from: meta, id: item.id) {
            item.thumbnailFileName = fileName
        } else {
            PlutarLog.store.notice("LinkMetadataEnricher: no image/icon saved for \(item.host, privacy: .public)")
        }
    }

    /// The two things only the page's own HTML has, read from one shared
    /// fetch per link — this used to be two separate passes, each
    /// downloading the same page on its own:
    ///
    /// - The site's own human-readable name (`og:site_name`/
    ///   `application-name` meta tags), regardless of read state — unlike
    ///   the excerpt, it's shown everywhere a source is named (row, Sources
    ///   group header, Classement), not just Date/Sources. Not gated on
    ///   `metadataFetched` either, so a site blocked for
    ///   `LPMetadataProvider` (`fetchTitleAndThumbnail`'s DataDome-style
    ///   failures, see its own comment) still gets a chance here, via a
    ///   plain HTTP fetch instead.
    /// - The meta description, restricted to links currently unread: the
    ///   excerpt only shows up in Date/Sources (it feeds the Éditoriale
    ///   layout), never in Lus, so there's nothing to gain fetching it for a
    ///   link that's already been read. `RootView.markAsUnread(_:)` clears
    ///   `excerptFetchAttempted` when a link moves back to unread, so it gets
    ///   picked up here again.
    private static func enrichFromHTML(in context: ModelContext, limit: Int) async {
        let items = pending(
            #Predicate { $0.sourceNameFetchAttempted == false || ($0.excerptFetchAttempted == false && $0.isRead == false) },
            in: context, limit: limit
        )
        guard !items.isEmpty else { return }
        for item in items {
            await fetchFromHTML(for: item)
        }
        context.persist()
    }

    private static func fetchFromHTML(for item: LinkItem) async {
        // `LinkItem.displaySourceName(forHost:)` already covers this host
        // with a hardcoded name that wins over any fetched one — nothing to
        // gain from requesting its name (often an always-failing request).
        let needsName = !item.sourceNameFetchAttempted
            && LinkItem.displaySourceName(forHost: item.host) == item.host
        let needsExcerpt = !item.excerptFetchAttempted && !item.isRead
        // Each marked done up front, same reasoning as `metadataFetched`.
        defer {
            item.sourceNameFetchAttempted = true
            if needsExcerpt { item.excerptFetchAttempted = true }
        }

        guard needsName || needsExcerpt,
              let url = URL(string: item.urlString),
              let html = await fetchHTML(for: url)
        else { return }
        if needsName, let name = firstMatch(siteNameRegexes, in: html) {
            item.sourceName = name
        }
        if needsExcerpt, let excerpt = firstMatch(descriptionRegexes, in: html) {
            item.excerpt = excerpt
        }
    }

    /// `metadataFetched`/`thumbnailFileName` sync via CloudKit like any other
    /// `LinkItem` field, but the JPEG itself lives only in the App Group
    /// container of whichever device actually fetched it (see
    /// `thumbnailFileName`'s doc comment on `LinkItem`) — it's never part of
    /// the synced record. A link enriched on another device therefore
    /// arrives here already marked done, with a `thumbnailFileName` that
    /// resolves to nothing on disk locally, and Détaillée/Éditoriale (the
    /// two layouts that actually render a thumbnail) show a blank gap where
    /// it should be. This re-downloads just the image for those — title and
    /// excerpt, already correct from the other device, are left alone.
    private static func redownloadMissingThumbnails(in context: ModelContext, limit: Int) async {
        let descriptor = FetchDescriptor<LinkItem>(
            predicate: #Predicate { $0.thumbnailFileName != nil }
        )
        guard let candidates = try? context.fetch(descriptor) else { return }
        let missing = candidates.filter { item in
            guard let fileName = item.thumbnailFileName else { return false }
            return !thumbnailFileExists(fileName)
        }
        guard !missing.isEmpty else { return }
        for item in missing.prefix(limit) {
            guard let url = URL(string: item.urlString),
                  let meta = await fetchLinkMetadata(for: url),
                  let fileName = await saveThumbnail(from: meta, id: item.id)
            else { continue }
            item.thumbnailFileName = fileName
        }
        context.persist()
    }

    private nonisolated static func thumbnailFileExists(_ fileName: String) -> Bool {
        guard let directory = SharedStore.thumbnailsDirectoryURL else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
    }

    /// `nonisolated`, deliberately: this is the actual slow part (a network
    /// round trip), and must run off the main actor so awaiting it doesn't
    /// pin the wait to the main thread. `.timeout` bounds a hung/slow host
    /// to the same 8 s cap as `fetchHTML` below, rather than
    /// however long `LPMetadataProvider` would otherwise wait on its own.
    private nonisolated static func fetchLinkMetadata(for url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        return try? await provider.startFetchingMetadata(for: url)
    }

    /// `LPLinkMetadata` doesn't expose the page's meta description (or its
    /// site name), so this pulls a capped prefix of the HTML itself and
    /// reads it out directly — enough to reach whatever's in `<head>`.
    /// `nonisolated` for the same reason as `fetchLinkMetadata` above.
    private nonisolated static func fetchHTML(for url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let capped = data.prefix(65_536)
        return String(data: capped, encoding: .utf8)
            ?? String(data: capped, encoding: .isoLatin1)
    }

    /// Both orderings of one `<meta>` tag's attributes (`property=… content=…`
    /// and `content=… property=…`), compiled once per process rather than on
    /// every match.
    private nonisolated static func metaTagRegexes(_ tags: [(attribute: String, value: String)]) -> [NSRegularExpression] {
        tags.flatMap { tag in [
            #"<meta[^>]+\#(tag.attribute)=["']\#(tag.value)["'][^>]+content=["']([^"']*)["']"#,
            #"<meta[^>]+content=["']([^"']*)["'][^>]+\#(tag.attribute)=["']\#(tag.value)["']"#,
        ] }
        .compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    private nonisolated static let descriptionRegexes = metaTagRegexes([
        ("property", "og:description"),
        ("name", "description"),
    ])

    /// Tried in this order: `og:site_name` is the standard Open Graph tag
    /// for exactly this ("The New York Times", "Le Monde", …); Apple's own
    /// `apple-mobile-web-app-title` and the generic `application-name` are
    /// fallbacks some sites use instead.
    private nonisolated static let siteNameRegexes = metaTagRegexes([
        ("property", "og:site_name"),
        ("name", "apple-mobile-web-app-title"),
        ("name", "application-name"),
    ])

    private nonisolated static func firstMatch(_ regexes: [NSRegularExpression], in html: String) -> String? {
        let range = NSRange(html.startIndex..., in: html)
        for regex in regexes {
            guard let match = regex.firstMatch(in: html, range: range), match.numberOfRanges > 1,
                  let group = Range(match.range(at: 1), in: html)
            else {
                continue
            }
            let value = decodeHTMLEntities(String(html[group]).trimmingCharacters(in: .whitespacesAndNewlines))
            if !value.isEmpty { return value }
        }
        return nil
    }

    private nonisolated static let htmlEntities: [String: String] = [
        "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
    ]

    private nonisolated static func decodeHTMLEntities(_ string: String) -> String {
        htmlEntities.reduce(string) { result, entity in
            result.replacingOccurrences(of: entity.key, with: entity.value)
        }
    }

    /// `nonisolated`: the image load/encode/write below has nothing to do
    /// with `ModelContext` and doesn't need the main actor. Takes the page's
    /// preview image, else its icon.
    private nonisolated static func saveThumbnail(from meta: LPLinkMetadata, id: UUID) async -> String? {
        guard let provider = meta.imageProvider ?? meta.iconProvider,
              provider.canLoadObject(ofClass: PlatformImage.self)
        else { return nil }
        let image: PlatformImage? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: PlatformImage.self) { object, _ in
                continuation.resume(returning: object as? PlatformImage)
            }
        }
        guard let image, let data = image.plutarJPEGData(compressionQuality: 0.7) else { return nil }
        guard let directory = SharedStore.thumbnailsDirectoryURL else { return nil }
        let fileName = "\(id.uuidString).jpg"
        guard (try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)) != nil else { return nil }
        return fileName
    }
}
