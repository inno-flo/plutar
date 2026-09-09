import SwiftUI

extension Color {
    /// Convenience initializer from a "#RRGGBB" or "#RRGGBBAA" hex string.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r: Double
        let g: Double
        let b: Double
        let a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

/// One of the color themes from the mockup. Each theme is a background,
/// an "ink" (text) color used at several opacities, an accent, and the tones
/// used for cards / thumbnail placeholders / chips.
enum AppTheme: String, CaseIterable, Identifiable {
    case tokyo, tokyoSoir, scand, scandSoir, blanc, blancSoir, astronaute, astronauteSoir

    /// Themes offered in the Affichage picker — every case.
    static var selectable: [AppTheme] { allCases }

    /// Whether this is a "soir" (dark) variant of another theme.
    var isSoir: Bool {
        switch self {
        case .scandSoir, .blancSoir, .astronauteSoir, .tokyoSoir: return true
        default: return false
        }
    }

    /// This theme's light-mode counterpart (itself if already light) — used
    /// to resolve the "Apparence" setting to an actual theme to display.
    var lightVariant: AppTheme {
        switch self {
        case .tokyoSoir: return .tokyo
        case .scandSoir: return .scand
        case .blancSoir: return .blanc
        case .astronauteSoir: return .astronaute
        default: return self
        }
    }

    /// This theme's "soir" (dark) counterpart (itself if already soir) —
    /// used to resolve the "Apparence" setting to an actual theme to display.
    var soirVariant: AppTheme {
        switch self {
        case .tokyo: return .tokyoSoir
        case .scand: return .scandSoir
        case .blanc: return .blancSoir
        case .astronaute: return .astronauteSoir
        default: return self
        }
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scand: return "Copenhague"
        case .scandSoir: return "Copenhague nuit"
        case .blanc: return "Kamakura"
        case .blancSoir: return "Kamakura nuit"
        case .astronaute: return "Cap Canaveral"
        case .astronauteSoir: return "Cap Canaveral nuit"
        case .tokyo: return "Tokyo"
        case .tokyoSoir: return "Tokyo nuit"
        }
    }

    var background: Color {
        switch self {
        case .scand: return Color(hex: "#E2D7CC")
        case .scandSoir: return Color(hex: "#23262B")
        case .blanc: return Color(hex: "#E4F1FF")
        case .blancSoir: return Color(hex: "#101B2C")
        case .astronaute: return Color(hex: "#2E5D93")
        case .astronauteSoir: return Color(hex: "#0C1A2E")
        case .tokyo: return Color(hex: "#F7F5F1")
        case .tokyoSoir: return Color(hex: "#000000")
        }
    }

    /// Base RGB used to derive the translucent "ink" tones (text at various opacities).
    private var inkRGB: (Double, Double, Double) {
        switch self {
        case .scand: return (43, 42, 40)
        case .scandSoir: return (230, 227, 220)
        case .blanc: return (20, 38, 75)
        case .blancSoir: return (225, 235, 245)
        case .astronaute, .astronauteSoir: return (255, 255, 255)
        case .tokyo: return (34, 34, 34)
        case .tokyoSoir: return (237, 237, 237)
        }
    }

    func ink(_ opacity: Double = 1) -> Color {
        let (r, g, b) = inkRGB
        return Color(red: r / 255, green: g / 255, blue: b / 255, opacity: opacity)
    }

    var accent: Color {
        Color(hex: "#FF4F00")
    }

    var accentSoft: Color {
        Color(hex: "#FFA366")
    }

    /// Diagonal-stripe thumbnail placeholder colors.
    var thumbnailStripes: (Color, Color) {
        switch self {
        case .scand: return (Color(hex: "#DCD5C6"), Color(hex: "#CFC7B6"))
        case .scandSoir: return (Color(hex: "#3A3F46"), Color(hex: "#2D3138"))
        case .blanc: return (Color(hex: "#E4E9F2"), Color(hex: "#D2DAE8"))
        case .blancSoir: return (Color(hex: "#16243A"), Color(hex: "#0F1B2C"))
        case .astronaute: return (Color(hex: "#3A6DA5"), Color(hex: "#27547F"))
        case .astronauteSoir: return (Color(hex: "#1B3350"), Color(hex: "#122740"))
        case .tokyo: return (Color(hex: "#F7F5F1"), Color(hex: "#EFEBE4"))
        case .tokyoSoir: return (Color(hex: "#1E1E1E"), Color(hex: "#171717"))
        }
    }

    var card: Color {
        switch self {
        case .scand: return Color(hex: "#FBF8F3")
        case .scandSoir: return Color(hex: "#2D3138")
        case .blanc: return Color(hex: "#FFFFFF")
        case .blancSoir: return Color(hex: "#1A2940")
        case .astronaute: return Color(hex: "#5F8FC7")
        case .astronauteSoir: return Color(hex: "#142942")
        case .tokyo: return Color(hex: "#FFFFFF")
        case .tokyoSoir: return Color(hex: "#1E1E1E")
        }
    }

    /// Lus-only override for a read link cell's background — nil means use
    /// the default (`card` tinted toward `background`, see LinkRowView).
    /// Cap Canaveral itself uses its former `card` blue, swapped with
    /// `card` itself. Cap Canaveral soir has no override of its own — like
    /// every other soir theme, it falls through to that same default.
    var readCardOverride: Color? {
        switch self {
        case .astronaute: return Color(hex: "#35699F")
        // Kamakura's own bluish Lus tint.
        case .blanc: return Color(hex: "#D1E2F9")
        // Copenhague's own beige Lus tint — previously had no override
        // here (its Lus tone was just `card` tinted toward `background`,
        // see LinkRowView), which worked out to about this color.
        case .scand: return Color(hex: "#ECE4DC")
        default: return nil
        }
    }

