import UIKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

/// One shared link as handed back by `extractSharedURL`.
private struct SharedLink {
    let url: URL
    let title: String?
    let sourceApp: String
}

/// Entry point of the PlutarShare extension (`NSExtensionPrincipalClass` in
/// its Info.plist). Pulls the shared URL out of the extension context,
/// presents `ShareView` for a title tweak, then writes straight into the
/// App Group-backed store the main app reads from.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedURL { [weak self] result in
            DispatchQueue.main.async {
                self?.present(result)
            }
        }
    }

    private func present(_ result: Result<SharedLink, Error>) {
        let content: AnyView
        switch result {
        case .failure:
            content = AnyView(ShareErrorView(
                message: "Ce contenu ne peut pas être ajouté à Plutar : aucun lien n'a été trouvé.",
                onDismiss: { [weak self] in self?.finish() }
            ))
        case .success(let shared):
            content = AnyView(ShareView(
                host: shared.url.host ?? shared.url.absoluteString,
                title: shared.title ?? shared.url.absoluteString,
                onSave: { [weak self] editedTitle in
                    self?.save(url: shared.url, title: editedTitle, sourceApp: shared.sourceApp)
                },
                onCancel: { [weak self] in self?.finish() }
            ))
        }
        let hosting = UIHostingController(rootView: content)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func save(url: URL, title: String, sourceApp: String) {
        do {
            let container = try SharedStore.makeContainer()
            try LinkItemFactory.save(url: url, title: title, sourceApp: sourceApp, in: container.mainContext)
            finish()
        } catch {
            let hosting = UIHostingController(rootView: ShareErrorView(
                message: "Impossible d'enregistrer ce lien : \(error.localizedDescription)",
                onDismiss: { [weak self] in self?.finish() }
            ))
            addChild(hosting)
            hosting.view.frame = view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(hosting.view)
            hosting.didMove(toParent: self)
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func extractSharedURL(completion: @escaping (Result<SharedLink, Error>) -> Void) {
        // Was `inputItems.first` + `.attachments?.first` — only ever looked
        // at the very first attachment of the very first item. Several
        // third-party apps put the link in a *second* attachment (a caption
        // or title comes first), which made every one of their shares fail
        // with "aucun lien n'a été trouvé" even though a perfectly good URL
        // was sitting right there. Every attachment of every item is
        // considered now.
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
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
        // the generic "via Partage" fallback below — iOS otherwise never
        // tells an extension which app invoked it.
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
    private func extractURL(
        fromTextAttachments attachments: [NSItemProvider],
        index: Int = 0,
        title: String?,
        completion: @escaping (Result<SharedLink, Error>) -> Void
    ) {
        guard index < attachments.count else {
            completion(.failure(URLError(.badURL)))
            return
        }
        attachments[index].loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
            if let text = data as? String, let url = Self.firstURL(in: text) {
                completion(.success(SharedLink(url: url, title: title, sourceApp: "Partage")))
            } else {
                self?.extractURL(fromTextAttachments: attachments, index: index + 1, title: title, completion: completion)
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
