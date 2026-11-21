// Draws the FormationFlightX app icon and splash artwork: flying wings in formation in an evening sky.
// Usage: swift Tools/make_icon.swift <icon.png> <splash.jpg>
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
let navy = col(0.035, 0.07, 0.125), deep = col(0.04, 0.2, 0.42), azure = col(0.10, 0.60, 0.92), glow = col(1.0, 0.78, 0.45)
let white = col(0.96, 0.975, 1.0), amber = col(1.0, 0.72, 0.22)

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Evening sky: dark overhead, bright blue lower down, a warm band at the horizon.
func sky(_ ctx: CGContext, _ r: CGRect) {
    let g = CGGradient(colorsSpace: cs, colors: [navy, deep, azure, glow] as CFArray, locations: [0, 0.38, 0.8, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX + r.width * 0.12, y: r.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// A swept flying wing seen from above, nose toward +y, 2 units in span, centred on the origin.
func wingPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0.50))
    p.addQuadCurve(to: CGPoint(x: 0.97, y: -0.30), control: CGPoint(x: 0.42, y: 0.22))
    p.addLine(to: CGPoint(x: 1.0, y: -0.52)); p.addLine(to: CGPoint(x: 0.82, y: -0.50))
    p.addQuadCurve(to: CGPoint(x: 0, y: -0.20), control: CGPoint(x: 0.34, y: -0.22))
    p.addQuadCurve(to: CGPoint(x: -0.82, y: -0.50), control: CGPoint(x: -0.34, y: -0.22))
    p.addLine(to: CGPoint(x: -1.0, y: -0.52)); p.addLine(to: CGPoint(x: -0.97, y: -0.30))
    p.addQuadCurve(to: CGPoint(x: 0, y: 0.50), control: CGPoint(x: -0.42, y: 0.22))
    p.closeSubpath()
    return p
}

/// One wing with the two vapour trails it leaves from its tips.
func wing(_ ctx: CGContext, at c: CGPoint, size s: CGFloat, heading: CGFloat, lead: Bool, trail: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: heading); ctx.scaleBy(x: s, y: s)
    for x in [CGFloat(-0.9), 0.9] {
        let g = CGGradient(colorsSpace: cs, colors: [col(1, 1, 1, 0.55), col(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.addRect(CGRect(x: x - 0.035, y: -0.45 - trail, width: 0.07, height: trail)); ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: x, y: -0.45), end: CGPoint(x: x, y: -0.45 - trail), options: [])
        ctx.restoreGState()
    }
    ctx.setShadow(offset: CGSize(width: 0, height: -0.05 * s), blur: 0.12 * s, color: col(0, 0.05, 0.15, 0.45))
    ctx.addPath(wingPath()); ctx.setFillColor(lead ? amber : white); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(CGPath(ellipseIn: CGRect(x: -0.075, y: -0.16, width: 0.15, height: 0.5), transform: nil)); ctx.setFillColor(navy); ctx.fillPath()
    ctx.restoreGState()
}

/// A vic of `n` wings, the lead at `c`, flying along `heading` (0 = up the page).
func formation(_ ctx: CGContext, lead c: CGPoint, size s: CGFloat, heading: CGFloat, count n: Int, trail: CGFloat) {
    let fwd = CGPoint(x: -sin(heading), y: cos(heading)), right = CGPoint(x: cos(heading), y: sin(heading))
    for i in stride(from: n - 1, through: 0, by: -1) {
        let row = CGFloat((i + 1) / 2), side: CGFloat = i % 2 == 1 ? 1 : -1
        let p = CGPoint(x: c.x + (right.x * side * row * 2.35 - fwd.x * row * 1.75) * s, y: c.y + (right.y * side * row * 2.35 - fwd.y * row * 1.75) * s)
        wing(ctx, at: p, size: s, heading: heading, lead: i == 0, trail: trail)
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
    sky(ctx, tile)
    formation(ctx, lead: CGPoint(x: 650, y: 640), size: 100, heading: -0.55, count: 3, trail: 3.6)
    ctx.restoreGState()
    save(ctx, args[1], jpeg: false)
}

// ---- splash
do {
    let W = 2560, H = 1600
    let ctx = context(W, H)
    sky(ctx, CGRect(x: 0, y: 0, width: W, height: H))
    formation(ctx, lead: CGPoint(x: 1820, y: 1120), size: 120, heading: -0.62, count: 5, trail: 5.5)
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, at p: CGPoint, tracking: CGFloat = 0) -> CGFloat {
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
        let a = NSAttributedString(string: s, attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color, .kern: tracking])
        let line = CTLineCreateWithAttributedString(a)
        ctx.textPosition = p
        CTLineDraw(line, ctx)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
    let w = text("FormationFlight", size: 190, weight: .bold, color: white, at: CGPoint(x: 150, y: 400))
    _ = text("X", size: 190, weight: .bold, color: amber, at: CGPoint(x: 150 + w + 6, y: 400))
    _ = text("Fly wings together", size: 62, weight: .medium, color: col(1, 1, 1, 0.82), at: CGPoint(x: 158, y: 302))
    // the Rock FPV logo, round, beside the credit
    let logoBox = CGRect(x: 152, y: 84, width: 150, height: 150)
    if let img = NSImage(contentsOfFile: "Resources/RockFPV.png"), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: col(0, 0.05, 0.15, 0.5))
        ctx.addEllipse(in: logoBox); ctx.setFillColor(navy); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: logoBox); ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: logoBox)
        ctx.restoreGState()
        ctx.addEllipse(in: logoBox); ctx.setStrokeColor(col(1, 1, 1, 0.85)); ctx.setLineWidth(3); ctx.strokePath()
    } else { print("warning: Resources/RockFPV.png not found; splash drawn without the logo") }
    _ = text("Created by", size: 30, weight: .medium, color: col(1, 1, 1, 0.75), at: CGPoint(x: 330, y: 172))
    _ = text("Rock FPV", size: 60, weight: .bold, color: white, at: CGPoint(x: 330, y: 104))
    save(ctx, args[2], jpeg: true)
}
