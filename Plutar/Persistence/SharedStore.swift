import CoreData
import Foundation
import SwiftData

/// Builds the `ModelContainer` shared between the main app and the
/// PlutarShare extension (iOS and macOS alike), so a link saved from the
/// share sheet shows up in the app without either process needing to
/// relaunch the other, and — via the CloudKit-backed configuration below —
/// syncs across every device signed into the same iCloud account.
///
/// All four targets (Plutar, PlutarShare, PlutarMac, PlutarShareMac) need to
/// agree on the exact same on-disk location and CloudKit container, which is
/// why this lives in one file compiled into all of them (see `project.yml`)
/// rather than being duplicated.
enum SharedStore {
    /// Must match the App Group entitlement on every target — anchored once
    /// as `&appGroupID` in `project.yml` (on the `Plutar` target) and
    /// referenced via `*appGroupID` by the other three, so there's one
    /// place on the YAML side to rename; this Swift constant is the one
    /// place on the Swift side, since an anchor can't reach across into
    /// source code.
    static let appGroupID = "group.com.innoflo.plutar"

    /// Must match `com.apple.developer.icloud-container-identifiers` on
    /// every target — anchored once as `&cloudKitContainerID` in
    /// `project.yml`, same as `appGroupID` above.
    static let cloudKitContainerID = "iCloud.com.innoflo.plutar"

    enum StoreError: Error {
        case missingAppGroupContainer
    }

    /// The container every app/extension process reads from and writes to.
    /// Throws (rather than falling back silently) when the App Group isn't
    /// available — the app already has its own in-memory fallback for that
    /// case; the extension surfaces the error to the user instead.
    ///
    /// The on-disk location stays the same App Group SQLite file as before
    /// CloudKit was added — it's still what gives same-device app↔extension
    /// sharing its immediate, no-round-trip behavior. `cloudKitDatabase:`
    /// only adds background sync of that same local store to other devices
    /// signed into the same iCloud account; it doesn't change where the
    /// local cache lives.
    static func makeContainer() throws -> ModelContainer {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            throw StoreError.missingAppGroupContainer
        }
        let storeURL = groupURL.appendingPathComponent("Plutar.sqlite")
        let configuration = ModelConfiguration(
            url: storeURL,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: LinkItem.self, SourceRank.self, configurations: configuration)
    }

    /// Where `LinkMetadataEnricher` saves downloaded preview images, keyed
    /// by `LinkItem.id`. In the App Group container (not the app's own
    /// Documents/Caches) so it's readable regardless of which process — app
    /// or extension — writes it.
    static func thumbnailsDirectoryURL() -> URL? {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            return nil
        }
        let directory = groupURL.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Removes a `LinkItem`'s on-disk preview image, once it's actually
    /// gone for good (not while an undo window could still restore the
    /// `LinkItem` pointing at this same file). Safe to call with `nil` (no
    /// thumbnail was ever fetched) or a name that's already gone.
    static func deleteThumbnailFile(named fileName: String?) {
        guard let fileName, let directory = thumbnailsDirectoryURL() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// Called by both share extensions right after `context.save()`, before
    /// they call `completeRequest`. `NSPersistentCloudKitContainer` (behind
    /// `cloudKitDatabase:` above) kicks off the push to CloudKit
    /// asynchronously once a save happens — it doesn't finish inside
    /// `save()` itself — but a share extension's process tends to get torn
    /// down very soon after `completeRequest`, often before that export has
    /// actually left the device. Left alone, a link shared while Plutar's
    /// main app hasn't been opened on that device would just sit
    /// local-only, invisible everywhere else, until the app (or this
    /// extension again) happened to run and give the container another
    /// chance to flush it.
    ///
    /// On iOS, `ProcessInfo.performExpiringActivity` asks the OS for a short
    /// grace period of background runtime beyond the extension's own
    /// lifecycle to do exactly this kind of cleanup — unavailable on macOS,
    /// which doesn't tear down an extension's process on the same tight
    /// leash to begin with, so the wait below just runs directly there.
    /// Either way this blocks (on a background queue — callers dispatch off
    /// the main thread before calling this) until
    /// `NSPersistentCloudKitContainer` reports the export finished, or
    /// `timeout` elapses, whichever comes first. Best effort, not a
    /// guarantee — a slow network or an already-expiring activity can still
    /// mean the export doesn't make it out in time, in which case the link
    /// is caught by the same fallback as before (the next process to touch
    /// this container).
    static func waitForPendingCloudKitExport(timeout: TimeInterval = 25) {
        #if os(iOS)
        ProcessInfo.processInfo.performExpiringActivity(withReason: "com.innoflo.plutar.cloudkit-export") { expiring in
            guard !expiring else { return }
            waitForExportEvent(timeout: timeout)
        }
        #else
        waitForExportEvent(timeout: timeout)
        #endif
    }

    private static func waitForExportEvent(timeout: TimeInterval) {
        let semaphore = DispatchSemaphore(value: 0)
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            else { return }
            // Diagnostic for whether a container freshly created inside the
            // extension is stalling on `.setup` (first-run CloudKit zone/
            // schema handshake) before it ever gets to `.export`, versus the
            // export itself starting but not finishing in time.
            PlutarLog.store.notice(
                "CloudKit event (share extension): type=\(String(describing: event.type), privacy: .public) succeeded=\(event.succeeded) finished=\(event.endDate != nil) error=\(String(describing: event.error), privacy: .public)"
            )
            guard event.type == .export, event.endDate != nil else { return }
            semaphore.signal()
        }
        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            PlutarLog.store.notice("CloudKit export wait timed out after \(timeout, privacy: .public)s (share extension)")
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
