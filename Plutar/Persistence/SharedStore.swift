import Foundation
import SwiftData

/// Builds the `ModelContainer` shared between the main app and the
/// PlutarShare extension, so a link saved from the share sheet shows up in
/// the app without either process needing to relaunch the other.
///
/// Both targets need to agree on the exact same on-disk location, which is
/// why this lives in one file compiled into both (see `project.yml`) rather
/// than being duplicated.
enum SharedStore {
    /// Must match the App Group entitlement on both the app and the
    /// extension targets.
    static let appGroupID = "group.com.innoflo.plutar"

    enum StoreError: Error {
        case missingAppGroupContainer
    }

    /// The container the app and extension both read from and write to.
    /// Throws (rather than falling back silently) when the App Group isn't
    /// available — the app already has its own in-memory fallback for that
    /// case; the extension surfaces the error to the user instead.
    static func makeContainer() throws -> ModelContainer {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            throw StoreError.missingAppGroupContainer
        }
        let storeURL = groupURL.appendingPathComponent("Plutar.sqlite")
        let configuration = ModelConfiguration(url: storeURL)
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
