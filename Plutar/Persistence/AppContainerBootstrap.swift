import CoreData
import Foundation
import SwiftData
import SwiftUI

/// Builds the app's `ModelContainer` (with the in-memory fallback used when
/// the on-disk/CloudKit store can't be opened) — shared by `PlutarApp.init`
/// and `PlutarMacApp.init`, which used to each carry their own copy of this
/// ~15-line sequence. A future change here (a new fallback case, extra
/// store-health logging) now only needs to happen once instead of being
/// hand-applied to both `@main` types, which don't call into each other and
/// so could silently drift if only one copy were updated.
enum AppContainerBootstrap {
    struct Result {
        let container: ModelContainer
        /// Set when the on-disk store could not be opened and `container`
        /// is a throwaway in-memory one — so the caller's UI can say so
        /// rather than pretending everything is being saved.
        let storeFailure: String?
    }

    @MainActor
    static func makeContainer() -> Result {
        // Before the container exists, not after: CloudKit starts importing
        // the moment it does, and `SyncMonitor` (what the automatic backup
        // waits on) only sees events posted once it's listening.
        SyncMonitor.shared.start()
        do {
            let container = try SharedStore.makeContainer()
            return Result(container: container, storeFailure: nil)
        } catch {
            // A failed schema migration, a corrupt store or a full disk used
            // to be a hard `fatalError` here: the app simply stopped
            // launching, with no way for the user to recover short of
            // deleting it. Falling back to an in-memory store keeps the app
            // usable and lets it explain itself — nothing persists across
            // launches until the real store can be opened again.
            PlutarLog.store.error(
                "Store on disk unavailable, falling back to memory: \(String(describing: error), privacy: .public)"
            )
            return Result(container: makeInMemoryContainer(), storeFailure: String(describing: error))
        }
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
}

extension View {
    /// Everything `PlutarApp` (iOS) and `PlutarMacApp` attach to their root
    /// view around the store — they used to each carry their own copy of
    /// this block. `scenePhase` is passed in from the `App` itself (its
    /// app-wide phase), not read from this view's own environment.
    func storeLifecycle(_ store: AppContainerBootstrap.Result, scenePhase: ScenePhase) -> some View {
        modifier(StoreLifecycle(store: store, scenePhase: scenePhase))
    }

    /// "Enregistrement impossible" — raised wherever a view's own
    /// `ModelContext.persist()` reports a failed save.
    func saveFailureAlert(isPresented: Binding<Bool>) -> some View {
        alert("Enregistrement impossible", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La dernière modification n'a pas pu être enregistrée et sera perdue à la fermeture de l'app.")
        }
    }
}

private struct StoreLifecycle: ViewModifier {
    let store: AppContainerBootstrap.Result
    let scenePhase: ScenePhase

    @State private var showStoreFailureAlert = false

    private var context: ModelContext { store.container.mainContext }

    func body(content: Content) -> some View {
        content
            .alert("Stockage indisponible", isPresented: $showStoreFailureAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Plutar n'a pas pu ouvrir sa base de données. L'app fonctionne normalement, mais les liens ajoutés ou supprimés pendant cette session seront perdus à la fermeture.")
            }
            .task { showStoreFailureAlert = store.storeFailure != nil }
            .task {
                // Cold start only, and before enrichment can write new
                // thumbnails: drop thumbnail files no link refers to any
                // more. Skipped on the throwaway in-memory fallback store,
                // whose emptiness says nothing about the real one.
                if store.storeFailure == nil,
                   let items = try? context.fetch(FetchDescriptor<LinkItem>()) {
                    SharedStore.removeOrphanedThumbnails(keeping: Set(items.compactMap(\.thumbnailFileName)))
                }
                // Its own task: an upload shouldn't hold up enrichment.
                // Usually a no-op this early — it waits for a CloudKit import
                // to have succeeded, see `BackupService.runAutomaticIfDue`.
                Task { await BackupService.runAutomaticIfDue(in: context) }
                await LinkMetadataEnricher.enrichPendingLinks(in: context)
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Catches links shared while Plutar wasn't running, and
                // ones the extension left half-done (e.g. app backgrounded
                // mid-fetch) — not just the cold-start case above.
                guard newPhase == .active else { return }
                Task { await BackupService.runAutomaticIfDue(in: context) }
                Task { await LinkMetadataEnricher.enrichPendingLinks(in: context) }
            }
            // The wake-up for an automatic backup that was put off for want
            // of a finished sync: each successful import re-asks.
            .onReceive(SyncMonitor.shared.importSucceeded) { _ in
                Task { await BackupService.runAutomaticIfDue(in: context) }
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
                // `@Query` is supposed to notice a store-level remote
                // change on its own, but a link that arrives already
                // fully enriched (the common case: the other device did
                // all the enrichment before this one synced) leaves
                // `enrichPendingLinks` below with nothing to save — and
                // with no save, nothing nudges this already-running
                // context to refetch, so the new row sits in the local
                // store invisible until the next launch — the "shows up
                // only after quitting and relaunching" symptom (a fresh
                // context fetches from scratch). `rollback()` has no unsaved
                // local changes to lose here — every mutation in this
                // app calls `persist()` synchronously right after — and
                // forces exactly that refetch.
                context.rollback()
                Task { await LinkMetadataEnricher.enrichPendingLinks(in: context) }
            }
    }
}
