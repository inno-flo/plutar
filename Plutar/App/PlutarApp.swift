import SwiftUI
import SwiftData
import OSLog

/// Shared loggers. Store writes used to be swallowed by `try?` at a dozen
/// call sites, so a failure to persist left no trace at all — not in the UI,
/// not in the console. Everything that touches the store reports here.
enum PlutarLog {
    static let store = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Plutar",
        category: "store"
    )
}

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
        do {
            container = try SharedStore.makeContainer()
            storeFailure = nil
        } catch {
            // A failed schema migration, a corrupt store or a full disk used
            // to be a hard `fatalError` here: the app simply stopped
            // launching, with no way for the user to recover short of
            // deleting it. Falling back to an in-memory store keeps the app
            // usable and lets it explain itself — nothing persists across
            // launches until the real store can be opened again.
            storeFailure = String(describing: error)
            PlutarLog.store.error(
                "Store on disk unavailable, falling back to memory: \(String(describing: error), privacy: .public)"
            )
            container = Self.makeInMemoryContainer()
        }
        seedIfNeeded()
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
        }
        .modelContainer(container)
    }

    /// Last-resort container. Only the schema itself can make this fail — no
    /// disk, no migration, no user data involved — so a failure here is a
    /// programmer error rather than something the user could recover from.
    private static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: LinkItem.self, SourceRank.self,
            configurations: configuration
        )
    }

    /// Populates the store with the 200 demo links on first launch only.
    private func seedIfNeeded() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<LinkItem>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        let items = SeedData.makeLinkItems()
        for item in items { context.insert(item) }
        SourceRank.bump(items.map(\.host), in: context)
        do {
            try context.save()
        } catch {
            // Previously a bare `try?`: a failed seed left the app showing an
            // empty feed with nothing anywhere saying why.
            PlutarLog.store.error("Seeding failed: \(String(describing: error), privacy: .public)")
        }
    }
}
