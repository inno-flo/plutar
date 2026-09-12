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
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachment = item.attachments?.first
        else {
            completion(.failure(SharedStore.StoreError.missingAppGroupContainer))
            return
        }

        let plainTitle = item.attributedContentText?.string

        // Safari (and only Safari — third-party apps never run our script)
        // runs `SharePreprocessor.js` on the page and hands back its result
        // as a property list instead of a plain URL, per
        // `NSExtensionJavaScriptPreprocessingFile` in Info.plist. Its
        // presence is what lets a link be tagged "via Safari" instead of
        // the generic "via Partage" fallback below — iOS otherwise never
        // tells an extension which app invoked it.
        if attachment.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
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
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { data, error in
                if let url = data as? URL {
                    completion(.success(SharedLink(url: url, title: plainTitle, sourceApp: "Partage")))
                } else if let error {
                    completion(.failure(error))
                } else {
                    completion(.failure(URLError(.badURL)))
                }
            }
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, error in
                if let text = data as? String, let url = URL(string: text), url.scheme != nil {
                    completion(.success(SharedLink(url: url, title: plainTitle, sourceApp: "Partage")))
                } else if let error {
                    completion(.failure(error))
                } else {
                    completion(.failure(URLError(.badURL)))
                }
            }
        } else {
            completion(.failure(URLError(.unsupportedURL)))
        }
    }
}
