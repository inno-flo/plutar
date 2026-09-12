import Foundation
import LinkPresentation
import SwiftData
import UIKit

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
        await enrichExcerpt(in: context, limit: limit)
    }

    /// Title (fallback replacement only) and preview image, via
    /// `LPMetadataProvider` — regardless of read state: cheap enough, and a
    /// freshly shared link is essentially always still unread by the time
    /// this runs anyway.
    private static func enrichTitleAndThumbnail(in context: ModelContext, limit: Int) async {
        let descriptor = FetchDescriptor<LinkItem>(
            predicate: #Predicate { $0.metadataFetched == false }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }
        for item in pending.prefix(limit) {
            await fetchTitleAndThumbnail(for: item)
        }
        try? context.save()
    }

    private static func fetchTitleAndThumbnail(for item: LinkItem) async {
        // Marked done up front, not after: a link that fails (dead URL, no
        // network, no metadata) should be left alone afterwards rather than
        // retried on every single launch.
        defer { item.metadataFetched = true }

        guard let url = URL(string: item.urlString) else { return }
        guard let meta = await fetchLinkMetadata(for: url) else { return }

        // Only replace the title if it's still one of the fallbacks
        // LinkItemFactory / ShareView used (the bare host, or the raw URL
        // when the source app supplied no title at all) — never overwrite a
        // title the user or the source app actually typed/provided.
        let isFallbackTitle = item.title == item.host || item.title == item.urlString
        if let title = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty, isFallbackTitle {
            item.title = title
        }
        if let provider = meta.imageProvider ?? meta.iconProvider,
           let fileName = await saveThumbnail(from: provider, id: item.id) {
            item.thumbnailFileName = fileName
            item.hasThumbnail = true
        }
    }

    /// The HTML meta-description fetch, restricted to links currently
    /// unread: the excerpt only shows up in Date/Sources (it feeds the
    /// Éditoriale layout), never in Lus, so there's nothing to gain fetching
    /// it for a link that's already been read. `RootView.markAsUnread(_:)`
    /// clears `excerptFetchAttempted` when a link moves back to unread, so
    /// it gets picked up here again.
    private static func enrichExcerpt(in context: ModelContext, limit: Int) async {
        let descriptor = FetchDescriptor<LinkItem>(
            predicate: #Predicate { $0.excerptFetchAttempted == false && $0.isRead == false }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }
        for item in pending.prefix(limit) {
            await fetchExcerpt(for: item)
        }
        try? context.save()
    }

    private static func fetchExcerpt(for item: LinkItem) async {
        defer { item.excerptFetchAttempted = true }

        guard let url = URL(string: item.urlString) else { return }
        guard let excerpt = await fetchMetaDescription(for: url), !excerpt.isEmpty else { return }
        item.excerpt = excerpt
    }

    /// `nonisolated`, deliberately: this is the actual slow part (a network
    /// round trip), and must run off the main actor so awaiting it doesn't
    /// pin the wait to the main thread. `.timeout` bounds a hung/slow host
    /// to the same 8 s cap as `fetchMetaDescription` below, rather than
    /// however long `LPMetadataProvider` would otherwise wait on its own.
    private nonisolated static func fetchLinkMetadata(for url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        return try? await provider.startFetchingMetadata(for: url)
    }

    /// `LPLinkMetadata` doesn't expose the page's meta description, so this
    /// pulls a capped prefix of the HTML itself and reads it out directly —
    /// enough to reach `<meta name="description">` /
    /// `<meta property="og:description">`, which live in `<head>`.
    /// `nonisolated` for the same reason as `fetchLinkMetadata` above.
    private nonisolated static func fetchMetaDescription(for url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let capped = data.prefix(65_536)
        guard let html = String(data: capped, encoding: .utf8)
            ?? String(data: capped, encoding: .isoLatin1)
        else {
            return nil
        }
        return metaDescription(in: html)
    }

    private nonisolated static let descriptionPatterns = [
        #"<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']*)["']"#,
        #"<meta[^>]+content=["']([^"']*)["'][^>]+property=["']og:description["']"#,
        #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["']"#,
        #"<meta[^>]+content=["']([^"']*)["'][^>]+name=["']description["']"#,
    ]

    private nonisolated static func metaDescription(in html: String) -> String? {
        let range = NSRange(html.startIndex..., in: html)
        for pattern in descriptionPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
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
    /// with `ModelContext` and doesn't need the main actor.
    private nonisolated static func saveThumbnail(from provider: NSItemProvider, id: UUID) async -> String? {
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        let image: UIImage? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        guard let image, let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        guard let directory = SharedStore.thumbnailsDirectoryURL() else { return nil }
        let fileName = "\(id.uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }
}
