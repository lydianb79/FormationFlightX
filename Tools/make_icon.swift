// Draws the FormationFlightX app icon and the splash artwork: aircraft in formation climbing out of a sunset,
// smoke on. The splash's title and credits are drawn by the app, over this picture.
// Usage: swift Tools/make_icon.swift <icon.png> <splash.jpg>
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
let navy = col(0.03, 0.06, 0.13), indigo = col(0.07, 0.16, 0.40), azure = col(0.10, 0.50, 0.88), peach = col(1.0, 0.70, 0.42), gold = col(1.0, 0.86, 0.55)
let white = col(0.97, 0.98, 1.0), amber = col(1.0, 0.72, 0.22)

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// A soft round glow.
func glow(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, _ color: CGColor, stretch: CGFloat = 1) {
    let comps = color.components!, clear = col(comps[0], comps[1], comps[2], 0)
    let g = CGGradient(colorsSpace: cs, colors: [color, clear] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: stretch, y: 1)
    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
    ctx.restoreGState()
}

/// The sky at sunset: dark overhead, blue lower down, a warm band at the horizon, the sun low on the right,
/// bars of cloud catching its light, and two ranges of hills in the haze.
func scene(_ ctx: CGContext, _ r: CGRect, sun: CGPoint, clouds: Bool) {
    let g = CGGradient(colorsSpace: cs, colors: [navy, indigo, azure, peach, gold] as CFArray, locations: [0, 0.3, 0.66, 0.9, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY + r.height * 0.1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let u = r.width
    glow(ctx, at: sun, radius: u * 0.5, col(1, 0.72, 0.4, 0.34))
    glow(ctx, at: sun, radius: u * 0.2, col(1, 0.93, 0.74, 0.9))
    glow(ctx, at: sun, radius: u * 0.055, col(1, 1, 0.94, 1))
    if clouds {
        // long thin bars, lit warm underneath
        var seed: UInt64 = 12345
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 40) & 0xFFFF) / 65535 }
        for _ in 0..<26 {
            let c = CGPoint(x: r.minX + rnd() * r.width, y: r.minY + r.height * (0.2 + 0.5 * rnd() * rnd()))
            let rad = u * (0.02 + 0.035 * rnd()), warm = 1 - (c.y - r.minY) / r.height
            glow(ctx, at: c, radius: rad, col(1, 0.8 + 0.2 * (1 - warm), 0.62 + 0.38 * (1 - warm), 0.16 + 0.12 * rnd()), stretch: 5 + 6 * rnd())
        }
    }
    // hills: the far range pale in the haze, the near one dark
    for (base, amp, color) in [(CGFloat(0.17), CGFloat(0.045), col(0.2, 0.26, 0.5, 0.9)), (0.085, 0.05, col(0.04, 0.08, 0.2, 1))] {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        var x = r.minX
        while x <= r.maxX + 4 {
            let t = (x - r.minX) / u
            let y = r.minY + r.height * (base + amp * (sin(t * 7.1 + base * 40) * 0.6 + sin(t * 17.3 + 1.7) * 0.25 + sin(t * 3.2 + 4) * 0.5))
            p.addLine(to: CGPoint(x: x, y: y)); x += 4
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
    }
    glow(ctx, at: CGPoint(x: sun.x, y: r.minY + r.height * 0.15), radius: u * 0.3, col(1, 0.72, 0.45, 0.16), stretch: 2.2)
}

/// An aircraft seen from above, nose toward +y, two units in span, centred on the origin: fuselage, swept wings, tail.
func planeParts() -> [CGPath] {
    func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        for s: CGFloat in [1, -1] { p.move(to: CGPoint(x: s * pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: s * q.0, y: q.1)) }; p.closeSubpath() }
        return p
    }
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 0, y: 1.0))
    body.addCurve(to: CGPoint(x: 0.12, y: 0.3), control1: CGPoint(x: 0.07, y: 0.92), control2: CGPoint(x: 0.13, y: 0.62))
    body.addLine(to: CGPoint(x: 0.085, y: -0.7)); body.addLine(to: CGPoint(x: 0, y: -0.96)); body.addLine(to: CGPoint(x: -0.085, y: -0.7)); body.addLine(to: CGPoint(x: -0.12, y: 0.3))
    body.addCurve(to: CGPoint(x: 0, y: 1.0), control1: CGPoint(x: -0.13, y: 0.62), control2: CGPoint(x: -0.07, y: 0.92))
    body.closeSubpath()
    return [poly([(0.08, 0.34), (1.0, -0.2), (1.0, -0.36), (0.6, -0.3), (0.08, -0.16)]), poly([(0.06, -0.58), (0.44, -0.84), (0.44, -0.95), (0.06, -0.84)]), body]
}

