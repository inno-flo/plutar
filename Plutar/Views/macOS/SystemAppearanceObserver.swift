import AppKit
import Combine
import SwiftUI

/// Tracks macOS's system-wide light/dark Appearance setting independently of
/// SwiftUI's own `\.colorScheme` environment value.
///
/// `MacRootView` can't use `@Environment(\.colorScheme)` for this the way
/// `MacSettingsView` does: it also forces `.preferredColorScheme` on that
/// same window (to recolor native title-bar/toolbar text for a couple of
/// themes — see `MacRootView.windowAppearanceIsDark`). Once forced, that
/// window's own `\.colorScheme` environment reports back the forced value
/// instead of the system's live one on the next render — effectively
/// latching it, so "Automatique" never notices a later real toggle in
/// System Settings > Général > Apparence again. `NSApp.effectiveAppearance`
/// isn't affected by one window's own appearance override, so observing it
/// here instead stays a clean, uncorrupted signal.
final class SystemAppearanceObserver: ObservableObject {
    @Published private(set) var colorScheme: ColorScheme

    private var observation: NSKeyValueObservation?

    init() {
        colorScheme = Self.resolve(NSApp.effectiveAppearance)
        observation = NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            let resolved = Self.resolve(app.effectiveAppearance)
            DispatchQueue.main.async { self?.colorScheme = resolved }
        }
    }

    private static func resolve(_ appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}
