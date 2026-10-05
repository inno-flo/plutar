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
        guard let groupURL = groupContainerURL else {
            throw StoreError.missingAppGroupContainer
        }
        let storeURL = groupURL.appendingPathComponent("Plutar.sqlite")
        let configuration = ModelConfiguration(
            url: storeURL,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: LinkItem.self, SourceRank.self, configurations: configuration)
    }

    /// The one container a share-extension process uses, for every share it
    /// handles — created on first access, then kept for the life of the
    /// process. Both extensions used to call `makeContainer()` as a local
    /// inside `save()`, which released the container (and with it the
    /// persistent store) a few milliseconds after the save, while
    /// `NSPersistentCloudKitContainer`'s asynchronous CloudKit setup was
    /// still running: every share logged `Failed to initialize CloudKit
    /// metadata` (134407) followed by "store was removed" / "tear down:
    /// Store Removed", and nothing was ever exported until the main app
    /// (which holds its container for its whole lifetime) next ran. A
    /// macOS extension process can also handle several shares in a row, and
    /// a fresh container per share meant a fresh CloudKit setup each time.
    static let extensionContainer = Result { try makeContainer() }

    private static var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Where `LinkMetadataEnricher` saves downloaded preview images, keyed
    /// by `LinkItem.id`. In the App Group container (not the app's own
    /// Documents/Caches) so it's readable regardless of which process — app
    /// or extension — writes it.
    ///
    /// Resolved (and the directory created) once per process: this used to
    /// be a function redoing both on every call — including every thumbnail
    /// cache miss while rendering a row.
    static let thumbnailsDirectoryURL: URL? = {
        guard let groupURL = groupContainerURL else { return nil }
        let directory = groupURL.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Removes a `LinkItem`'s on-disk preview image, once it's actually
    /// gone for good (not while an undo window could still restore the
    /// `LinkItem` pointing at this same file). Safe to call with `nil` (no
    /// thumbnail was ever fetched) or a name that's already gone.
    static func deleteThumbnailFile(named fileName: String?) {
        guard let fileName, let directory = thumbnailsDirectoryURL else { return }
        thumbnailImageCache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// Small in-memory cache so scrolling doesn't re-read the same JPEG off
    /// disk on every layout pass (see `LinkRowView`) — kept here, next to
    /// the files it mirrors, so deleting a thumbnail drops its cached image
    /// too.
    static let thumbnailImageCache = NSCache<NSString, PlatformImage>()

    /// Deletes every file in the thumbnails directory that no link refers
    /// to any more — a link deleted on another device, via CloudKit, only
    /// removes that device's own file. `referenced` is every
    /// `thumbnailFileName` currently in the store; the caller must only
    /// pass a complete set (never one from a failed fetch or the in-memory
    /// fallback store), or live thumbnails would be wiped.
    static func removeOrphanedThumbnails(keeping referenced: Set<String>) {
        guard let directory = thumbnailsDirectoryURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for file in files where !referenced.contains(file) {
            deleteThumbnailFile(named: file)
        }
    }

    /// Called by both share extensions right after a successful save (off
    /// the main thread — this blocks). `NSPersistentCloudKitContainer`
    /// (behind `cloudKitDatabase:` above) pushes a save to CloudKit
    /// asynchronously, after `save()` has returned, so the extension has to
    /// stay around — process *and* `extensionContainer` — until that export
    /// has actually left the device; otherwise a link shared while Plutar
    /// isn't running sits local-only until the main app next runs.
    ///
    /// On iOS, `ProcessInfo.performExpiringActivity` asks the OS for a short
    /// grace period of background runtime beyond the extension's own
    /// lifecycle (the share sheet itself is dismissed independently, after
    /// the brief confirmation) — unavailable on macOS, where on-device logs
    /// showed the extension process staying alive after `completeRequest`
    /// anyway, so the wait just runs directly there. Either way this
    /// returns once `NSPersistentCloudKitContainer` reports an export
    /// finished, or `timeout` elapses. Best effort, not a guarantee — if
    /// the export doesn't make it out in time, the next process to open the
    /// store (usually the main app) exports it.
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

extension ModelContext {
    /// Saves, logging a failure instead of dropping it — returns whether the
    /// save went through, so a view can also surface it ("Enregistrement
    /// impossible").
    ///
    /// Every mutation used to end in a bare `try? modelContext.save()`, so a
    /// full disk or a constraint violation vanished without a trace: the
    /// in-memory objects looked updated, nothing reached the store, and
    /// neither the user nor the console ever heard about it.
    @discardableResult
    func persist(_ operation: String = #function) -> Bool {
        do {
            try save()
            return true
        } catch {
            PlutarLog.store.error(
                "Save failed during \(operation, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    /// Deletes `items` for good, along with each one's on-disk thumbnail —
    /// only for a delete no undo window can bring back (see
    /// `SharedStore.deleteThumbnailFile(named:)`).
    func deleteLinks(_ items: some Sequence<LinkItem>) {
        for item in items {
            SharedStore.deleteThumbnailFile(named: item.thumbnailFileName)
            delete(item)
        }
    }
}
