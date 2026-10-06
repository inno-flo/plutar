import Combine
import CoreData
import Foundation

/// Remembers when CloudKit last finished importing into this device's store —
/// the "synchronisation terminée" signal the automatic backup waits for
/// (`BackupService.runAutomaticIfDue`), so a device that has only half-synced
/// (a fresh install, a stretch offline) never overwrites a good backup with
/// partial content.
///
/// Listens to the same `NSPersistentCloudKitContainer.eventChangedNotification`
/// `SharedStore.waitForExportEvent` uses. It has to be started *before* the
/// container is created (see `AppContainerBootstrap.makeContainer`): the
/// import that follows launch is posted as soon as the container exists, and
/// an observer registered later would only ever see the next one.
///
/// Main apps only — the share extensions never start it.
@MainActor
final class SyncMonitor {
    static let shared = SyncMonitor()

    /// When the most recent successful import ended. In memory on purpose:
    /// the question is "has this process synced today", not something to
    /// carry across launches.
    private(set) var lastImportSuccess: Date?

    /// Fires on the main actor each time an import finishes successfully.
    let importSucceeded = PassthroughSubject<Void, Never>()

    private var observer: NSObjectProtocol?

    /// Whether an import has finished successfully since local midnight.
    var hasSuccessfulImportToday: Bool {
        guard let lastImportSuccess else { return false }
        return Calendar.current.isDateInToday(lastImportSuccess)
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
                  let end = event.endDate
            else { return }
            // Logged for every finished event, not just imports: whether an
            // import really is posted on each launch (even with nothing to
            // import) is what the automatic backup's trigger relies on.
            PlutarLog.store.notice(
                "CloudKit event: type=\(String(describing: event.type), privacy: .public) succeeded=\(event.succeeded) error=\(String(describing: event.error), privacy: .public)"
            )
            guard event.type == .import, event.succeeded else { return }
            MainActor.assumeIsolated {
                self?.lastImportSuccess = end
                self?.importSucceeded.send()
            }
        }
    }
}
