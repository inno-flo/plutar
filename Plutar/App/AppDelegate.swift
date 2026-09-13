import UIKit

/// Registers for CloudKit's silent push so `NSPersistentCloudKitContainer`
/// (behind `SharedStore`'s `cloudKitDatabase:` config) can pull a remote
/// change in the moment it happens, instead of only noticing on the next
/// launch or foreground. Without this, a link added on another device sits
/// unsynced while Plutar stays open in the foreground — nothing tells the
/// running app a remote change is waiting, and pull-to-refresh only re-runs
/// `LinkMetadataEnricher`'s local scan; it can't itself ask CloudKit for new
/// data. Backgrounding then foregrounding "worked" only because that's one
/// of the moments the framework already re-checks on its own.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    /// `NSPersistentCloudKitContainer` recognizes and imports its own
    /// CloudKit push payload automatically once it reaches the app —
    /// nothing else needs to happen here beyond acknowledging it.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }

    // Registration failing silently (bad/missing "Push Notifications"
    // capability on the provisioning profile, no network, …) would leave
    // this device stuck on the old launch/foreground-only sync with
    // nothing in the console explaining why — these two make that visible.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PlutarLog.store.notice("Remote notification registration succeeded (iOS)")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PlutarLog.store.error("Remote notification registration failed (iOS): \(String(describing: error), privacy: .public)")
    }
}
