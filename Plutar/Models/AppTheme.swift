import SwiftUI

extension Color {
    /// Convenience initializer from a "#RRGGBB" hex string.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// One of the seven color themes from the mockup. Each theme is a background,
/// an "ink" (text) color used at several opacities, an accent, and the tones
/// used for cards / thumbnail placeholders / chips.
enum AppTheme: String, CaseIterable, Identifiable {
    case couchant, crepuscule, creme, blanc, marine, astronaute

    var id: String { rawValue }

    var label: String {
        switch self {
        case .couchant: return "Couchant"
        case .crepuscule: return "Crépuscule"
        case .creme: return "Crème"
        case .blanc: return "Blanc"
        case .marine: return "Marine"
        case .astronaute: return "Astronaute"
        }
    }

    var swatch: Color {
        switch self {
        case .couchant: return Color(hex: "#D95204")
        case .crepuscule: return Color(hex: "#3C2208")
        case .creme: return Color(hex: "#F4F1E9")
        case .blanc: return Color(hex: "#FFFFFF")
        case .marine: return Color(hex: "#14264B")
        case .astronaute: return Color(hex: "#2E5D93")
        }
    }

    var background: Color {
        switch self {
        case .couchant: return Color(hex: "#EBE7DC")
        case .crepuscule: return Color(hex: "#3C2208")
        case .creme: return Color(hex: "#F4F1E9")
        case .blanc: return Color(hex: "#FFFFFF")
        case .marine: return Color(hex: "#14264B")
        case .astronaute: return Color(hex: "#2E5D93")
        }
    }

    /// Base RGB used to derive the translucent "ink" tones (text at various opacities).
    private var inkRGB: (Double, Double, Double) {
        switch self {
        case .couchant: return (60, 34, 8)
        case .crepuscule: return (235, 231, 220)
        case .creme: return (22, 21, 15)
        case .blanc: return (20, 38, 75)
        case .marine: return (255, 255, 255)
        case .astronaute: return (255, 255, 255)
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
        case .creme, .blanc, .marine, .astronaute: return Color(hex: "#FF4F00")
        }
    }

    var accentSoft: Color {
        switch self {
        case .couchant: return Color(hex: "#F2A626")
        case .crepuscule: return Color(hex: "#E07B26")
        case .creme, .blanc, .marine, .astronaute: return Color(hex: "#FFA366")
        }
    }

    /// Diagonal-stripe thumbnail placeholder colors.
    var thumbnailStripes: (Color, Color) {
        switch self {
        case .couchant: return (Color(hex: "#F2A626"), Color(hex: "#E07B26"))
        case .crepuscule: return (Color(hex: "#5C3410"), Color(hex: "#4A2A0C"))
        case .creme: return (Color(hex: "#DCD5C6"), Color(hex: "#CFC7B6"))
        case .blanc: return (Color(hex: "#E4E9F2"), Color(hex: "#D2DAE8"))
        case .marine: return (Color(hex: "#1F3763"), Color(hex: "#2A4780"))
        case .astronaute: return (Color(hex: "#3A6DA5"), Color(hex: "#27547F"))
        }
    }

    var card: Color {
        switch self {
        case .couchant: return Color(hex: "#F5F2E9")
        case .crepuscule: return Color(hex: "#4A2A0C")
        case .creme: return Color(hex: "#FFFDF6")
        case .blanc: return Color(hex: "#F3F6FB")
        case .marine: return Color(hex: "#1C3364")
        case .astronaute: return Color(hex: "#35699F")
        }
    }

    /// Sticky day-group (or source) pill background.
    var chip: Color {
        switch self {
        case .couchant: return Color(hex: "#8C3F12")
        case .crepuscule: return Color(hex: "#D95204")
        case .creme: return Color(hex: "#16150F")
        case .blanc: return Color(hex: "#14264B")
        case .marine, .astronaute: return Color(hex: "#FF4F00")
        }
    }

    /// Text color drawn on top of `chip` — white for Astronaute, whose
    /// `background` (the default choice) is too close in value to `chip`'s
    /// orange to read well.
    var chipText: Color {
        switch self {
        case .astronaute: return .white
        default: return background
        }
    }

    var time: Color {
        switch self {
        case .couchant: return Color(hex: "#B04A12")
        case .crepuscule: return Color(hex: "#F2A626")
        case .astronaute: return Color(hex: "#FF4F00")
        default: return ink(1)
        }
    }

    var title: Color {
        switch self {
        case .couchant: return Color(hex: "#3C2208")
        case .crepuscule: return Color(hex: "#F5EFE2")
        case .astronaute: return .white
        default: return ink(1)
        }
    }

    var tabActive: Color {
        switch self {
        case .couchant: return Color(hex: "#D95204")
        case .crepuscule: return Color(hex: "#F2A626")
        case .astronaute: return .white
        default: return accent
        }
    }

    var countForeground: Color {
        switch self {
        case .couchant: return Color(hex: "#EBE7DC")
        case .crepuscule: return Color(hex: "#3C2208")
        case .astronaute: return .white
        default: return background
        }
    }
}

/// Typeface choice from the settings drawer. Both are available on stock iOS.
enum AppFont: String, CaseIterable, Identifiable {
    case futura, rounded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .futura: return "Futura"
        case .rounded: return "Rounded"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .futura: return .custom("Futura", size: size).weight(weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
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
        case .card: return "Détaillées"
        case .editorial: return "Éditoriale"
        }
    }
}
