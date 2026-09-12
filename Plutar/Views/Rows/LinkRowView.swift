import SwiftUI
import UIKit

/// Renders one `LinkItem` in whichever of the three timeline layouts is
/// currently selected (rail / card / editorial).
struct LinkRowView: View {
    let item: LinkItem
    let layout: LinkLayout
    let theme: AppTheme
    let appFont: AppFont
    let showThumbnails: Bool
    let showFavicons: Bool
    /// Whether a link with no real image (not fetched yet, or the fetch
    /// found none) falls back to the striped placeholder, or shows nothing
    /// at all. All three tabs (Date, Sources, Lus) now pass `false` — a wall
    /// of placeholders for links still waiting on `LinkMetadataEnricher`
    /// read as more "broken" than useful. Kept as a parameter rather than
    /// deleted outright, in case a future layout wants the placeholder back.
    let showsPlaceholderThumbnail: Bool

    /// Tokyo soir, in Lus (every cell here is `isRead`): every link text
    /// matches the view's own counter gray instead of each text's usual
    /// per-element tone.
    private var isTokyoSoirRead: Bool { item.isRead && theme == .tokyoSoir }

    /// Rounded is a real system weight variant and renders this bold fine;
    /// SF Compact ignores it entirely (fixed to its own Regular style
    /// regardless of what's passed), so titles stay at Regular weight there.
    private var titleWeight: Font.Weight { .bold }

    /// 0→180°, animated in one continuous motion (see `FlipCard`) when
    /// `LinkMetadataEnricher` turns a bare-URL link into a real title.
    @State private var flipAngle: Double = 0
    /// The pre-enrichment title/thumbnail, kept around only for the
    /// duration of the flip — `FlipCard` shows this face for the first half
    /// of the turn and the live (enriched) one for the second half.
    @State private var frozenTitle: String?
    @State private var frozenThumbnailFileName: String??

    var body: some View {
        FlipCard(angle: flipAngle, axis: (x: 1, y: 0, z: 0)) { showsNewFace in
            cardFace(
                title: showsNewFace ? item.title : (frozenTitle ?? item.title),
                thumbnailFileName: showsNewFace ? item.thumbnailFileName : (frozenThumbnailFileName ?? item.thumbnailFileName)
            )
        }
        .onChange(of: item.title) { oldTitle, newTitle in
            // Only the "acquired a real title" transition flips — a link
            // whose title was already real doesn't flip again over some
            // unrelated later edit (there isn't one today, but this keeps
            // the trigger meaningful rather than "title changed at all").
            guard oldTitle != newTitle, oldTitle == item.host || oldTitle == item.urlString else { return }
            frozenTitle = oldTitle
            frozenThumbnailFileName = item.thumbnailFileName
            flipAngle = 0
            withAnimation(.easeInOut(duration: 0.5)) {
                flipAngle = 180
            }
        }
    }