    /// Sticky day/source-name pill AND counter badge background — each
    /// theme's own color. Every "nuit" variant now uses a darker tone of its
    /// light counterpart's color, rather than sharing the exact same value.
    var chip: Color {
        switch self {
        case .scand: return Color(hex: "#6E8CA0")
        case .scandSoir: return Color(hex: "#4A6270")
        case .blanc: return Color(hex: "#7FACCC")
        case .blancSoir: return Color(hex: "#4F7AA8")
        case .astronaute: return Color(hex: "#FF4F00")
        case .astronauteSoir: return Color(hex: "#C23D00")
        // Tokyo's pill swapped hues with its counter badge: black here
        // (was red), a near-black gray in soir (was dark red) — see
        // `RootView.counterBackgroundOverride` for the other half of the
        // swap.
        case .tokyo: return .black
        case .tokyoSoir: return Color(hex: "#2B2B2B")
        }
    }

    /// Text color drawn on top of `chip` (and the counter badge) — white for
    /// Cap Canaveral and Copenhague, whose `background` is too close in
    /// value to `chip` to read well; each other theme's own background
    /// otherwise.
    var chipText: Color {
        switch self {
        // Contrast audit: soir chipText used to go dark-on-dark here
        // (navy-on-orange ~2.8:1, black-on-red ~3.2:1) — both now match
        // their light counterpart's white-on-saturated pattern instead.
        case .astronaute, .scand, .tokyo, .astronauteSoir, .tokyoSoir: return .white
        case .blanc: return Color(hex: "#E1F3FC")
        // Copenhague soir and Kamakura soir: each falls through to its own
        // (dark) background — darker than the light variant's pale text,
        // but still readable on the shared chip color.
        default: return background
        }
    }

    /// Trailing swipe-to-delete tint (Date/Sources/Lus) — nil uses the
    /// system's own destructive red. Kamakura gets its own red, Kamakura
    /// soir a darker one. Cap Canaveral soir and Copenhague soir also get
    /// that same darker red.
    var deleteSwipeTint: Color? {
        switch self {
        case .blanc: return Color(hex: "#E53935")
        case .blancSoir: return Color(hex: "#7A1F1F")
        case .astronauteSoir, .scandSoir, .tokyoSoir: return Color(hex: "#8C2F2F")
        case .tokyo: return Color(hex: "#E1000F")
        default: return nil
        }
    }

    /// Leading swipe "Non lu" (mark as unread) tint in Lus — plain system
    /// green by default; Kamakura soir, Cap Canaveral soir, Copenhague soir
    /// and Tokyo soir use a darker green instead.
    var markUnreadSwipeTint: Color {
        switch self {
        case .blancSoir, .astronauteSoir, .scandSoir, .tokyoSoir: return Color(hex: "#1F5C33")
        default: return .green
        }
    }

    /// Leading swipe "Lu" (mark as read) tint in Date/Sources — plain gray
    /// by default. Kamakura uses its own lighter blue; Copenhague uses a
    /// lighter tone of its own ink color; Kamakura soir still uses its
    /// `card` color (the same background as a link cell in Lus); Cap
    /// Canaveral soir and Copenhague soir use a darker gray.
    var markReadSwipeTint: Color {
        switch self {
        case .blanc: return Color(hex: "#72A8F6")
        case .scand: return Color(hex: "#6E6962")
        case .blancSoir: return readCardOverride ?? card
        case .astronauteSoir: return Color(hex: "#4A4A4E")
        case .scandSoir: return Color(hex: "#4A4A4E")
        default: return .gray
        }
    }

    var title: Color {
        switch self {
        case .astronaute, .astronauteSoir: return .white
        default: return ink(1)
        }
    }

    var countForeground: Color {
        switch self {
        case .astronaute, .scand, .tokyo, .astronauteSoir, .tokyoSoir: return .white
        case .blanc: return Color(hex: "#E1F3FC")
        // Copenhague soir falls through to `background` too — see chipText.
        default: return background
        }
    }
}

/// Light/soir selector from the settings drawer. "Claire" forces the active
/// theme's light variant, "Sombre" forces its soir variant, and
/// "Automatique" switches between the two based on the system's own active
/// appearance setting — see `RootView.theme`, which resolves the raw
/// selected `AppTheme` and this setting into the theme actually displayed.
enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Claire"
        case .dark: return "Sombre"
        case .auto: return "Automatique"
        }
    }

    /// Value to pass to `.preferredColorScheme` — nil for "Automatique"
    /// lets the system's active appearance take over.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}

/// Typeface choice from the settings drawer, all available on stock iOS.
/// SF Pro (`.rounded`) is the default.
enum AppFont: String, CaseIterable, Identifiable {
    case rounded, sfCompact, helvetica

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rounded: return "SF Pro"
        case .sfCompact: return "SF Compact"
        case .helvetica: return "Helvetica"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        // Fixed to its plain (Regular) style, ignoring `weight`.
        case .sfCompact: return .custom("SFCompactDisplay-Regular", size: size)
        // Helvetica Neue, fixed to its Bold style, ignoring `weight`.
        case .helvetica: return .custom("HelveticaNeue-Bold", size: size)
        }
    }
}

/// The three timeline layouts from the mockup's settings drawer.
enum LinkLayout: String, CaseIterable, Identifiable {
    case rail, card, editorial

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rail: return "Simple"
        case .card: return "Détaillée"
        case .editorial: return "Éditoriale"
        }
    }
}
