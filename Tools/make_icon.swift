// Draws the FormationFlightX app icon and splash artwork: three flying wings in a vic.
// Usage: swift Tools/make_icon.swift <icon.png> <splash.jpg>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
let red = col(0.76, 0.13, 0.10), ring1 = col(0.70, 0.10, 0.08), ring2 = col(0.66, 0.09, 0.07)
let shadow = col(0.42, 0.05, 0.04, 0.55), cream = col(0.965, 0.93, 0.875), ink = col(0.11, 0.075, 0.07)

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// A swept flying wing seen from above, nose toward +y, about 2 units in span, centred on the origin.
func wing(_ ctx: CGContext, fill: CGColor?, stripe: Bool) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0.52))
    p.addLine(to: CGPoint(x: 0.96, y: -0.28)); p.addLine(to: CGPoint(x: 1.0, y: -0.50)); p.addLine(to: CGPoint(x: 0.80, y: -0.50))
    p.addLine(to: CGPoint(x: 0.16, y: -0.20)); p.addLine(to: CGPoint(x: 0, y: -0.30)); p.addLine(to: CGPoint(x: -0.16, y: -0.20))
    p.addLine(to: CGPoint(x: -0.80, y: -0.50)); p.addLine(to: CGPoint(x: -1.0, y: -0.50)); p.addLine(to: CGPoint(x: -0.96, y: -0.28))
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(fill ?? cream); ctx.fillPath()
    guard fill == nil else { return }
    if stripe {
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.setFillColor(red)
        for x in [CGFloat(-0.74), 0.64] { ctx.fill(CGRect(x: x, y: -0.6, width: 0.10, height: 1.2)) }
        ctx.restoreGState()
    }
    // centre pod
    let pod = CGPath(roundedRect: CGRect(x: -0.085, y: -0.26, width: 0.17, height: 0.74), cornerWidth: 0.085, cornerHeight: 0.085, transform: nil)
    ctx.addPath(pod); ctx.setFillColor(ink); ctx.fillPath()
}

/// Three wings in a vic, each `s` points in half-span, around a centre.
func vic(_ ctx: CGContext, center c: CGPoint, s: CGFloat, tilt: CGFloat) {
    let places: [(CGFloat, CGFloat)] = [(0, 0.95), (1.25, -0.35), (-1.25, -0.35)]
    for pass in 0..<2 {
        for (i, pl) in places.enumerated() {
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: tilt)
            ctx.translateBy(x: pl.0 * s + (pass == 0 ? 0.10 * s : 0), y: pl.1 * s - (pass == 0 ? 0.16 * s : 0))
            ctx.scaleBy(x: s, y: s)
            wing(ctx, fill: pass == 0 ? shadow : nil, stripe: i == 0)
            ctx.restoreGState()
        }
    }
}

func save(_ ctx: CGContext, _ path: String, jpeg: Bool) {
    let type = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type, 1, nil)!
    CGImageDestinationAddImage(dst, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    CGImageDestinationFinalize(dst)
}

let args = CommandLine.arguments
guard args.count > 2 else { print("usage: make_icon <icon.png> <splash.jpg>"); exit(1) }

// ---- icon: macOS shape, 824pt rounded square on a 1024 canvas
do {
    let ctx = context(1024, 1024)
    let shape = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: col(0, 0, 0, 0.35))
    ctx.addPath(shape); ctx.setFillColor(red); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    let c = CGPoint(x: 560, y: 480)
    for (r, colr) in [(CGFloat(470), ring1), (330, ring2)] { ctx.setFillColor(colr); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
    vic(ctx, center: CGPoint(x: 512, y: 512), s: 138, tilt: -0.42)
    ctx.restoreGState()
    save(ctx, args[1], jpeg: false)
}

// ---- splash
do {
    let W = 2560, H = 1600
    let ctx = context(W, H)
    ctx.setFillColor(red); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let c = CGPoint(x: 1780, y: 860)
    for (r, colr) in [(CGFloat(1150), ring1), (780, ring2)] { ctx.setFillColor(colr); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
    vic(ctx, center: CGPoint(x: 1960, y: 860), s: 215, tilt: -0.5)
    func text(_ s: String, size: CGFloat, weight: CGFloat, color: CGColor, at p: CGPoint, tracking: CGFloat = 0) -> CGFloat {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(font), [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]] as CFDictionary)
        let f = CTFontCreateWithFontDescriptor(desc, size, nil)
        let a = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f,
                                                           NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                                                           NSAttributedString.Key(kCTKernAttributeName as String): tracking])
        let line = CTLineCreateWithAttributedString(a)
        ctx.textPosition = p
        CTLineDraw(line, ctx)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
    _ = text("FLYING-WING FORMATION TRAINER", size: 40, weight: 0.6, color: cream, at: CGPoint(x: 170, y: 1010), tracking: 12)
    _ = text("FORMATION", size: 250, weight: 0.9, color: cream, at: CGPoint(x: 160, y: 740), tracking: -8)
    let w = text("FLIGHT", size: 250, weight: 0.9, color: cream, at: CGPoint(x: 160, y: 510), tracking: -8)
    _ = text("X", size: 250, weight: 0.9, color: ink, at: CGPoint(x: 160 + w + 30, y: 510))
    _ = text("CREATED BY ROCK FPV", size: 34, weight: 0.6, color: cream, at: CGPoint(x: 170, y: 400), tracking: 8)
    save(ctx, args[2], jpeg: true)
}
