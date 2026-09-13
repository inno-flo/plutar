import Foundation
import OSLog

/// Shared loggers. Store writes used to be swallowed by `try?` at a dozen
/// call sites, so a failure to persist left no trace at all — not in the UI,
/// not in the console. Everything that touches the store reports here.
///
/// Lives in `Persistence/` (rather than the iOS-only `App/PlutarApp.swift`
/// it started in) so every target that saves to the store — both apps and
/// both share extensions — can use it.
enum PlutarLog {
    static let store = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Plutar",
        category: "store"
    )

    /// Used by both `PlutarShare` and `PlutarShareMac` to log when a share
    /// couldn't be turned into a link — otherwise the only trace is the
    /// generic "aucun lien n'a été trouvé" message shown to the user, with
    /// no way to tell which of several possible causes it was.
    static let shareExtension = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Plutar",
        category: "shareExtension"
    )
}
