// Renders the three 1024×1024 app-icon variants.
//   swift MakeIcon.swift ../../Plutar/Assets.xcassets/AppIcon.appiconset
// LAYERS=. also re-exports moon.png for Icon Composer.

import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// ---------------------------------------------------------------- geometry
let S: CGFloat = 1024
// Everything is authored on a 1024 grid then scaled about the optical centre so
// the artwork sits comfortably inside the squircle mask.
let K: CGFloat = 1.06
let O = CGPoint(x: 512, y: 506)
func sx(_ x: CGFloat) -> CGFloat { O.x + (x - O.x) * K }
func sy(_ y: CGFloat) -> CGFloat { O.y + (y - O.y) * K }
func sr(_ r: CGRect) -> CGRect { CGRect(x: sx(r.minX), y: sy(r.minY), width: r.width * K, height: r.height * K) }

let moonC = CGPoint(x: sx(640), y: sy(384))
let moonR: CGFloat = 228 * K
let moonBox = CGRect(x: moonC.x - moonR, y: moonC.y - moonR, width: moonR * 2, height: moonR * 2)
let page = sr(CGRect(x: 156, y: 356, width: 400, height: 500))
let pageR: CGFloat = 48 * K

struct Line { let r: CGRect; let radius: CGFloat; let accent: Bool }
let lines: [Line] = [
    Line(r: sr(CGRect(x: 216, y: 483, width: 176, height: 30)), radius: 15 * K, accent: true),
    Line(r: sr(CGRect(x: 216, y: 575, width: 280, height: 22)), radius: 11 * K, accent: false),
    Line(r: sr(CGRect(x: 216, y: 641, width: 280, height: 22)), radius: 11 * K, accent: false),
    Line(r: sr(CGRect(x: 216, y: 707, width: 190, height: 22)), radius: 11 * K, accent: false),
]

// ---------------------------------------------------------------- helpers
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func c(_ hex: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        CGFloat(a),
    ])!
}

func newContext() -> CGContext {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: S)          // work in y-down coordinates
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// Draw a CGImage upright inside our y-down context.
func draw(_ img: CGImage, in ctx: CGContext, rect: CGRect = CGRect(x: 0, y: 0, width: S, height: S)) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: rect.minX, y: S - rect.maxY, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat],
            center: CGPoint, r0: CGFloat, r1: CGFloat) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: r0,
                           endCenter: center, endRadius: r1, options: [.drawsAfterEndLocation])
}

func blur(_ img: CGImage, radius: Double) -> CGImage {
    let ci = CIImage(cgImage: img)
    let f = CIFilter(name: "CIGaussianBlur")!
    f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
    f.setValue(radius, forKey: kCIInputRadiusKey)
    let out = f.outputImage!.cropped(to: ci.extent)
    return CIContext(options: [.workingColorSpace: sRGB]).createCGImage(out, from: ci.extent)!
}

func writePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}


// ---------------------------------------------------------------- crescent
// A true two-circle crescent: the moon's own sphere, minus a second circle
// offset towards the opening. The cusps are where the two circles cross, so
// they come to a point and sit exactly on the sphere — no rounded caps, and
// nothing sticking out past the limb.
//
// Thickness and wrap are set so the crescent covers ~40% of the disc, which is
// what SF Symbols' own `moon.fill` covers — same visual mass, cleaner tips.
//
// Angle is measured clockwise from +x in screen space, so -45 opens the
// crescent towards the upper right, the way SF Symbols' `moon.fill` does.
var moonOpenAngle: CGFloat = -45   // direction the crescent opens towards
var moonThickness: CGFloat = 0.63  // widest span of the crescent, as a fraction of R
var moonWrap: CGFloat = 70         // cusp half-angle from the opening axis

/// Centre and radius of the circle to subtract from the sphere.
func moonCutter() -> (CGPoint, CGFloat) {
    let R = moonR
    let t = moonThickness
    let psi = moonWrap * .pi / 180
    // Solving thickness = R + d - r together with the cusps landing at ±psi.
    let d = R * (1 - (1 - t) * (1 - t)) / (2 * ((1 - t) + cos(psi)))
    let r = d + R * (1 - t)
    let a = moonOpenAngle * .pi / 180
    return (CGPoint(x: moonC.x + d * cos(a), y: moonC.y + d * sin(a)), r)
}

/// Clip to the crescent: inside the sphere, and outside the cutter. The second
/// half is an even-odd rect-minus-circle, since Core Graphics cannot clip to
/// the complement of a path directly.
func clipToMoon(_ ctx: CGContext) {
    ctx.addEllipse(in: moonBox)
    ctx.clip()

    let (cc, cr) = moonCutter()
    let outside = CGMutablePath()
    outside.addRect(CGRect(x: 0, y: 0, width: S, height: S))
    outside.addEllipse(in: CGRect(x: cc.x - cr, y: cc.y - cr, width: cr * 2, height: cr * 2))
    ctx.addPath(outside)
    ctx.clip(using: .evenOdd)
}

