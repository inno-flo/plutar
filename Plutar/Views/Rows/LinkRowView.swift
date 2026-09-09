import SwiftUI

/// Renders one `LinkItem` in whichever of the three timeline layouts is
/// currently selected (rail / card / editorial).
struct LinkRowView: View {
    let item: LinkItem
    let layout: LinkLayout
    let theme: AppTheme
    let appFont: AppFont
    let showThumbnails: Bool
    let showFavicons: Bool

    private var viaString: String { "via \(item.sourceApp)" }
    private var showThumbnail: Bool { item.hasThumbnail && showThumbnails }

    /// Rounded is a real system weight variant and renders this bold fine;
    /// SF Compact ignores it entirely (fixed to its own Regular style
    /// regardless of what's passed), so titles stay at Regular weight there.
    private var titleWeight: Font.Weight { .bold }

    var body: some View {
        Group {
            switch layout {
            case .rail: railBody
            case .card: cardBody
            case .editorial: editorialBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, layout == .editorial ? 16 : 16)
        .padding(.horizontal, 18)
        .background(item.isRead ? (theme.readCardOverride ?? theme.card) : theme.card)
        // In Lus (every cell here is read), the title drops down to the
        // same muted tone as the host/"via" line below it instead of the
        // theme's full-strength title color.
        .foregroundStyle(item.isRead ? theme.ink(0.52) : theme.title)
        // A read cell (i.e. every cell in Lus) is tinted toward the page's
        // own background instead of just made transparent — plain opacity
        // makes the cell blend with whatever scrolls behind it, which reads
        // inconsistently from theme to theme; blending toward a color the
        // theme already defines gives a real, consistently muted tone.
        // Skipped when the theme provides its own flat `readCardOverride`
        // (Cap Canaveral uses a plain medium gray instead).
        .overlay {
            if item.isRead && theme.readCardOverride == nil {
                theme.background.opacity(0.6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Skipped when the theme provides its own flat `readCardOverride` —
        // otherwise this desaturates that color too, washing e.g. Cap
        // Canaveral's light blue down to a gray indistinguishable from
        // before.
        .saturation(item.isRead && theme.readCardOverride == nil ? 0 : 1)
        // No shadow on read cells (all of Lus) — it read as too heavy on an
        // already muted/desaturated card.
        .shadow(color: item.isRead ? .clear : .black.opacity(0.08), radius: 9, y: 4)
    }

    // MARK: Rail (default) — just the title, host below, nothing else.

    private var railBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.title)
                .font(appFont.font(size: 18, weight: titleWeight))
                .lineLimit(3)
            hostRow
        }
    }

    // MARK: Card — favicon + title, host below, thumbnail on the right.

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 14) {
            if showFavicons {
                favicon(size: 18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(appFont.font(size: 18, weight: titleWeight))
                    .lineLimit(3)
                hostRow
            }
            Spacer(minLength: 0)
            if showThumbnail {
                thumbnail(size: 86)
            }
        }
    }

    // MARK: Editorial — big thumbnail on top, title, excerpt below.

    private var editorialBody: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                if showFavicons {
                    favicon(size: 22)
                }
                hostRow
            }
            if showThumbnail {
                thumbnail(size: 150, fullWidth: true)
            }
            Text(item.title)
                .font(appFont.font(size: 18, weight: .bold))
                .lineLimit(3)
            Text(item.excerpt)
                .font(appFont.font(size: 12))
                .foregroundStyle(theme.ink(0.5))
                .lineLimit(3)
        }
    }

    // MARK: Shared pieces

    /// Stand-in for the link's site favicon (there is no network fetch — this
    /// is the same colored initial badge used across the demo data).
    private func favicon(size: CGFloat) -> some View {
        Text(item.initial)
            .font(.system(size: size * 0.42, weight: .heavy))
            .foregroundStyle(theme.background)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: item.colorHex)))
    }

    private var hostRow: some View {
        HStack(spacing: 7) {
            Text(item.host)
                .font(appFont.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.ink(0.52))
                .lineLimit(1)
            if !viaString.isEmpty {
                Text(viaString)
                    .font(appFont.font(size: 12))
                    .foregroundStyle(theme.ink(0.34))
            }
        }
    }

    private func thumbnail(size: CGFloat, fullWidth: Bool = false) -> some View {
        let stripes = theme.thumbnailStripes
        return ZStack(alignment: .bottomLeading) {
            StripesShape()
                .fill(stripes.0)
            StripesShape(phase: 8)
                .fill(stripes.1)
                .opacity(0.6)
            Text("aperçu · \(item.host.split(separator: ".").first.map(String.init) ?? item.host)")
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundStyle(theme.ink(0.5))
                .padding(5)
        }
        .frame(width: fullWidth ? nil : size, height: size)
        .frame(maxWidth: fullWidth ? .infinity : size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A cheap diagonal-stripe placeholder standing in for a real link preview
/// image (there is no network fetch — these are demo links).
private struct StripesShape: Shape {
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 10
        let span = rect.width + rect.height
        var offset = -rect.height + phase
        while offset < span {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
            offset += spacing
        }
        return path.strokedPath(StrokeStyle(lineWidth: 5))
    }
}
