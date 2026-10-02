import SwiftUI
import SwiftData

// `PlutarLog` moved to `Persistence/PlutarLog.swift` — shared with the
// macOS app and both share extensions.

@main
struct PlutarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Container creation + in-memory fallback lives in
    /// `AppContainerBootstrap`, shared with `PlutarMacApp` — see there.
    private let store = AppContainerBootstrap.makeContainer()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                // Store-failure alert, enrichment on launch/foreground and
                // on CloudKit remote changes — see `StoreLifecycle`.
                .storeLifecycle(store, scenePhase: scenePhase)
        }
        .modelContainer(store.container)
    }
}