    /// The whole visible card — background, shape, shadow and all — for
    /// one specific title/thumbnail pairing. Takes them as parameters
    /// rather than reading `item` directly so `FlipCard` can render the
    /// pre- and post-enrichment faces side by side while it turns.
    private func cardFace(title: String, thumbnailFileName: String?) -> some View {
        Group {
            switch layout {
            case .rail: railBody(title: title)
            case .card: cardBody(title: title, thumbnailFileName: thumbnailFileName)
            case .editorial: editorialBody(title: title, thumbnailFileName: thumbnailFileName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, layout == .editorial ? 16 : 16)
        .padding(.horizontal, 18)
        .background(item.isRead ? (theme.readCardOverride ?? theme.card) : theme.card)
        // In Lus (every cell here is read), the title drops down to the
        // same muted tone as the host/"via" line below it instead of the
        // theme's full-strength title color.
        .foregroundStyle(isTokyoSoirRead ? theme.ink(0.5) : (item.isRead ? theme.ink(0.52) : theme.title))
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

    private func railBody(title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(appFont.font(size: 18, weight: titleWeight))
                .lineLimit(3)
            hostRow
        }
    }

    // MARK: Card — favicon + title, host below, thumbnail on the right.

    private func cardBody(title: String, thumbnailFileName: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if showFavicons {
                favicon(size: 18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(appFont.font(size: 18, weight: titleWeight))
                    .lineLimit(3)
                hostRow
            }
            Spacer(minLength: 0)
            // Always shown in Détaillée — like Éditoriale below, this
            // layout's premise includes a thumbnail; it's Simple's premise
            // to have none.
            thumbnail(size: 86, thumbnailFileName: thumbnailFileName)
        }
    }

    // MARK: Editorial — big thumbnail on top, title, excerpt below.

    private func editorialBody(title: String, thumbnailFileName: String?) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                if showFavicons {
                    favicon(size: 22)
                }
                hostRow
            }
            // Always shown — see the comment in cardBody: Détaillée and
            // Éditoriale both always carry a thumbnail (placeholder or
            // real), Simple never does.
            thumbnail(size: 150, fullWidth: true, thumbnailFileName: thumbnailFileName)
            Text(title)
                .font(appFont.font(size: 18, weight: .bold))
                .lineLimit(3)
            Text(item.excerpt)
                .font(appFont.font(size: 13))
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
        Text(item.host)
            .font(appFont.font(size: 13, weight: .semibold))
            .foregroundStyle(isTokyoSoirRead ? theme.ink(0.5) : theme.ink(0.52))
            .lineLimit(1)
    }

    @ViewBuilder
    private func thumbnail(size: CGFloat, fullWidth: Bool = false, thumbnailFileName: String?) -> some View {
        if let fileName = thumbnailFileName, let image = Self.cachedThumbnail(fileName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: fullWidth ? nil : size, height: size)
                .frame(maxWidth: fullWidth ? .infinity : size)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if showsPlaceholderThumbnail {
            placeholderThumbnail
                .frame(width: fullWidth ? nil : size, height: size)
                .frame(maxWidth: fullWidth ? .infinity : size)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        // Neither: no real image, and this row doesn't fall back to the
        // placeholder — render nothing, reserving no space either.
    }

    /// Placeholder for demo links (no real image ever fetched for those)
    /// and for real ones still waiting on `LinkMetadataEnricher`.
    private var placeholderThumbnail: some View {
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
                .hidden()
        }
    }

    /// Small in-memory cache so scrolling doesn't re-read the same JPEG off
    /// disk on every layout pass — thumbnails are a handful of KB each, but
    /// cells redraw often (theme changes, read-state toggles, swipe).
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    private static func cachedThumbnail(_ fileName: String) -> UIImage? {
        let key = fileName as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let directory = SharedStore.thumbnailsDirectoryURL(),
              let image = UIImage(contentsOfFile: directory.appendingPathComponent(fileName).path)
        else {
            return nil
        }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }
}

/// Turns `content` continuously from 0° to 180° around `axis`, as if the
/// card were being physically flipped over to its back face. `Animatable`
/// makes SwiftUI call `body` for every interpolated frame of the
/// animation (not just its start/end), which is what lets a single
/// `withAnimation` drive both the rotation and, exactly at the 90°
/// midpoint (where the card is edge-on and briefly invisible), the swap
/// from `content(false)` to `content(true)` — one continuous curve, no
/// separate staged animations that could visibly stutter at the handoff.
///
/// Past 90°, `angle - 180` keeps the second face's own rotation within
/// ±90° of upright, so it's never drawn mirrored the way a plain 0→180°
/// `rotation3DEffect` would show it partway through.
private struct FlipCard<Content: View>: View, Animatable {
    var angle: Double
    let axis: (x: CGFloat, y: CGFloat, z: CGFloat)
    @ViewBuilder let content: (_ showsNewFace: Bool) -> Content

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showsNewFace = angle > 90
        content(showsNewFace)
            .rotation3DEffect(
                .degrees(showsNewFace ? angle - 180 : angle),
                axis: axis,
                perspective: 0.4
            )
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