// ---------------------------------------------------------------- variants
struct Variant {
    var name: String
    var bgTop: UInt32 = 0, bgBottom: UInt32 = 0
    var opaqueBackground = true
    var glow: UInt32 = 0xFF4F00, glowAlpha: Double = 0.3
    var moonInner: UInt32, moonMid: UInt32, moonOuter: UInt32
    var moonHighlight: Double            // white specular inside the moon
    var moonDarkInner: UInt32, moonDarkOuter: UInt32   // the unlit sphere behind
    var moonShadow: UInt32, moonShadowAlpha: Double   // terminator, makes the disc read as a sphere
    var pageTint: UInt32, pageAlpha: Double
    var pageStroke: UInt32, pageStrokeAlpha: Double
    var specular: Double                 // top-edge sheen on the page
    var titleColor: UInt32, titleAlpha: Double
    var bodyColor: UInt32, bodyAlpha: Double
    var shadowAlpha: Double
    var frost: Bool = true               // sample & blur the backdrop through the page
}

let light = Variant(
    name: "light",
    bgTop: 0x8FB4E0, bgBottom: 0xE9D6BC,
    glow: 0xFFE6BC, glowAlpha: 0.26,
    moonInner: 0xFFFDF6, moonMid: 0xFFEDCA, moonOuter: 0xE7BC7C, moonHighlight: 0.34,
    moonDarkInner: 0xBCC6D4, moonDarkOuter: 0x9CA8BA,
    moonShadow: 0x6E5330, moonShadowAlpha: 0.36,
    pageTint: 0xFFFFFF, pageAlpha: 0.88,
    pageStroke: 0xFFFFFF, pageStrokeAlpha: 0.95,
    specular: 0.45,
    titleColor: 0xFF4F00, titleAlpha: 1.0,
    bodyColor: 0x4A5B72, bodyAlpha: 0.42,
    shadowAlpha: 0.26)

let dark = Variant(
    name: "dark",
    bgTop: 0x1B3054, bgBottom: 0x050A14,
    glow: 0xFFCE86, glowAlpha: 0.30,
    moonInner: 0xFFFDF7, moonMid: 0xFFEFD2, moonOuter: 0xE8C286, moonHighlight: 0.30,
    moonDarkInner: 0x36435A, moonDarkOuter: 0x202B3D,
    moonShadow: 0x241A0E, moonShadowAlpha: 0.42,
    pageTint: 0xFFFFFF, pageAlpha: 0.17,
    pageStroke: 0xFFFFFF, pageStrokeAlpha: 0.38,
    specular: 0.30,
    titleColor: 0xFF6A1A, titleAlpha: 1.0,
    bodyColor: 0xFFFFFF, bodyAlpha: 0.66,
    shadowAlpha: 0.50)

let tinted = Variant(
    name: "tinted",
    opaqueBackground: false,
    glow: 0xFFFFFF, glowAlpha: 0.10,
    moonInner: 0xFFFFFF, moonMid: 0xF0F0F0, moonOuter: 0xB4B4B4, moonHighlight: 0.20,
    moonDarkInner: 0x9A9A9A, moonDarkOuter: 0x6E6E6E,
    moonShadow: 0x000000, moonShadowAlpha: 0.20,
    pageTint: 0xE8E8E8, pageAlpha: 0.55,
    pageStroke: 0xFFFFFF, pageStrokeAlpha: 0.55,
    specular: 0.20,
    titleColor: 0xFFFFFF, titleAlpha: 1.0,
    bodyColor: 0xFFFFFF, bodyAlpha: 0.55,
    shadowAlpha: 0.0,
    frost: false)

// ---------------------------------------------------------------- drawing
func pagePath() -> CGPath {
    CGPath(roundedRect: page, cornerWidth: pageR, cornerHeight: pageR, transform: nil)
}

