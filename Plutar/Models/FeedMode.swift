import Foundation

/// Which of the three feeds — Date, Sources, Lus — is showing. Shared
/// between `RootView` (iOS) and `MacRootView`/`MacFeedList` (macOS), which
/// both group/filter `LinkItem`s the same way for a given mode.
enum FeedMode: String, CaseIterable {
    case chrono, source, read

    var label: String {
        switch self {
        case .chrono: return "À lire"
        case .source: return "Sources"
        case .read: return "Lus"
        }
    }

    var icon: String {
        switch self {
        case .chrono: return "list.bullet.clipboard"
        case .source: return "globe.fill"
        case .read: return "checkmark.circle"
        }
    }
}
