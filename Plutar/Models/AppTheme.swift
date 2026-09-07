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

/// One of the seven color themes from the mockup. Each theme is a background,
/// an "ink" (text) color used at several opacities, an accent, and the tones
/// used for cards / thumbnail placeholders / chips.
enum AppTheme: String, CaseIterable, Identifiable {
    case couchant, crepuscule, blanc, marine, scand, scandSoir, astronaute, astronauteSoir

    var id: String { rawValue }

    var label: String {
        switch self {
        case .couchant: return "Lacanau"
        case .crepuscule: return "Lacanau soir"
        case .scand: return "Copenhague"
        case .scandSoir: return "Copenhague soir"
        case .blanc: return "Marine clair"
        case .marine: return "Marine sombre"
        case .astronaute: return "Cap Canaveral"
        case .astronauteSoir: return "Cap Canaveral soir"
        }
    }

    var swatch: Color {
        switch self {
        case .couchant: return Color(hex: "#D95204")
        case .crepuscule: return Color(hex: "#3C2208")
        case .scand: return Color(hex: "#F4F1E9")
        case .scandSoir: return Color(hex: "#23262B")
        case .blanc: return Color(hex: "#FFFFFF")
        case .marine: return Color(hex: "#14264B")
        case .astronaute: return Color(hex: "#2E5D93")
        case .astronauteSoir: return Color(hex: "#0C1A2E")
        }
    }

    var background: Color {
        switch self {
        case .couchant: return Color(hex: "#EBE7DC")
        case .crepuscule: return Color(hex: "#4A2A0C")
        case .scand: return Color(hex: "#E2D7CC")
        case .scandSoir: return Color(hex: "#23262B")
        case .blanc: return Color(hex: "#FFFFFF")
        case .marine: return Color(hex: "#14264B")
        case .astronaute: return Color(hex: "#2E5D93")
        case .astronauteSoir: return Color(hex: "#0C1A2E")
        }
    }

    /// Base RGB used to derive the translucent "ink" tones (text at various opacities).
    private var inkRGB: (Double, Double, Double) {
        switch self {
        case .couchant: return (60, 34, 8)
        case .crepuscule: return (245, 198, 0)
        case .scand: return (43, 42, 40)
        case .scandSoir: return (230, 227, 220)
        case .blanc: return (20, 38, 75)
        case .marine: return (255, 255, 255)
        case .astronaute, .astronauteSoir: return (255, 255, 255)
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
        switch self {
        case .couchant: return Color(hex: "#D95204")
        case .crepuscule: return Color(hex: "#F2A626")
        case .scand, .scandSoir, .blanc, .marine, .astronaute, .astronauteSoir: return Color(hex: "#FF4F00")
        }
    }

    var accentSoft: Color {
        switch self {
        case .couchant: return Color(hex: "#F2A626")
        case .crepuscule: return Color(hex: "#E07B26")
        case .scand, .scandSoir, .blanc, .marine, .astronaute, .astronauteSoir: return Color(hex: "#FFA366")
        }
    }

    /// Diagonal-stripe thumbnail placeholder colors.
    var thumbnailStripes: (Color, Color) {
        switch self {
        case .couchant: return (Color(hex: "#F2A626"), Color(hex: "#E07B26"))
        case .crepuscule: return (Color(hex: "#5C3410"), Color(hex: "#4A2A0C"))
        case .scand: return (Color(hex: "#DCD5C6"), Color(hex: "#CFC7B6"))
        case .scandSoir: return (Color(hex: "#3A3F46"), Color(hex: "#2D3138"))
        case .blanc: return (Color(hex: "#E4E9F2"), Color(hex: "#D2DAE8"))
        case .marine: return (Color(hex: "#1F3763"), Color(hex: "#2A4780"))
        case .astronaute: return (Color(hex: "#3A6DA5"), Color(hex: "#27547F"))
        case .astronauteSoir: return (Color(hex: "#1B3350"), Color(hex: "#122740"))
        }
    }

    var card: Color {
        switch self {
        case .couchant: return Color(hex: "#F5F2E9")
        case .crepuscule: return Color(hex: "#9B4923")
        case .scand: return Color(hex: "#FBF8F3")
        case .scandSoir: return Color(hex: "#2D3138")
        case .blanc: return Color(hex: "#F3F6FB")
        case .marine: return Color(hex: "#1C3364")
        case .astronaute: return Color(hex: "#35699F")
        case .astronauteSoir: return Color(hex: "#142942")
        }
    }

    /// Lus-only override for a read link cell's background — nil means use
    /// the default (`card` tinted toward `background`, see LinkRowView).
    /// Cap Canaveral (and its dark variant) use a plain medium gray instead.
    var readCardOverride: Color? {
        switch self {
        case .astronaute, .astronauteSoir: return Color(hex: "#8E8E93")
        default: return nil
        }
    }

    /// Sticky day/source-name pill AND counter badge background — each
    /// theme's own color, except Copenhague's dedicated "bleu scandinave"
    /// (shared with its dark variant), which isn't used by any other theme.
    var chip: Color {
        switch self {
        case .couchant: return Color(hex: "#8C3F12")
        case .crepuscule: return Color(hex: "#D8460B")
        case .scand, .scandSoir: return Color(hex: "#6E8CA0")
        case .blanc: return Color(hex: "#14264B")
        case .marine, .astronaute, .astronauteSoir: return Color(hex: "#FF4F00")
        }
    }

    /// Text color drawn on top of `chip` (and the counter badge) — white for
    /// Cap Canaveral and Copenhague (plus their dark variants), whose
    /// `background` is too close in value to `chip` to read well; each
    /// other theme's own background otherwise.
    var chipText: Color {
        switch self {
        case .astronaute, .scand: return .white
        case .astronauteSoir: return AppTheme.marine.background
        case .crepuscule: return AppTheme.couchant.title
        // Copenhague soir: its own (dark) background, darker than plain
        // white but still readable on the bleu-scandinave chip.
        default: return background
        }
    }

    var time: Color {
        switch self {
        case .couchant: return Color(hex: "#B04A12")
        case .crepuscule: return Color(hex: "#F2A626")
        case .astronaute, .astronauteSoir: return Color(hex: "#FF4F00")
        default: return ink(1)
        }
    }

    var title: Color {
        switch self {
        case .couchant: return Color(hex: "#3C2208")
        case .crepuscule: return Color(hex: "#F5C600")
        case .astronaute, .astronauteSoir: return .white
        default: return ink(1)
        }
    }

    var countForeground: Color {
        switch self {
        case .couchant: return Color(hex: "#EBE7DC")
        case .crepuscule: return AppTheme.couchant.title
        case .astronaute, .scand: return .white
        case .astronauteSoir: return AppTheme.marine.background
        // Copenhague soir falls through to `background` too — see chipText.
        default: return background
        }
    }
}

/// Typeface choice from the settings drawer. All three are available on stock iOS.
enum AppFont: String, CaseIterable, Identifiable {
    case futura, rounded, avenirNext

    var id: String { rawValue }

    var label: String {
        switch self {
        case .futura: return "Futura"
        case .rounded: return "SF Pro"
        case .avenirNext: return "Avenir Next"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .futura: return .custom("Futura", size: size).weight(weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        // Fixed to its own named DemiBold variant, ignoring `weight` —
        // like Futura, ".weight()" doesn't reliably resolve to a real
        // bold/regular variant for a named custom font.
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
