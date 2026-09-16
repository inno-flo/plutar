import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// `PlatformImage` (`UIImage`/`NSImage`) itself is defined in
/// `Persistence/PlatformImage.swift`, shared with the share extensions,
/// which don't need this SwiftUI-specific wrapper.
extension Image {
    /// `Image(uiImage:)` on iOS, `Image(nsImage:)` on macOS — lets
    /// `LinkRowView` stay a single shared file across both platforms.
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Renders one `LinkItem` in whichever of the three timeline layouts is
/// currently selected (rail / card / editorial).
struct LinkRowView: View {
    let item: LinkItem
    let layout: LinkLayout
    let theme: AppTheme
    let appFont: AppFont
    /// Whether the host/"via" line renders at all — `true` everywhere except
    /// a macOS single-source detail (`MacFeedList`'s `isSingleSourceDetail`),
    /// where every row is already known to belong to the one source named in
    /// the toolbar title, so repeating it on every card is redundant. iOS
    /// never sets this (always the default `true`).
    var showHost: Bool = true
    /// macOS only: whether this row is the `List`'s current selection.
    /// Native `List` selection on macOS draws its highlight as a plain
    /// rectangle behind the row, which — since the card itself is inset
    /// from the row's edges — showed up as a ring *around* the card rather
    /// than filling it. Instead, `MacFeedList` hides that native highlight
    /// and this fills the card itself with `theme.chip` (text switching to
    /// `selectedTextColor` below) when selected instead — the same
    /// background already used for iOS's link-count counter badge.
    /// iOS never sets this (always `false`).
    var isSelected: Bool = false
    /// macOS only (all of À lire/Lus/Sources): drops the card's white
    /// background, rounded shape and shadow, leaving just the title, host
    /// and thumbnail sitting directly on the list background. Selection
    /// still fills with `theme.chip` like the normal card does — otherwise
    /// there'd be no way to see which row is selected. iOS never sets this
    /// (always `false`).
    var plainStyle: Bool = false

    /// `theme.chipText` for the selected-link text below, except Copenhague
    /// nuit and Kamakura nuit: `chipText` falls through to each's own (dark)
    /// `background` there — fine for the counter badge's own tuned overrides
    /// elsewhere, but reading dark-on-chip here, unlike every other "nuit"
    /// theme's white. Keeping the same light text as Cap Canaveral nuit/
    /// Tokyo nuit instead.
    private var selectedTextColor: Color {
        switch theme {
        case .scandSoir, .blancSoir: return .white
        default: return theme.chipText
        }
    }

    /// Any "nuit" theme, in Lus (every cell here is `isRead`): title and
    /// host both use the theme's own (already light) ink rather than
    /// anything darker — Cap Canaveral nuit already reads this way by
    /// accident (its ink is plain white in both variants), this just makes
    /// every other nuit theme's Lus text behave the same, legibly, instead
    /// of the light-variant tone `readTitleColor` used to borrow, which was
    /// dark and unreadable against a nuit theme's own dark background.
    private var isSoirRead: Bool { item.isRead && theme.isSoir }

    /// Tokyo clair, in Lus: thumbnails get an extra grayed-out veil on top
    /// of the row's own saturation/tint treatment, which on this theme's
    /// bright background isn't muted enough on its own to read as "read".
    private var isTokyoLightRead: Bool { item.isRead && theme == .tokyo }

    /// Read-link title color: unchanged in a light theme; a "nuit" theme
    /// uses its own (already off-white) ink at full strength instead of
    /// the usual dimmed opacity, so it stays legible against the theme's
    /// own dark background.
    private var readTitleColor: Color {
        theme.isSoir ? theme.ink(1) : theme.ink(0.52)
    }

    /// Rounded is a real system weight variant and renders this bold fine;
    /// SF Compact ignores it entirely (fixed to its own Regular style
    /// regardless of what's passed), so titles stay at Regular weight there.
    private var titleWeight: Font.Weight { .bold }

    /// Smaller on macOS — the mockup's 18pt reads oversized next to the
    /// window chrome/sidebar there; iOS keeps its original size.
    private var titleFontSize: CGFloat {
        #if os(macOS)
        16
        #else
        18
        #endif
    }

    /// 0→180°, animated in one continuous motion (see `FlipCard`) when
    /// `LinkMetadataEnricher` turns a bare-URL link into a real title.
    @State private var flipAngle: Double = 0
    /// The pre-enrichment title/thumbnail, kept around only for the
    /// duration of the flip — `FlipCard` shows this face for the first half
    /// of the turn and the live (enriched) one for the second half.
    @State private var frozenTitle: String?
    @State private var frozenThumbnailFileName: String??