/// Background gradient + halo + moon — everything that sits *behind* the page.
func renderBase(_ v: Variant) -> CGImage {
    let ctx = newContext()

    if v.opaqueBackground {
        ctx.saveGState()
        ctx.addRect(CGRect(x: 0, y: 0, width: S, height: S))
        ctx.clip()
        linear(ctx, [c(v.bgTop), c(v.bgBottom)], [0, 1],
               from: CGPoint(x: 180, y: 0), to: CGPoint(x: 860, y: S))
        ctx.restoreGState()
    }

    // Halo around the moon.
    radial(ctx, [c(v.glow, v.glowAlpha), c(v.glow, v.glowAlpha * 0.45), c(v.glow, 0)],
           [0, 0.45, 1], center: moonC, r0: moonR * 0.85, r1: moonR * 2.1)

    // The moon is two spheres of the same diameter, exactly superimposed: an
    // unlit one, and the lit crescent in front of it. What the crescent leaves
    // open shows the darker sphere, not the sky.
    ctx.saveGState()
    ctx.addEllipse(in: moonBox)
    ctx.clip()
    radial(ctx, [c(v.moonDarkInner), c(v.moonDarkOuter)], [0, 1],
           center: CGPoint(x: moonC.x - moonR * 0.32, y: moonC.y - moonR * 0.36),
           r0: 0, r1: moonR * 1.7)
    ctx.restoreGState()

    // Lit crescent.
    ctx.saveGState()
    clipToMoon(ctx)
    radial(ctx, [c(v.moonInner), c(v.moonMid), c(v.moonOuter)], [0, 0.55, 1],
           center: CGPoint(x: moonC.x - moonR * 0.32, y: moonC.y - moonR * 0.36),
           r0: 0, r1: moonR * 1.7)
    // Light falls away towards the lower right, giving the limb some volume.
    linear(ctx, [c(v.moonShadow, 0), c(v.moonShadow, v.moonShadowAlpha * 0.35), c(v.moonShadow, v.moonShadowAlpha)],
           [0, 0.6, 1],
           from: CGPoint(x: moonC.x - moonR * 0.55, y: moonC.y - moonR * 0.55),
           to: CGPoint(x: moonC.x + moonR * 0.95, y: moonC.y + moonR * 0.95))
    radial(ctx, [c(0xFFFFFF, v.moonHighlight), c(0xFFFFFF, 0)], [0, 1],
           center: CGPoint(x: moonC.x - moonR * 0.40, y: moonC.y - moonR * 0.44),
           r0: 0, r1: moonR * 0.9)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func renderIcon(_ v: Variant) -> CGImage {
    let base = renderBase(v)
    let ctx = newContext()
    draw(base, in: ctx)

    let path = pagePath()

    // Drop shadow cast by the page.
    if v.shadowAlpha > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: c(0x000000, v.shadowAlpha))
        ctx.addPath(path)
        ctx.setFillColor(c(0x000000, 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Frosted glass: the blurred backdrop read through the page.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if v.frost {
        draw(blur(base, radius: 34), in: ctx)
    }
    ctx.setFillColor(c(v.pageTint, v.pageAlpha))
    ctx.fill(page)

    // Specular sheen across the top of the sheet.
    linear(ctx, [c(0xFFFFFF, v.specular), c(0xFFFFFF, 0)], [0, 1],
           from: CGPoint(x: page.minX, y: page.minY),
           to: CGPoint(x: page.minX + page.width * 0.55, y: page.minY + page.height * 0.5))
    ctx.restoreGState()

    // Rim light.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(c(v.pageStroke, v.pageStrokeAlpha))
    ctx.strokePath()
    ctx.restoreGState()

    // Written lines.
    for l in lines {
        ctx.addPath(CGPath(roundedRect: l.r, cornerWidth: l.radius, cornerHeight: l.radius, transform: nil))
        ctx.setFillColor(l.accent ? c(v.titleColor, v.titleAlpha) : c(v.bodyColor, v.bodyAlpha))
        ctx.fillPath()
    }

    return ctx.makeImage()!
}

// ---------------------------------------------------------------- output
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let env = ProcessInfo.processInfo.environment
if let v = env["OPEN"],  let d = Double(v) { moonOpenAngle = CGFloat(d) }
if let v = env["THICK"], let d = Double(v) { moonThickness = CGFloat(d) }
if let v = env["WRAP"],  let d = Double(v) { moonWrap = CGFloat(d) }
for v in [light, dark, tinted] {
    writePNG(renderIcon(v), "\(outDir)/AppIcon-\(v.name)-1024.png")
    print("wrote AppIcon-\(v.name)-1024.png")
}

// LAYERS=<dir> also exports the flat foreground layers for Icon Composer.
if let layerDir = env["LAYERS"] {
    let (cc, cr) = moonCutter()
    func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <defs>
        <radialGradient id="lit" gradientUnits="userSpaceOnUse"
                        cx="\(f(moonC.x - moonR * 0.32))" cy="\(f(moonC.y - moonR * 0.36))" r="\(f(moonR * 1.7))">
          <stop offset="0" stop-color="#FFFDF6"/>
          <stop offset="0.55" stop-color="#FFEDCA"/>
          <stop offset="1" stop-color="#E7BC7C"/>
        </radialGradient>
        <radialGradient id="unlit" gradientUnits="userSpaceOnUse"
                        cx="\(f(moonC.x - moonR * 0.32))" cy="\(f(moonC.y - moonR * 0.36))" r="\(f(moonR * 1.7))">
          <stop offset="0" stop-color="#BCC6D4"/>
          <stop offset="1" stop-color="#9CA8BA"/>
        </radialGradient>
        <mask id="crescent">
          <circle cx="\(f(moonC.x))" cy="\(f(moonC.y))" r="\(f(moonR))" fill="#FFFFFF"/>
          <circle cx="\(f(cc.x))" cy="\(f(cc.y))" r="\(f(cr))" fill="#000000"/>
        </mask>
      </defs>
      <!-- Two spheres of the same diameter, exactly superimposed: the unlit one,
           then the lit crescent in front of it. -->
      <circle cx="\(f(moonC.x))" cy="\(f(moonC.y))" r="\(f(moonR))" fill="url(#unlit)"/>
      <circle cx="\(f(moonC.x))" cy="\(f(moonC.y))" r="\(f(moonR))" fill="url(#lit)" mask="url(#crescent)"/>
    </svg>
    """
    try! svg.write(toFile: "\(layerDir)/moon.svg", atomically: true, encoding: .utf8)
    print("wrote moon.svg")
}
