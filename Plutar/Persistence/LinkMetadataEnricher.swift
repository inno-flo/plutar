import Foundation
import LinkPresentation
import Network
import Observation
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
/// Bumped each time a thumbnail file lands on disk. A row can't notice that on
/// its own: it reads the file during `body`, and re-assigning an unchanged
/// `thumbnailFileName` (the name is the same before and after a download) may
/// not invalidate it — so `LinkRowView` reads `revision` too, and redraws.
@MainActor @Observable
final class ThumbnailEvents {
    static let shared = ThumbnailEvents()
    var revision = 0
}

@MainActor
enum LinkMetadataEnricher {
    /// Processes a handful of not-yet-enriched links per call rather than
    /// every pending one at once, so a burst of shared links (or a cold
    /// start with several still pending) doesn't fire a pile of concurrent
    /// network requests the moment the app opens.
    static func enrichPendingLinks(in context: ModelContext, limit: Int = 8) async {
        // One pass at a time: the triggers overlap (launch, foreground, remote
        // change, manual refresh), and two passes interleaving at their awaits
        // fetched the same pending links twice. A trigger that arrives
        // mid-pass asks for one more pass instead of starting its own.
        guard !isEnriching else {
            passRequestedWhileBusy = true
            return
        }
        isEnriching = true
        defer { isEnriching = false }
        repairLegacyExtractionIfNeeded(in: context)
        repeat {
            passRequestedWhileBusy = false
            // Offline, every fetch below would fail and mark its link as
            // tried for good — leave everything pending for the next pass.
            if await isOnline() {
                await enrichTitleAndThumbnail(in: context, limit: limit)
                await enrichFromHTML(in: context, limit: limit)
                // Eight at a time was enough for the odd synced-in link, but a freshly
                // installed device has *every* image to fetch and would need dozens of
                // launches: same pass as after a restore, in parallel, capped per call.
                await regenerateMissingThumbnails(in: context, limit: 40)
            }
            // Everything above has been persisted by now: the rollback a
            // remote change asked for mid-pass can no longer lose anything.
            if rollbackDeferred {
                rollbackDeferred = false
                context.rollback()
            }
        } while passRequestedWhileBusy
    }

    private static var isEnriching = false
    private static var passRequestedWhileBusy = false
    private static var rollbackDeferred = false

    /// The forced refetch `StoreLifecycle` wants after a CloudKit remote change
    /// (see its comment) — `context.rollback()`, except while a pass is
    /// running: a pass sets titles, thumbnails and its "tried" flags across
    /// several awaits before saving them, and a rollback landing in between
    /// threw that work away (to be downloaded again on the next pass). It is
    /// done at the end of the pass instead.
    static func refetchAfterRemoteChange(in context: ModelContext) {
        if isEnriching {
            rollbackDeferred = true
        } else {
            context.rollback()
        }
    }

    private static let legacyExtractionRepairedKey = "LinkMetadataEnricher.legacyExtractionRepaired.v1"