    var body: some View {
        // `FlipCard` is plain SwiftUI (no UIKit dependency, despite the
        // stale comment that used to sit here) — both platforms get the
        // same flip when `LinkMetadataEnricher` turns a bare-URL title into
        // a real one.
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
        .onChange(of: item.thumbnailFileName) { oldFileName, newFileName in
            // Same flip, for the case `LinkMetadataEnricher`'s
            // `redownloadMissingThumbnails` exists for: a link enriched on
            // the *other* platform (iOS/macOS) syncs in with its title
            // already real but no image — the JPEG itself never syncs via
            // CloudKit, only this filename — and this device fetches its
            // own copy afterwards. Only the "acquired an image" transition
            // flips, same reasoning as the title's own case above.
            guard oldFileName != newFileName, oldFileName == nil, newFileName != nil else { return }
            frozenTitle = item.title
            frozenThumbnailFileName = oldFileName
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
        // `plainStyle` rows have no card padding out an inter-row gap of
        // their own anymore — halved here so consecutive links sit closer
        // together than the old card spacing.
        .padding(.vertical, plainStyle ? 8 : 16)
        .padding(.horizontal, 18)
        .background(plainStyle && !isSelected ? Color.clear : (isSelected ? theme.chip : (item.isRead ? (theme.readCardOverride ?? theme.card) : theme.card)))
        // In Lus (every cell here is read), the title drops down to the
        // same muted tone as the host/"via" line below it instead of the
        // theme's full-strength title color.
        .foregroundStyle(isSelected ? selectedTextColor : (item.isRead ? readTitleColor : theme.title))
        // A read cell (i.e. every cell in Lus) is tinted toward the page's
        // own background instead of just made transparent — plain opacity
        // makes the cell blend with whatever scrolls behind it, which reads
        // inconsistently from theme to theme; blending toward a color the
        // theme already defines gives a real, consistently muted tone.
        // Skipped when the theme provides its own flat `readCardOverride`
        // (Cap Canaveral uses a plain medium gray instead), when selected —
        // the accent fill above should read clean, not muted — and in
        // `plainStyle`, which has no fill to tint in the first place.
        .overlay {
            if item.isRead && theme.readCardOverride == nil && !isSelected && !plainStyle {
                theme.background.opacity(0.6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Skipped when the theme provides its own flat `readCardOverride`,
        // or when selected — otherwise this desaturates that color too,
        // washing e.g. Cap Canaveral's light blue (or the selection accent)
        // down to a gray indistinguishable from before. Also skipped for
        // every "nuit" theme — their thumbnails stay in color there, with
        // the black veil in `thumbnail(...)` doing the muting instead.
        .saturation(item.isRead && theme.readCardOverride == nil && !isSelected && !theme.isSoir ? 0 : 1)
        // No shadow on read cells (all of Lus), and none at all in
        // `plainStyle` — there's no card underneath for a shadow to sit on.
        .shadow(color: (item.isRead || plainStyle) ? .clear : .black.opacity(0.08), radius: 9, y: 4)
    }

    // MARK: Rail (default) — just the title, host below, nothing else.

    private func railBody(title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(appFont.font(size: titleFontSize, weight: titleWeight))
                .lineLimit(3)
            if showHost {
                hostRow
            }
        }
    }

    // MARK: Card — title, host below, thumbnail on the right.

    private func cardBody(title: String, thumbnailFileName: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(appFont.font(size: titleFontSize, weight: titleWeight))
                    .lineLimit(3)
                if showHost {
                    hostRow
                }
            }
            Spacer(minLength: 0)
            // Always shown in Détaillée — like Éditoriale below, this
            // layout's premise includes a thumbnail; it's Simple's premise
            // to have none.
            thumbnail(size: 86, thumbnailFileName: thumbnailFileName)
        }
    }

    // MARK: Editorial — big thumbnail on top, title, excerpt, source at the
    // bottom (still leading-aligned, like every other line in this stack).

    /// 150 everywhere except iPad, where it's 225 (+50%) — Éditoriale's
    /// full-width thumbnail otherwise reads as squat on the extra width an
    /// iPad screen gives it.
    private var editorialThumbnailHeight: CGFloat {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? 225 : 150
        #else
        return 150
        #endif
    }

    private func editorialBody(title: String, thumbnailFileName: String?) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            // Always shown — see the comment in cardBody: Détaillée and
            // Éditoriale both always carry a thumbnail (placeholder or
            // real), Simple never does.
            thumbnail(size: editorialThumbnailHeight, fullWidth: true, thumbnailFileName: thumbnailFileName)
            Text(title)
                .font(appFont.font(size: titleFontSize, weight: .bold))
                .lineLimit(3)
            // Only when there's actually an excerpt to show — an empty
            // `Text` still claims a row plus the `VStack`'s own spacing on
            // both sides, leaving a visible gap above the source line for
            // links `LinkMetadataEnricher` hasn't found a description for.
            if !item.excerpt.isEmpty {
                Text(item.excerpt)
                    .font(appFont.font(size: 13))
                    .foregroundStyle(isSelected ? selectedTextColor.opacity(0.85) : theme.ink(0.5))
                    .lineLimit(3)
            }
            if showHost {
                hostRow
            }
        }
    }

    // MARK: Shared pieces

    private var hostRow: some View {
        Text(item.host)
            .font(appFont.font(size: 13, weight: .regular))
            .foregroundStyle(isSelected ? selectedTextColor : (isSoirRead ? theme.ink(0.5) : theme.ink(0.52)))
            .lineLimit(1)
    }

    @ViewBuilder
    private func thumbnail(size: CGFloat, fullWidth: Bool = false, thumbnailFileName: String?) -> some View {
        if let fileName = thumbnailFileName, let image = Self.cachedThumbnail(fileName) {
            Image(platformImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: fullWidth ? nil : size, height: size)
                .frame(maxWidth: fullWidth ? .infinity : size)
                .overlay {
                    if isTokyoLightRead || isSoirRead {
                        Color.black.opacity(0.35)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        // No real image: render nothing, reserving no space either.
    }

    /// Small in-memory cache so scrolling doesn't re-read the same JPEG off
    /// disk on every layout pass — thumbnails are a handful of KB each, but
    /// cells redraw often (theme changes, read-state toggles, swipe).
    private static let thumbnailCache = NSCache<NSString, PlatformImage>()

    private static func cachedThumbnail(_ fileName: String) -> PlatformImage? {
        let key = fileName as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let directory = SharedStore.thumbnailsDirectoryURL(),
              let image = PlatformImage(contentsOfFile: directory.appendingPathComponent(fileName).path)
        else {
            return nil
        }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }
}
