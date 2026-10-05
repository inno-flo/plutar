import SwiftUI

/// Holds each feed view's last scroll offset, keyed by view. A plain
/// reference type on purpose (not `@Observable`/`@State` content): offsets
/// are written on every scroll frame, which must not invalidate any view.
/// Owned by `RootView` (iOS/iPadOS) and `MacRootView` (macOS) via `@State`,
/// so it outlives the feed list it remembers.
final class ScrollOffsetStore {
    var offsets: [String: CGFloat] = [:]
}

private struct RememberScrollOffset: ViewModifier {
    let store: ScrollOffsetStore
    let key: String
    /// Owned by the caller, so it can also drive scrolling itself.
    @Binding var position: ScrollPosition
    /// True from the moment `key` changes (or the view appears) until the
    /// saved offset has been re-applied — the offsets reported while the
    /// list swaps its content would otherwise overwrite the saved one.
    @State private var isRestoring = true

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                if !isRestoring { store.offsets[key] = offset }
            }
            .task(id: key) {
                isRestoring = true
                // Let the list lay out its new content before scrolling.
                try? await Task.sleep(for: .milliseconds(120))
                if let saved = store.offsets[key] {
                    position.scrollTo(y: saved)
                    try? await Task.sleep(for: .milliseconds(120))
                }
                isRestoring = false
            }
    }
}

extension View {
    /// Remembers this scroll view's offset under `key` in `store` and
    /// restores it when the view (re)appears or `key` changes — so
    /// switching to another view and back lands where the user left off.
    func rememberScrollOffset(in store: ScrollOffsetStore, key: String, position: Binding<ScrollPosition>) -> some View {
        modifier(RememberScrollOffset(store: store, key: key, position: position))
    }
}
