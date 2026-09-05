import SwiftUI

/// Renders one `LinkItem` in whichever of the three timeline layouts is
/// currently selected (rail / card / editorial).
struct LinkRowView: View {
    let item: LinkItem
    let layout: LinkLayout
    let theme: AppTheme
    let appFont: AppFont
    let compact: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private var timeString: String { Self.timeFormatter.string(from: item.dateAdded) }
    private var stampString: String { "\(Self.stampFormatter.string(from: item.dateAdded)) · \(timeString)" }
    private var viaString: String { compact ? "" : "via \(item.sourceApp)" }
    private var showThumbnail: Bool { item.hasThumbnail && !compact }

    var body: some View {
        Group {
            switch layout {
            case .rail: railBody
            case .card: cardBody
            case .editorial: editorialBody
            }
        }
        .padding(.vertical, layout == .editorial ? 16 : 16)
        .padding(.horizontal, 18)
        .background(theme.card)
        .foregroundStyle(theme.title)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(item.isRead ? 0.55 : 1)
        .saturation(item.isRead ? 0 : 1)
        .shadow(color: .black.opacity(0.08), radius: 9, y: 4)
    }

    // MARK: Rail (default) — time on the left, title + host, optional thumbnail.

    private var railBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timeString)
                .font(appFont.font(size: 14))
                .foregroundStyle(theme.time)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(appFont.font(size: 18, weight: .bold))
                    .lineLimit(3)
                hostRow
            }

            if showThumbnail {
                thumbnail(size: 64)
            }
        }
    }

    // MARK: Card — host on top, larger title, timestamp, optional thumbnail on the right.

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                hostRow
                Text(item.title)
                    .font(appFont.font(size: 19, weight: .bold))
                    .lineLimit(3)
                Text(stampString)
                    .font(appFont.font(size: 11.5))
                    .foregroundStyle(theme.ink(0.4))
                    .textCase(.uppercase)
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
            HStack {
                hostRow
                Spacer()
                Text(timeString)
                    .font(appFont.font(size: 14))
                    .foregroundStyle(theme.time)
            }
            if showThumbnail {
                thumbnail(size: 150, fullWidth: true)
            }
            Text(item.title)
                .font(appFont.font(size: 18, weight: .bold))
                .lineLimit(3)
            if !compact {
                Text(item.excerpt)
                    .font(appFont.font(size: 12))
                    .foregroundStyle(theme.ink(0.5))
                    .lineLimit(3)
            }
        }
    }

    // MARK: Shared pieces

    private var hostRow: some View {
        HStack(spacing: 7) {
            Text(item.initial)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(theme.background)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color(hex: item.colorHex)))
            Text(item.host)
                .font(appFont.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.ink(0.52))
                .lineLimit(1)
            if !viaString.isEmpty {
                Text(viaString)
                    .font(appFont.font(size: 11))
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
