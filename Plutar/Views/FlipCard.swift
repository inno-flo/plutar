import SwiftUI

/// Turns `content` continuously from 0° to 180° around `axis`, as if it
/// were being physically flipped over to its back face. `Animatable`
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
///
/// Used by `LinkRowView` (a link revealing a fetched title/image) and
/// `RootView` (link cards and the counter badge turning to their new theme
/// on a shake — the day/source pills went with a plain color cross-fade
/// instead, see `RootView.fadingDayPill`/`fadingSourceChipLabel`).
struct FlipCard<Content: View>: View, Animatable {
    var angle: Double
    let axis: (x: CGFloat, y: CGFloat, z: CGFloat)
    @ViewBuilder let content: (_ showsNewFace: Bool) -> Content

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showsNewFace = angle > 90
        // A size cue on top of the rotation itself: a slight scale-up
        // peaking at the 90° midpoint (where `sin` of the angle is at its
        // max) and back to 1 at both ends, so the turn reads as an
        // unmistakable physical motion rather than a subtle wobble.
        let scale = 1 + 0.12 * sin(angle * .pi / 180)
        content(showsNewFace)
            // Flattens the content (background fill + clip shape + text,
            // for a capsule) into one layer before the transforms below.
            // Without it, a small, tightly-clipped view like a day/source
            // pill can end up with them applied per-layer instead of to the
            // composited whole — visually, the rotation barely reads at
            // all, unlike a much taller `LinkRowView` card where there's
            // enough room for the same per-layer transform to look like a
            // single rigid rotation anyway.
            .compositingGroup()
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(showsNewFace ? angle - 180 : angle),
                axis: axis,
                perspective: 0.4
            )
    }
}
