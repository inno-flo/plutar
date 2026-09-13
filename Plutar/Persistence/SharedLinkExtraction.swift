import Foundation
import UniformTypeIdentifiers

/// One shared link as handed back by `extractSharedURL`.
struct SharedLink {
    let url: URL
    let title: String?
    let sourceApp: String
}

/// Pulls a URL (plus an optional title and the originating app, when known)
/// out of a share extension's `NSExtensionItem`s. Pure Foundation +
/// UniformTypeIdentifiers — `NSExtensionItem`/`NSItemProvider` are Foundation
/// types, not UIKit/AppKit ones, so this same logic drives both `PlutarShare`
/// (iOS, `UIViewController`-hosted) and `PlutarShareMac` (macOS,
/// `NSViewController`-hosted); only each's own `ShareViewController` differs.
enum SharedLinkExtraction {
    static func extractSharedURL(
        from items: [NSExtensionItem]?,
        completion: @escaping (Result<SharedLink, Error>) -> Void
    ) {
        // Was `inputItems.first` + `.attachments?.first` — only ever looked
        // at the very first attachment of the very first item. Several
        // third-party apps put the link in a *second* attachment (a caption
        // or title comes first), which made every one of their shares fail
        // with "aucun lien n'a été trouvé" even though a perfectly good URL
        // was sitting right there. Every attachment of every item is
        // considered now.
        guard let items, !items.isEmpty else {
            completion(.failure(SharedStore.StoreError.missingAppGroupContainer))
            return
        }
        let attachments = items.flatMap { $0.attachments ?? [] }
        guard !attachments.isEmpty else {
            completion(.failure(SharedStore.StoreError.missingAppGroupContainer))
            return
        }
        let plainTitle = items.compactMap { $0.attributedContentText?.string }.first

        // Safari (and only Safari — third-party apps never run our script)
        // runs `SharePreprocessor.js` on the page and hands back its result
        // as a property list instead of a plain URL, per
        // `NSExtensionJavaScriptPreprocessingFile` in Info.plist. Its
        // presence is what lets a link be tagged "via Safari" instead of
        // the generic "via Partage" fallback below — the OS otherwise never
        // tells an extension which app invoked it. (macOS's Safari share
        // extension host may not run the preprocessing script the same way
        // — if not, macOS shares simply fall back to "Partage", which is
        // fine.)
        if let attachment = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) }) {
            attachment.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { data, error in
                guard
                    let dictionary = data as? NSDictionary,
                    let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary,
                    let urlString = results["URL"] as? String,
                    let url = URL(string: urlString)
                else {
                    completion(.failure(error ?? URLError(.badURL)))
                    return
                }
                let title = (results["title"] as? String) ?? plainTitle
                completion(.success(SharedLink(url: url, title: title, sourceApp: "Safari")))
            }
            return
        }

        if let attachment = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { data, error in
                if let url = data as? URL {
                    completion(.success(SharedLink(url: url, title: plainTitle, sourceApp: "Partage")))
                } else if let error {
                    completion(.failure(error))
                } else {
                    completion(.failure(URLError(.badURL)))
                }
            }
            return
        }

        let textAttachments = attachments.filter { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        guard !textAttachments.isEmpty else {
            completion(.failure(URLError(.unsupportedURL)))
            return
        }
        extractURL(fromTextAttachments: textAttachments, title: plainTitle, completion: completion)
    }

    /// Tries each plain-text attachment in turn, pulling a URL out of
    /// whatever free-form text it holds — a caption and a link sharing one
    /// attachment ("Check this out: https://…") is common enough that
    /// requiring the *whole* string to be a URL (the previous behavior)
    /// rejected real shares.
    private static func extractURL(
        fromTextAttachments attachments: [NSItemProvider],
        index: Int = 0,
        title: String?,
        completion: @escaping (Result<SharedLink, Error>) -> Void
    ) {
        guard index < attachments.count else {
            completion(.failure(URLError(.badURL)))
            return
        }
        attachments[index].loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            if let text = data as? String, let url = firstURL(in: text) {
                completion(.success(SharedLink(url: url, title: title, sourceApp: "Partage")))
            } else {
                extractURL(fromTextAttachments: attachments, index: index + 1, title: title, completion: completion)
            }
        }
    }

    private static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return URL(string: text)
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }
}