/// One aircraft and the smoke it trails.
func plane(_ ctx: CGContext, at c: CGPoint, size s: CGFloat, heading: CGFloat, lead: Bool, trail: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: heading); ctx.scaleBy(x: s, y: s)
    // smoke: a band that widens and thins behind the tail, laid in three passes so its edges are soft
    for (w, a) in [(CGFloat(1.0), CGFloat(0.22)), (0.62, 0.3), (0.3, 0.45)] {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -0.05 * w, y: -0.9)); p.addLine(to: CGPoint(x: 0.05 * w, y: -0.9))
        p.addLine(to: CGPoint(x: 0.34 * w, y: -0.9 - trail)); p.addLine(to: CGPoint(x: -0.34 * w, y: -0.9 - trail)); p.closeSubpath()
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        let g = CGGradient(colorsSpace: cs, colors: [col(1, 1, 1, a), col(1, 0.97, 0.92, a * 0.55), col(1, 0.95, 0.88, 0)] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: -0.9), end: CGPoint(x: 0, y: -0.9 - trail), options: [])
        ctx.restoreGState()
    }
    let parts = planeParts(), paint = lead ? amber : white
    ctx.setShadow(offset: CGSize(width: 0.05 * s, height: -0.09 * s), blur: 0.16 * s, color: col(0, 0.03, 0.12, 0.5))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for p in parts { ctx.addPath(p); ctx.setFillColor(paint); ctx.fillPath() }
    ctx.endTransparencyLayer()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // the side away from the sun is in shade; a canopy; a stripe on each wing
    ctx.saveGState()
    for p in parts { ctx.addPath(p) }
    ctx.clip()
    ctx.setFillColor(col(0.05, 0.1, 0.3, 0.2)); ctx.fill(CGRect(x: -1.1, y: -1.1, width: 1.1, height: 2.2))
    ctx.setFillColor(lead ? col(0.75, 0.3, 0.05, 0.9) : col(0.1, 0.5, 0.9, 0.95))
    for sgn: CGFloat in [1, -1] {
        let st = CGMutablePath()
        st.move(to: CGPoint(x: sgn * 0.62, y: 0.03)); st.addLine(to: CGPoint(x: sgn * 0.78, y: -0.065)); st.addLine(to: CGPoint(x: sgn * 0.78, y: -0.34)); st.addLine(to: CGPoint(x: sgn * 0.62, y: -0.31)); st.closeSubpath()
        ctx.addPath(st)
    }
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(ellipseIn: CGRect(x: -0.06, y: 0.36, width: 0.12, height: 0.36), transform: nil)); ctx.setFillColor(col(0.04, 0.1, 0.22)); ctx.fillPath()
    ctx.addPath(CGPath(ellipseIn: CGRect(x: -0.03, y: 0.52, width: 0.045, height: 0.15), transform: nil)); ctx.setFillColor(col(0.6, 0.8, 1, 0.7)); ctx.fillPath()
    ctx.restoreGState()
}

/// A vic of `n`, the lead at `c`, flying along `heading` (0 = up the page).
func formation(_ ctx: CGContext, lead c: CGPoint, size s: CGFloat, heading: CGFloat, count n: Int, trail: CGFloat) {
    let fwd = CGPoint(x: -sin(heading), y: cos(heading)), right = CGPoint(x: cos(heading), y: sin(heading))
    for i in stride(from: n - 1, through: 0, by: -1) {
        let row = CGFloat((i + 1) / 2), side: CGFloat = i % 2 == 1 ? 1 : -1
        let p = CGPoint(x: c.x + (right.x * side * row * 2.25 - fwd.x * row * 1.9) * s, y: c.y + (right.y * side * row * 2.25 - fwd.y * row * 1.9) * s)
        plane(ctx, at: p, size: s, heading: heading, lead: i == 0, trail: trail)
    }
}

func save(_ ctx: CGContext, _ path: String, jpeg: Bool) {
    let type = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type, 1, nil)!
    CGImageDestinationAddImage(dst, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.93] as CFDictionary)
    CGImageDestinationFinalize(dst)
}

let args = CommandLine.arguments
guard args.count > 2 else { print("usage: make_icon <icon.png> <splash.jpg>"); exit(1) }

// ---- icon: macOS shape, 824pt rounded square on a 1024 canvas
do {
    let ctx = context(1024, 1024)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: col(0, 0, 0, 0.35))
    ctx.addPath(shape); ctx.setFillColor(navy); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    scene(ctx, tile, sun: CGPoint(x: 330, y: 300), clouds: false)
    formation(ctx, lead: CGPoint(x: 668, y: 690), size: 132, heading: -0.62, count: 3, trail: 3.4)
    // light from above on the tile, and a fine bright rim
    let sheen = CGGradient(colorsSpace: cs, colors: [col(1, 1, 1, 0.16), col(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(col(1, 1, 1, 0.16)); ctx.setLineWidth(4); ctx.strokePath()
    save(ctx, args[1], jpeg: false)
}

// ---- splash artwork (the app draws the title over the left and bottom of it)
do {
    let W = 2560, H = 1600
    let ctx = context(W, H)
    scene(ctx, CGRect(x: 0, y: 0, width: W, height: H), sun: CGPoint(x: 1500, y: 330), clouds: true)
    formation(ctx, lead: CGPoint(x: 1960, y: 1240), size: 118, heading: -0.7, count: 5, trail: 6.5)
    save(ctx, args[2], jpeg: true)
}
