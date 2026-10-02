import Cocoa
import SwiftUI

/// Entry point of the PlutarShareMac extension (`NSExtensionPrincipalClass`
/// in its Info.plist) — the macOS counterpart of
/// `PlutarShare/ShareViewController.swift`. Same shared
/// `SharedLinkExtraction`/`ShareSavedView`/`LinkItemFactory` logic, hosted via
/// AppKit (`NSViewController`/`NSHostingController`) instead of UIKit.
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 475, height: 160))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
            save(shared)
        }
    }

    /// AppKit's `NSViewController.addChild(_:)` has no `didMove(toParent:)`
    /// step to call afterwards the way UIKit's does — adding the child and
    /// its view is enough.
    private func embed<Content: View>(_ content: Content) {
        for child in children {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let hosting = NSHostingController(rootView: content)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.width, .height]
        view.addSubview(hosting.view)
    }

    private func save(_ shared: SharedLink) {
        do {
            // Process-wide container + background CloudKit export wait: see
            // `LinkItemFactory.save`.
            try LinkItemFactory.save(shared)
            embed(ShareSavedView())
            // Shrink the window to just the checkmark square (the error
            // dialogs keep the wider default set in `loadView`).
            let size = NSSize(width: 136, height: 136)
            preferredContentSize = size
            view.setFrameSize(size)
            finishAfterDelay()
        } catch {
            // `SwiftDataError`'s every case bridges to the same NSError code
            // (1), so `localizedDescription` alone can't tell one apart from
            // another — `String(reflecting:)` dumps the actual enum case,
            // and userInfo often carries CloudKit's own underlying error.
            let ns = error as NSError
            PlutarLog.shareExtension.error("save failed: \(String(reflecting: error), privacy: .public) userInfo: \(ns.userInfo, privacy: .public)")
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
