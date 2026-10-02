import UIKit
import SwiftUI

/// Entry point of the PlutarShare extension (`NSExtensionPrincipalClass` in
/// its Info.plist). Pulls the shared URL out of the extension context (via
/// the shared, platform-agnostic `SharedLinkExtraction`), saves it straight into
/// the App Group/CloudKit-backed store the main app reads from, and shows a
/// brief self-dismissing `ShareSavedView`. See
/// `PlutarShareMac/ShareViewController.swift` for the macOS counterpart —
/// same logic, `NSViewController`/`NSHostingController` instead of
/// `UIViewController`/`UIHostingController`.
///
/// The container — the card that slides up from the bottom of the screen on
/// iPhone — belongs to the host app's share-sheet machinery, not to the
/// extension: there is no API to replace it with a centered HUD. All that's
/// controllable from here is making our own view transparent so only the
/// checkmark square shows, and (iPad only) shrinking the presented size.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        SharedLinkExtraction.extractSharedURL(from: extensionContext?.inputItems as? [NSExtensionItem]) { [weak self] result in
            DispatchQueue.main.async {
                self?.present(result)
            }
        }
    }

    private func present(_ result: Result<SharedLink, Error>) {
        switch result {
        case .failure(let error):
            PlutarLog.shareExtension.error("extractSharedURL failed: \(error.localizedDescription, privacy: .public)")
            embed(ShareErrorView(
                message: "Ce contenu ne peut pas être ajouté à Plutar : aucun lien n'a été trouvé.",
                onDismiss: { [weak self] in self?.finish() }
            ))
        case .success(let shared):
            // No confirmation step: saved straight away, then a brief
            // "Ajouté" that dismisses itself (see `save`).
            save(url: shared.url, title: shared.title, sourceApp: shared.sourceApp)
        }
    }

    private func embed<Content: View>(_ content: Content) {
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let hosting = UIHostingController(rootView: content)
        // Transparent, so the confirmation HUD floats over the host app
        // instead of sitting on an opaque sheet.
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func save(url: URL, title: String?, sourceApp: String) {
        do {
            // Process-wide, not a local: see `SharedStore.extensionContainer`
            // — a local was released right after this save, mid CloudKit
            // setup, so nothing was ever exported.
            let container = try SharedStore.extensionContainer.get()
            try LinkItemFactory.save(url: url, title: title, sourceApp: sourceApp, in: container.mainContext)
            embed(ShareSavedView())
            // iPad presents the extension as a popover/form sheet that
            // follows `preferredContentSize`, so it shrinks to just the
            // checkmark square; iPhone ignores it (see the class doc).
            preferredContentSize = CGSize(width: 136, height: 136)
            // The sheet doesn't wait for CloudKit — the confirmation stays
            // up only briefly — but the export wait below keeps going after
            // it's dismissed (see `SharedStore.waitForPendingCloudKitExport`).
            finishAfterDelay()
            DispatchQueue.global(qos: .utility).async {
                SharedStore.waitForPendingCloudKitExport()
            }
        } catch {
            embed(ShareErrorView(
                message: "Impossible d'enregistrer ce lien : \(error.localizedDescription)",
                onDismiss: { [weak self] in self?.finish() }
            ))
        }
    }

    /// Just long enough to register the checkmark, short enough not to get in
    /// the way of whatever the user was doing in the host app.
    private func finishAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
