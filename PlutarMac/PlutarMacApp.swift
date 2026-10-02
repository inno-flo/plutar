import SwiftUI
import SwiftData

@main
struct PlutarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Container creation + in-memory fallback lives in
    /// `AppContainerBootstrap`, shared with `PlutarApp` (iOS) — see there.
    private let store = AppContainerBootstrap.makeContainer()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .frame(minWidth: 480, minHeight: 360)
                // Same as `PlutarApp`'s: a remote CloudKit change (e.g. a
                // link enriched on iOS) merges into the store on its own, so
                // without this the Mac app never noticed there was now an
                // image to redownload until the next launch/foreground or a
                // manual refresh — see `StoreLifecycle`.
                .storeLifecycle(store, scenePhase: scenePhase)
        }
        .modelContainer(store.container)

        // `.modelContainer` is per-Scene, not app-wide — `MacSettingsView`
        // reads/deletes `LinkItem`/`SourceRank` (Avancé tab), so this Settings
        // scene needs the same container as the WindowGroup above, not just
        // whatever SwiftData default it would otherwise fall back to.
        Settings {
            MacSettingsView()
        }
        .modelContainer(store.container)
    }
}
