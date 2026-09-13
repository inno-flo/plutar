import AppKit

/// Mac counterpart to `PlutarApp`'s `AppDelegate` (iOS) — see its doc
/// comment. Registers for CloudKit's silent push so a remote change is
/// pulled in while the app is already foregrounded, rather than only on the
/// next launch/foreground or a manual refresh.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    /// `NSPersistentCloudKitContainer` recognizes and imports its own
    /// CloudKit push payload automatically once it reaches the app —
    /// nothing else needs to happen here.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {}

    // Registration failing silently (bad/missing "Push Notifications"
    // capability on the provisioning profile, no network, …) would leave
    // this device stuck on the old launch/foreground-only sync with
    // nothing in the console explaining why — these two make that visible.
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PlutarLog.store.notice("Remote notification registration succeeded (macOS)")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PlutarLog.store.error("Remote notification registration failed (macOS): \(String(describing: error), privacy: .public)")
    }
}
