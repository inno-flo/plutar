import Foundation

/// What's selected in the macOS sidebar (`MacSidebarView`) and therefore
/// shown in `MacRootView`'s detail column. Unlike iOS's `FeedMode`, which
/// only distinguishes Date/Sources/Lus, `.source` here carries the specific
/// host the user picked — the sidebar lists sources individually rather than
/// bundling them behind one "Sources" screen.
enum SidebarSelection: Hashable {
    case date
    case read
    case source(String)
    /// The standing "most shared sources" ranking (`SourceRank`) — its own
    /// row inside the Sources disclosure group, alongside the individual
    /// hosts rather than one of them.
    case ranking
}

extension SidebarSelection {
    /// String form persisted in `@AppStorage` so the macOS app reopens on the
    /// section that was active at quit — see `MacRootView`.
    var storageKey: String {
        switch self {
        case .date: return "date"
        case .read: return "read"
        case .ranking: return "ranking"
        case .source(let host): return "source:\(host)"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "date": self = .date
        case "read": self = .read
        case "ranking": self = .ranking
        default:
            guard storageKey.hasPrefix("source:") else { return nil }
            self = .source(String(storageKey.dropFirst("source:".count)))
        }
    }
}
