import Foundation
import SwiftData

/// Builds the `ModelContainer` shared between the main app and the
/// PlutarShare extension (iOS and macOS alike), so a link saved from the
/// share sheet shows up in the app without either process needing to
/// relaunch the other, and — via the CloudKit-backed configuration below —
/// syncs across every device signed into the same iCloud account.
///
/// All four targets (Plutar, PlutarShare, PlutarMac, PlutarShareMac) need to
/// agree on the exact same on-disk location and CloudKit container, which is
/// why this lives in one file compiled into all of them (see `project.yml`)
/// rather than being duplicated.
enum SharedStore {
    /// Must match the App Group entitlement on every target — anchored once
    /// as `&appGroupID` in `project.yml` (on the `Plutar` target) and
    /// referenced via `*appGroupID` by the other three, so there's one
    /// place on the YAML side to rename; this Swift constant is the one
    /// place on the Swift side, since an anchor can't reach across into
    /// source code.
    static let appGroupID = "group.com.innoflo.plutar"

    /// Must match `com.apple.developer.icloud-container-identifiers` on
    /// every target — anchored once as `&cloudKitContainerID` in
    /// `project.yml`, same as `appGroupID` above.
    static let cloudKitContainerID = "iCloud.com.innoflo.plutar"

    enum StoreError: Error {
        case missingAppGroupContainer
    }

    /// The container every app/extension process reads from and writes to.
    /// Throws (rather than falling back silently) when the App Group isn't
    /// available — the app already has its own in-memory fallback for that
    /// case; the extension surfaces the error to the user instead.
    ///
    /// The on-disk location stays the same App Group SQLite file as before
    /// CloudKit was added — it's still what gives same-device app↔extension
    /// sharing its immediate, no-round-trip behavior. `cloudKitDatabase:`
    /// only adds background sync of that same local store to other devices
    /// signed into the same iCloud account; it doesn't change where the
    /// local cache lives.
    static func makeContainer() throws -> ModelContainer {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            throw StoreError.missingAppGroupContainer
        }
        let storeURL = groupURL.appendingPathComponent("Plutar.sqlite")
        let configuration = ModelConfiguration(
            url: storeURL,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: LinkItem.self, SourceRank.self, configurations: configuration)
    }

    /// Where `LinkMetadataEnricher` saves downloaded preview images, keyed
    /// by `LinkItem.id`. In the App Group container (not the app's own
    /// Documents/Caches) so it's readable regardless of which process — app
    /// or extension — writes it.
    static func thumbnailsDirectoryURL() -> URL? {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            return nil
        }
        let directory = groupURL.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
