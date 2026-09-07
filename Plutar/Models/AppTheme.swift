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
    case blanc, blancSoir, scand, scandSoir, astronaute, astronauteSoir, leMans, leMansSoir

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scand: return "Copenhague"
        case .scandSoir: return "Copenhague soir"
        case .blanc: return "Kamakura"
        case .blancSoir: return "Kamakura soir"
        case .astronaute: return "Cap Canaveral"
        case .astronauteSoir: return "Cap Canaveral soir"
        case .leMans: return "Le Mans"
        case .leMansSoir: return "Le Mans soir"
        }
    }

    var swatch: Color {
        switch self {
        case .scand: return Color(hex: "#F4F1E9")
        case .scandSoir: return Color(hex: "#23262B")
        case .blanc: return Color(hex: "#E4F1FF")
        case .blancSoir: return Color(hex: "#101B2C")
        case .astronaute: return Color(hex: "#2E5D93")
        case .astronauteSoir: return Color(hex: "#0C1A2E")
        case .leMans: return Color(hex: "#FFFFFF")
        case .leMansSoir: return Color(hex: "#23262B")
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
        case .leMans: return Color(hex: "#FFFFFF")
        case .leMansSoir: return Color(hex: "#23262B")
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
        case .leMans: return (12, 22, 29)
        case .leMansSoir: return (242, 232, 224)
        }
    }

    func ink(_ opacity: Double = 1) -> Color {
        let (r, g, b) = inkRGB
        return Color(red: r / 255, green: g / 255, blue: b / 255, opacity: opacity)
    }

    var isDark: Bool {
        let (r, g, b) = inkRGB
        return (r * 299 + g * 587 + b * 114) / 1000 > 140
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
        case .leMans: return (Color(hex: "#DCEBFA"), Color(hex: "#C7DCF0"))
        case .leMansSoir: return (Color(hex: "#96481E"), Color(hex: "#7E3B18"))
        }
    }

    var card: Color {
        switch self {
        case .scand: return Color(hex: "#FBF8F3")
        case .scandSoir: return Color(hex: "#2D3138")
        case .blanc: return Color(hex: "#FFFFFF")
        case .blancSoir: return Color(hex: "#1A2940")
        case .astronaute: return Color(hex: "#35699F")
        case .astronauteSoir: return Color(hex: "#142942")
        case .leMans: return Color(hex: "#DCEBFA")
        case .leMansSoir: return Color(hex: "#96481E")
        }
    }

    /// Lus-only override for a read link cell's background — nil means use
    /// the default (`card` tinted toward `background`, see LinkRowView).
    /// Cap Canaveral (and its dark variant) use a plain medium gray instead.
    var readCardOverride: Color? {
        switch self {
        case .astronaute: return Color(hex: "#8E8E93")
        // A darker gray than Cap Canaveral's own, for better contrast
        // against the dark background.
        case .astronauteSoir: return Color(hex: "#4A4A4E")
        // Keeps Lus at the slightly-darkened tone from before, now that
        // `card` itself (Date/Sources' unread background) is plain white.
        case .blanc: return Color(hex: "#E7EAEE")
        default: return nil
        }
    }

    /// Sticky day/source-name pill AND counter badge background — each
    /// theme's own color, except Copenhague's dedicated "bleu scandinave"
    /// (shared with its dark variant), which isn't used by any other theme.
    var chip: Color {
        switch self {
        case .scand, .scandSoir: return Color(hex: "#6E8CA0")
        case .blanc, .blancSoir: return Color(hex: "#7FACCC")
        case .astronaute, .astronauteSoir: return Color(hex: "#FF4F00")
        case .leMans: return Color(hex: "#D17132")
        case .leMansSoir: return Color(hex: "#96481E")
        }
    }

    /// Text color drawn on top of `chip` (and the counter badge) — white for
    /// Cap Canaveral and Copenhague, whose `background` is too close in
    /// value to `chip` to read well; each other theme's own background
    /// otherwise.
    var chipText: Color {
        switch self {
        case .astronaute, .scand, .leMans: return .white
        // Cap Canaveral soir's own chip/counter text, matching what the
        // (now-removed) Marine sombre theme used to use.
        case .astronauteSoir: return Color(hex: "#14264B")
        case .blanc: return Color(hex: "#E1F3FC")
        // Le Mans soir's chip is the same dark brown as `card`, too close in
        // value to fall through to `background` like the other soir themes.
        case .leMansSoir: return ink(1)
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
        case .astronauteSoir, .scandSoir: return Color(hex: "#8C2F2F")
        default: return nil
        }
    }

    /// Leading swipe "Non lu" (mark as unread) tint in Lus — plain system
    /// green by default; Kamakura soir, Cap Canaveral soir and Copenhague
    /// soir use a darker green instead.
    var markUnreadSwipeTint: Color {
        switch self {
        case .blancSoir, .astronauteSoir, .scandSoir: return Color(hex: "#1F5C33")
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
        case .astronauteSoir: return readCardOverride ?? .gray
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
        case .astronaute, .scand, .leMans: return .white
        case .astronauteSoir: return Color(hex: "#14264B")
        case .blanc: return Color(hex: "#E1F3FC")
        // Le Mans soir — see chipText.
        case .leMansSoir: return ink(1)
        // Copenhague soir falls through to `background` too — see chipText.
        default: return background
        }
    }
}

/// Typeface choice from the settings drawer. Both are available on stock iOS.
enum AppFont: String, CaseIterable, Identifiable {
    case rounded, avenirNext

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rounded: return "SF Pro"
        case .avenirNext: return "Avenir Next"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        // Fixed to its own named DemiBold variant, ignoring `weight` —
        // ".weight()" doesn't reliably resolve to a real bold/regular
        // variant for a named custom font.
        case .avenirNext: return .custom("AvenirNext-DemiBold", size: size)
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
