import SwiftUI
import SwiftData

@main
struct PlutarMacApp: App {
    let container: ModelContainer
    /// Set when the on-disk store could not be opened and the app fell back
    /// to a throwaway in-memory one, so the UI can say so rather than
    /// pretending everything is being saved.
    let storeFailure: String?

    @State private var showStoreFailureAlert = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Container creation + in-memory fallback lives in
        // `AppContainerBootstrap`, shared with `PlutarApp` (iOS) — see there.
        let bootstrap = AppContainerBootstrap.makeContainer()
        container = bootstrap.container
        storeFailure = bootstrap.storeFailure
    }

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .frame(minWidth: 480, minHeight: 360)
                .alert("Stockage indisponible", isPresented: $showStoreFailureAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Plutar n'a pas pu ouvrir sa base de données. L'app fonctionne normalement, mais les liens ajoutés ou supprimés pendant cette session seront perdus à la fermeture.")
                }
                .task { showStoreFailureAlert = storeFailure != nil }
                .task { await LinkMetadataEnricher.enrichPendingLinks(in: container.mainContext) }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await LinkMetadataEnricher.enrichPendingLinks(in: container.mainContext) }
                }
        }
        .modelContainer(container)

        // `.modelContainer` is per-Scene, not app-wide — `MacSettingsView`
        // reads/deletes `LinkItem`/`SourceRank` (Avancé tab), so this Settings
        // scene needs the same container as the WindowGroup above, not just
        // whatever SwiftData default it would otherwise fall back to.
        Settings {
            MacSettingsView()
        }
        .modelContainer(container)
    }
}