    /// One-time repair, per device, of what the old HTML extraction left
    /// behind: excerpts and site names cut at their first apostrophe
    /// ("L" for "L'Équipe"), accents decoded as Latin-1 ("Ã©"), entities left
    /// as written ("&#039;"). Those links are marked as already tried, so
    /// nothing would ever read their page again; this puts them back in
    /// `enrichFromHTML`'s queue, which then works through them a few per pass.
    ///
    /// - Unread links: excerpt and site name both (a cut excerpt can't be
    ///   told from a short one, so all of them).
    /// - Read links: only a site name that looks damaged — their excerpt is
    ///   never shown, and re-reading every read link's page isn't worth it.
    ///
    /// The stored values stay in place until a fetch replaces them, so a page
    /// that no longer answers loses nothing.
    private static func repairLegacyExtractionIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyExtractionRepairedKey),
              // The throwaway fallback store says nothing about the real one.
              !context.container.configurations.contains(where: \.isStoredInMemoryOnly),
              let items = try? context.fetch(FetchDescriptor<LinkItem>())
        else { return }

        var requeued = 0
        for item in items {
            var changed = false
            if !item.isRead {
                if item.excerptFetchAttempted { item.excerptFetchAttempted = false; changed = true }
                if item.sourceNameFetchAttempted { item.sourceNameFetchAttempted = false; changed = true }
            } else if item.sourceNameFetchAttempted, let name = item.sourceName, looksDamaged(name) {
                item.sourceNameFetchAttempted = false
                changed = true
            }
            if changed { requeued += 1 }
        }
        // Flag set only once the reset is safely stored — otherwise it is
        // simply tried again on the next pass.
        guard context.persist() else { return }
        defaults.set(true, forKey: legacyExtractionRepairedKey)
        PlutarLog.store.notice("Legacy extraction repair: \(requeued) link(s) queued for a new HTML fetch")
    }

    /// A site name the old extraction most likely got wrong: cut at an
    /// apostrophe (one or two characters left), UTF-8 read as Latin-1, or an
    /// entity left undecoded.
    private nonisolated static func looksDamaged(_ text: String) -> Bool {
        text.count <= 2 || text.contains("Ã") || text.contains("â€")
            || decodeHTMLEntities(text) != text
    }

    /// Whether the device currently has a usable network path.
    private nonisolated static func isOnline() async -> Bool {
        for await path in NWPathMonitor() { return path.status == .satisfied }
        return true
    }

    /// Whether `error` (or an error it wraps) says the network itself was
    /// missing — as opposed to the site refusing, timing out or not existing.
    private nonisolated static func isOfflineError(_ error: Error) -> Bool {
        let offlineCodes = [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
            NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
        ]
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSURLErrorDomain, offlineCodes.contains(nsError.code) { return true }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
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
        guard let url = URL(string: item.urlString) else {
            item.metadataFetched = true
            return
        }
        let fetched = await fetchLinkMetadata(for: url)
        // The network dropped mid-pass: not this link's fault, so it stays
        // pending — it used to be marked done here and never got its title
        // or thumbnail.
        if fetched.offline {
            PlutarLog.store.notice("LinkMetadataEnricher: offline, \(item.host, privacy: .public) left pending")
            return
        }
        // Marked done whatever the outcome from here on: a link that fails
        // for its own reasons (dead URL, bot protection, no metadata) should
        // be left alone afterwards rather than retried on every single launch.
        item.metadataFetched = true
        guard let meta = fetched.meta else {
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
        // Each marked done whatever the fetch gives, same reasoning as
        // `metadataFetched` — except when the network itself was missing.
        func markAttempted() {
            item.sourceNameFetchAttempted = true
            if needsExcerpt { item.excerptFetchAttempted = true }
        }

        guard needsName || needsExcerpt, let url = URL(string: item.urlString) else {
            markAttempted()
            return
        }
        let fetched = await fetchHTML(for: url)
        if fetched.offline { return }
        markAttempted()
        guard let html = fetched.html else { return }
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
    /// When each link's image was last attempted *this session* — memory
    /// only, per device like the files themselves.
    private static var lastThumbnailAttempt: [UUID: Date] = [:]

    /// How many images `regenerateMissingThumbnails` fetches at once.
    private static let regenerationParallelism = 4
    private static var isRegenerating = false

    /// Re-downloads every missing thumbnail, a few at a time — what runs right
    /// after a backup is restored, and on every enrichment pass (a link synced in from
    /// another device, or a reinstalled app, has a `thumbnailFileName` but no
    /// file — the JPEG itself never syncs). Candidates: links that name a thumbnail whose file isn't here.
    ///
    /// `onProgress` gets `(done, total)` after each image, success or not.
    /// Saves every 20 images, so a run cut short by the app being suspended
    /// keeps what it got — and the regular path picks up the rest.
    static func regenerateMissingThumbnails(
        in context: ModelContext,
        limit: Int? = nil,
        onProgress: ((_ done: Int, _ total: Int) -> Void)? = nil
    ) async {
        // Triggers overlap (launch, foreground, remote change…): one pass at a time.
        guard !isRegenerating else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        // Least recently attempted first. Taking them in fetch order meant a
        // link whose image never comes back (dead page, bot protection…)
        // stayed "missing" and, a few of them in, starved every link behind
        // it. Nothing is given up on — a failed link just goes to the back.
        let missing = itemsMissingThumbnailFile(in: context)
            .sorted { (lastThumbnailAttempt[$0.id] ?? .distantPast) < (lastThumbnailAttempt[$1.id] ?? .distantPast) }
            .prefix(limit ?? .max)
        // `LinkItem` isn't `Sendable`: only ids and URLs go out to the child
        // tasks, and the results are applied back here on the main actor.
        var itemsByID: [UUID: LinkItem] = [:]
        var jobs: [(id: UUID, url: URL)] = []
        for item in missing {
            itemsByID[item.id] = item
            if let url = URL(string: item.urlString) { jobs.append((item.id, url)) }
        }
        guard !jobs.isEmpty else { return }

        var done = 0
        var succeeded = 0
        await withTaskGroup(of: (UUID, String?).self) { group in
            var next = 0
            while next < min(regenerationParallelism, jobs.count) {
                let job = jobs[next]
                next += 1
                group.addTask { (job.id, await fetchThumbnail(for: job.url, id: job.id)) }
            }
            while let (id, fileName) = await group.next() {
                done += 1
                lastThumbnailAttempt[id] = Date()
                // Re-assigned even though the name is the same as before:
                // that's what makes the row notice the file has appeared.
                if let fileName, let item = itemsByID[id] {
                    item.thumbnailFileName = fileName
                    succeeded += 1
                    ThumbnailEvents.shared.revision += 1
                }
                if done.isMultiple(of: 20) { context.persist() }
                onProgress?(done, jobs.count)
                if next < jobs.count {
                    let job = jobs[next]
                    next += 1
                    group.addTask { (job.id, await fetchThumbnail(for: job.url, id: job.id)) }
                }
            }
        }
        context.persist()
        PlutarLog.store.notice("Thumbnails: \(succeeded)/\(jobs.count) recovered, \(jobs.count - succeeded) failed")
    }

    /// Links that name a thumbnail (`thumbnailFileName` set) whose file isn't
    /// on this device — the state a link synced in from another device, or
    /// restored from a backup, arrives in.
    private static func itemsMissingThumbnailFile(in context: ModelContext) -> [LinkItem] {
        let descriptor = FetchDescriptor<LinkItem>(
            predicate: #Predicate { $0.thumbnailFileName != nil }
        )
        guard let candidates = try? context.fetch(descriptor) else { return [] }
        return candidates.filter { item in
            guard let fileName = item.thumbnailFileName else { return false }
            return !thumbnailFileExists(fileName)
        }
    }

    /// One link's preview image, fetched and written to disk — nothing else
    /// (title and excerpt are left alone). `nonisolated` for the same reason
    /// as `fetchLinkMetadata`.
    private nonisolated static func fetchThumbnail(for url: URL, id: UUID) async -> String? {
        guard let meta = await fetchLinkMetadata(for: url).meta else {
            PlutarLog.store.notice("Thumbnail: no metadata for \(url.host() ?? "?", privacy: .public)")
            return nil
        }
        let name = await saveThumbnail(from: meta, id: id)
        if name == nil {
            PlutarLog.store.notice("Thumbnail: page loaded but no image for \(url.host() ?? "?", privacy: .public)")
        }
        return name
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
    ///
    /// `offline` tells a missing network apart from a failure of the link's
    /// own, so the caller can leave the link pending instead of giving up.
    private nonisolated static func fetchLinkMetadata(for url: URL) async -> (meta: LPLinkMetadata?, offline: Bool) {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        do {
            return (try await provider.startFetchingMetadata(for: url), false)
        } catch {
            return (nil, isOfflineError(error))
        }
    }

    /// `LPLinkMetadata` doesn't expose the page's meta description (or its
    /// site name), so this pulls a capped prefix of the HTML itself and
    /// reads it out directly — enough to reach whatever's in `<head>`.
    /// `nonisolated` for the same reason as `fetchLinkMetadata` above.
    /// `offline`: same meaning as `fetchLinkMetadata`'s.
    private nonisolated static func fetchHTML(for url: URL) async -> (html: String?, offline: Bool) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let limit = 65_536
            return (decodeHTML(data.prefix(limit), wasCut: data.count > limit), false)
        } catch {
            return (nil, isOfflineError(error))
        }
    }

    /// `data` (a page cut at a fixed byte count) as text: UTF-8, else
    /// Windows-1252/Latin-1 for the older pages still served that way.
    ///
    /// The cut can land in the middle of a multi-byte UTF-8 character, which
    /// makes strict UTF-8 decoding fail on the *whole* buffer; it then fell
    /// through to Latin-1 and every accent on the page came out as "Ã©". Up to
    /// three trailing bytes (the most an incomplete character can leave) are
    /// dropped before giving up on UTF-8 — only when the page really was cut
    /// (`wasCut`): on a whole page, a trailing byte that isn't UTF-8 means
    /// the page is Latin-1, not that a character is incomplete.
    nonisolated static func decodeHTML(_ data: Data, wasCut: Bool) -> String? {
        for dropped in 0...(wasCut ? 3 : 0) where dropped <= data.count {
            if let text = String(data: data.dropLast(dropped), encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
    }

    /// Both orderings of one `<meta>` tag's attributes (`property=… content=…`
    /// and `content=… property=…`), compiled once per process rather than on
    /// every match. The content is capture group 2.
    ///
    /// Group 1 is the quote that opens `content`, and the value runs to that
    /// same quote (`\1`) — it used to stop at the first quote of *either*
    /// kind, so `content="L'histoire d'un…"` was read as just "L".
    private nonisolated static func metaTagRegexes(_ tags: [(attribute: String, value: String)]) -> [NSRegularExpression] {
        tags.flatMap { tag in [
            #"<meta[^>]+\#(tag.attribute)=["']\#(tag.value)["'][^>]+content=(["'])(.*?)\1"#,
            #"<meta[^>]+content=(["'])(.*?)\1[^>]+\#(tag.attribute)=["']\#(tag.value)["']"#,
        ] }
        .compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .dotMatchesLineSeparators]) }
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
            guard let match = regex.firstMatch(in: html, range: range), match.numberOfRanges > 2,
                  let group = Range(match.range(at: 2), in: html)
            else {
                continue
            }
            let value = decodeHTMLEntities(String(html[group]).trimmingCharacters(in: .whitespacesAndNewlines))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Named entities worth knowing here — the markup ones, typographic
    /// punctuation, and the accented letters French pages still write out.
    /// Numeric ones (`&#039;`, `&#x27;`, `&#8217;`) need no table.
    private nonisolated static let htmlEntities: [String: String] = [
        "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "laquo": "«", "raquo": "»",
        "hellip": "…", "ndash": "–", "mdash": "—", "middot": "·", "bull": "•",
        "euro": "€", "copy": "©", "reg": "®", "trade": "™", "deg": "°",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë",
        "agrave": "à", "acirc": "â", "auml": "ä", "ccedil": "ç",
        "icirc": "î", "iuml": "ï", "ocirc": "ô", "ouml": "ö",
        "ugrave": "ù", "ucirc": "û", "uuml": "ü", "oelig": "œ", "aelig": "æ",
        "Eacute": "É", "Egrave": "È", "Ecirc": "Ê", "Agrave": "À", "Acirc": "Â",
        "Ccedil": "Ç", "Icirc": "Î", "Ocirc": "Ô", "Ucirc": "Û", "OElig": "Œ",
    ]

    private nonisolated static let htmlEntityRegex = try? NSRegularExpression(
        pattern: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,10});"
    )

    /// Named and numeric entities, in a single left-to-right pass: replacing
    /// one entity at a time over the whole string, as before, could decode
    /// twice ("&amp;lt;" ending up as "<"). An entity that isn't recognized
    /// is left as written.
    nonisolated static func decodeHTMLEntities(_ string: String) -> String {
        guard let regex = htmlEntityRegex, string.contains("&") else { return string }
        var result = ""
        var cursor = string.startIndex
        for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
            guard let whole = Range(match.range, in: string),
                  let body = Range(match.range(at: 1), in: string)
            else { continue }
            let name = string[body]
            let decoded: String?
            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let code = digits.first == "x" || digits.first == "X"
                    ? UInt32(digits.dropFirst(), radix: 16)
                    : UInt32(digits, radix: 10)
                decoded = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = htmlEntities[String(name)]
            }
            result += string[cursor..<whole.lowerBound]
            result += decoded ?? String(string[whole])
            cursor = whole.upperBound
        }
        result += string[cursor...]
        return result
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
