import Combine
import CoreData
import SwiftUI
import SwiftData

// `PlutarLog` moved to `Persistence/PlutarLog.swift` — shared with the
// macOS app and both share extensions.

@main
struct PlutarApp: App {
    let container: ModelContainer
    /// Set when the on-disk store could not be opened and the app fell back
    /// to a throwaway in-memory one, so the UI can say so rather than
    /// pretending everything is being saved.
    let storeFailure: String?

    @State private var showStoreFailureAlert = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Container creation + in-memory fallback lives in
        // `AppContainerBootstrap`, shared with `PlutarMacApp` — see there.
        let bootstrap = AppContainerBootstrap.makeContainer()
        container = bootstrap.container
        storeFailure = bootstrap.storeFailure
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .alert("Stockage indisponible", isPresented: $showStoreFailureAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Plutar n'a pas pu ouvrir sa base de données. L'app fonctionne normalement, mais les liens ajoutés ou supprimés pendant cette session seront perdus à la fermeture.")
                }
                .task { showStoreFailureAlert = storeFailure != nil }
                .task { await LinkMetadataEnricher.enrichPendingLinks(in: container.mainContext) }
                .onChange(of: scenePhase) { _, newPhase in
                    // Catches links shared while Plutar wasn't running, and
                    // ones the extension left half-done (e.g. app backgrounded
                    // mid-fetch) — not just the cold-start case above.
                    guard newPhase == .active else { return }
                    Task { await LinkMetadataEnricher.enrichPendingLinks(in: container.mainContext) }
                }
                // CloudKit merges a remote change straight into the store
                // without the app doing anything, so a link enriched on
                // another device (title/thumbnailFileName arriving here) used
                // to just sit there until the next launch/foreground or a
                // manual refresh — nothing re-ran `redownloadMissingThumbnails`
                // to fetch this device's own copy of the image. Debounced
                // since CloudKit can deliver a burst of remote-change
                // notifications for a single sync.
                .onReceive(
                    NotificationCenter.default
                        .publisher(for: .NSPersistentStoreRemoteChange)
                        .debounce(for: .seconds(1), scheduler: RunLoop.main)
                ) { _ in
                    Task { await LinkMetadataEnricher.enrichPendingLinks(in: container.mainContext) }
                }
        }
        .modelContainer(container)
    }
}
