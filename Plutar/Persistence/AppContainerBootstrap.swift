import Foundation
import SwiftData

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

    static func makeContainer() -> Result {
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
