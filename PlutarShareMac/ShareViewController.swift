import Cocoa
import SwiftUI

/// Entry point of the PlutarShareMac extension (`NSExtensionPrincipalClass`
/// in its Info.plist) — the macOS counterpart of
/// `PlutarShare/ShareViewController.swift`. Same shared
/// `SharedLinkExtraction`/`ShareView`/`LinkItemFactory` logic, hosted via
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
        embed(NSHostingController(rootView: content))
    }

    /// AppKit's `NSViewController.addChild(_:)` has no `didMove(toParent:)`
    /// step to call afterwards the way UIKit's does — adding the child and
    /// its view is enough.
    private func embed(_ hosting: NSHostingController<AnyView>) {
        for child in children { child.view.removeFromSuperview() }
        children.forEach { $0.removeFromParent() }
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.width, .height]
        view.addSubview(hosting.view)
    }

    private func save(url: URL, title: String, sourceApp: String) {
        do {
            let container = try SharedStore.makeContainer()
            try LinkItemFactory.save(url: url, title: title, sourceApp: sourceApp, in: container.mainContext)
            // See `SharedStore.waitForPendingCloudKitExport`'s doc comment —
            // on-device testing showed the wait never actually observing a
            // single CloudKit sync event even across a full timeout kept
            // alive, meaning it wasn't a process-teardown race to begin
            // with. Blocking the share sheet open bought nothing but bad
            // UX, so back to dismissing immediately while the diagnosis
            // continues.
            finish()
            // Fire-and-forget now, purely diagnostic: still logs whatever
            // CloudKit sync events (if any) show up in the time the process
            // happens to survive after finish(), without holding the UI up
            // for it.
            DispatchQueue.global(qos: .utility).async {
                SharedStore.waitForPendingCloudKitExport()
            }
        } catch {
            // `SwiftDataError`'s every case bridges to the same NSError code
            // (1), so `localizedDescription` alone can't tell one apart from
            // another — `String(reflecting:)` dumps the actual enum case,
            // and userInfo often carries CloudKit's own underlying error.
            let ns = error as NSError
            PlutarLog.shareExtension.error("save failed: \(String(reflecting: error), privacy: .public) userInfo: \(ns.userInfo, privacy: .public)")
            embed(NSHostingController(rootView: AnyView(ShareErrorView(
                message: "Impossible d'enregistrer ce lien : \(error.localizedDescription)",
                onDismiss: { [weak self] in self?.finish() }
            ))))
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
