import UIKit
import SwiftUI

/// Entry point of the PlutarShare extension (`NSExtensionPrincipalClass` in
/// its Info.plist). Pulls the shared URL out of the extension context (via
/// the shared, platform-agnostic `SharedLinkExtraction`), presents
/// `ShareView` for a title tweak, then writes straight into the App
/// Group/CloudKit-backed store the main app reads from. See
/// `PlutarShareMac/ShareViewController.swift` for the macOS counterpart —
/// same logic, `NSViewController`/`NSHostingController` instead of
/// `UIViewController`/`UIHostingController`.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        SharedLinkExtraction.extractSharedURL(from: extensionContext?.inputItems as? [NSExtensionItem]) { [weak self] result in
            DispatchQueue.main.async {
                self?.present(result)
            }
        }
    }

    private func present(_ result: Result<SharedLink, Error>) {
        let content: AnyView
        switch result {
        case .failure(let error):
            PlutarLog.shareExtension.error("extractSharedURL failed: \(error.localizedDescription, privacy: .public)")
            content = AnyView(ShareErrorView(
                message: "Ce contenu ne peut pas être ajouté à Plutar : aucun lien n'a été trouvé.",
                onDismiss: { [weak self] in self?.finish() }
            ))
        case .success(let shared):
            content = AnyView(ShareView(
                host: shared.url.host ?? shared.url.absoluteString,
                title: shared.title ?? shared.url.absoluteString,
                url: shared.url,
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
}
