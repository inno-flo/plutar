import Foundation

/// The `@AppStorage`/`UserDefaults` key for every per-device display
/// setting — theme, appearance, font, layout, etc. `RootView` (iOS),
/// `MacRootView`, and `MacSettingsView` each declare their own
/// `@AppStorage` properties for these (the property-wrapper model doesn't
/// let them share one *instance*), but previously each also retyped the raw
/// key string, so renaming one only had to be missed in one of the three
/// places to leave platforms silently reading/writing different keys. Using
/// these constants at every `@AppStorage(...)` site instead means a rename
/// happens here, once, and the compiler enforces every call site picks it up.
///
/// Deliberately not the values themselves (`AppTheme.scand`, `.auto`, …) —
/// those defaults are already typed enum cases at each `@AppStorage`
/// declaration site, not string literals, so they don't have the same
/// drift risk this addresses.
enum DisplaySettingsKey {
    static let theme = "plutar.theme"
    static let appearance = "plutar.appearance"
    static let font = "plutar.font"
    static let layout = "plutar.layout"
    /// macOS only — last active sidebar section (`SidebarSelection.storageKey`).
    static let sidebarSelection = "plutar.sidebarSelection"
    static let blackSoirBackground = "plutar.blackSoirBackground"
    /// iOS-only — no shake gesture on macOS, so only `RootView` reads this.
    static let shakeToChangeTheme = "plutar.shakeToChangeTheme"
    /// Lus's globe/calendar toggle (`MacFeedList` on macOS, `RootView` on
    /// iOS/iPadOS), whether it's currently grouped by source instead of by
    /// day. Per-device like the rest of this enum, so each platform reading/
    /// writing the same key name is fine — it's never the same store.
    static let readGroupedBySource = "plutar.macReadGroupedBySource"
}
