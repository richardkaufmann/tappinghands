// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit
import CoreText

/// A rendered pointer: image, size in points, and the hotspot as a unit anchor (y-up, CALayer convention).
struct Sprite {
    let image: CGImage
    let size: CGSize
    let anchor: CGPoint
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Draws vector art in "design units" with y pointing DOWN, then crops to the opaque pixels.
/// `box` must contain the whole drawing; `k` = points per design unit; `hotspot` is in design units.
func makeSprite(box: CGRect, hotspot: CGPoint, k: CGFloat, scale: CGFloat, draw: (CGContext) -> Void) -> Sprite {
    let s = k * scale
    let pw = max(1, Int(ceil(box.width * s))), ph = max(1, Int(ceil(box.height * s)))
    let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(ph)); ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: -box.minX, y: -box.minY)
    ctx.setLineJoin(.round); ctx.setLineCap(.round)
    draw(ctx)

    // Crop to the opaque pixels (memory row 0 = top = box.minY), keeping the hotspot inside.
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: pw * ph * 4)
    var x0 = pw, y0 = ph, x1 = -1, y1 = -1
    for y in 0..<ph {
        let row = y * pw * 4
        for x in 0..<pw where px[row + x * 4 + 3] > 0 {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
    }
    let hx = (hotspot.x - box.minX) * s, hy = (hotspot.y - box.minY) * s
    if x1 < 0 { x0 = 0; y0 = 0; x1 = pw - 1; y1 = ph - 1 }
    let pad = Int(ceil(scale))
    x0 = max(0, min(x0, Int(hx)) - pad); y0 = max(0, min(y0, Int(hy)) - pad)
    x1 = min(pw - 1, max(x1, Int(hx)) + pad); y1 = min(ph - 1, max(y1, Int(hy)) + pad)
    let crop = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    let image = ctx.makeImage()!.cropping(to: crop)!
    let anchor = CGPoint(x: (hx - crop.minX) / crop.width, y: 1 - (hy - crop.minY) / crop.height)
    return Sprite(image: image, size: CGSize(width: crop.width / scale, height: crop.height / scale), anchor: anchor)
}

/// Small y-down drawing helpers shared by the pointer art and the click effects.
enum Draw {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func capsule(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) -> CGPath {
        let len = hypot(b.x - a.x, b.y - a.y)
        var t = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(b.y - a.y, b.x - a.x))
        return CGPath(roundedRect: CGRect(x: -w / 2, y: -w / 2, width: len + w, height: w),
                      cornerWidth: w / 2, cornerHeight: w / 2, transform: &t)
    }
    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }
    static func ellipse(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat, angle: CGFloat = 0) -> CGPath {
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
        return CGPath(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: &t)
    }
    static func rrect(_ r: CGRect, _ rad: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil)
    }
    static func poly(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p
    }
    /// n-point star/burst; `jitter` (0...1) roughens the points, seeded.
    static func star(_ c: CGPoint, outer: CGFloat, inner: CGFloat, points n: Int, rotation: CGFloat = -.pi / 2,
                     jitter: CGFloat = 0, seed: UInt64 = 1) -> CGPath {
        var rng = RNG(seed)
        var pts: [CGPoint] = []
        for i in 0..<(n * 2) {
            let a = rotation + CGFloat(i) * .pi / CGFloat(n)
            var r = i.isMultiple(of: 2) ? outer : inner
            if i.isMultiple(of: 2) { r *= 1 - jitter * rng.next() }
            pts.append(CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
        }
        return poly(pts)
    }

    static func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
        CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
    }
    static func fill(_ c: CGContext, _ p: CGPath, _ color: CGColor) {
        c.addPath(p); c.setFillColor(color); c.fillPath()
    }
    static func fill(_ c: CGContext, _ p: CGPath, _ colors: [CGColor], _ a: CGPoint, _ b: CGPoint, _ locs: [CGFloat]? = nil) {
        c.saveGState(); c.addPath(p); c.clip()
        c.drawLinearGradient(gradient(colors, locs), start: a, end: b,
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
    static func radial(_ c: CGContext, _ p: CGPath?, _ colors: [CGColor], center: CGPoint, radius: CGFloat,
                       _ locs: [CGFloat]? = nil) {
        c.saveGState()
        if let p { c.addPath(p); c.clip() }
        c.drawRadialGradient(gradient(colors, locs), startCenter: center, startRadius: 0, endCenter: center,
                             endRadius: radius, options: [.drawsBeforeStartLocation])
        c.restoreGState()
    }
    static func stroke(_ c: CGContext, _ p: CGPath, _ color: CGColor, _ w: CGFloat) {
        c.addPath(p); c.setStrokeColor(color); c.setLineWidth(w); c.strokePath()
    }
    static func curve(_ a: CGPoint, _ ctrl: CGPoint, _ b: CGPoint) -> CGPath {
        let p = CGMutablePath(); p.move(to: a); p.addQuadCurve(to: b, control: ctrl); return p
    }

    /// Centered text in a y-down context, optional outline, shrunk to fit `maxWidth`.
    static func text(_ c: CGContext, _ s: String, center: CGPoint, size: CGFloat, fill: CGColor,
                     stroke: CGColor? = nil, strokeWidth: CGFloat = 0, maxWidth: CGFloat = .infinity,
                     font name: String = "Futura-CondensedExtraBold") {
        func line(_ f: CTFont, _ extra: [NSAttributedString.Key: Any]) -> CTLine {
            var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: fill]
            extra.forEach { attrs[$0.key] = $0.value }
            return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        }
        var font = CTFontCreateWithName(name as CFString, size, nil)
        var w = CGFloat(CTLineGetTypographicBounds(line(font, [:]), nil, nil, nil))
        if w > maxWidth {
            font = CTFontCreateWithName(name as CFString, size * maxWidth / w, nil)
            w = CGFloat(CTLineGetTypographicBounds(line(font, [:]), nil, nil, nil))
        }
        let baseline = center.y + (CTFontGetCapHeight(font)) / 2
        c.saveGState()
        c.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if let stroke, strokeWidth > 0 {
            c.setLineJoin(.round)
            c.textPosition = CGPoint(x: center.x - w / 2, y: baseline)
            CTLineDraw(line(font, [.strokeColor: stroke,
                                   .strokeWidth: strokeWidth / CTFontGetSize(font) * 100]), c)
        }
        c.textPosition = CGPoint(x: center.x - w / 2, y: baseline)
        CTLineDraw(line(font, [:]), c)
        c.restoreGState()
    }
}

/// Tiny deterministic RNG so effects and art are the same every run.
struct RNG {
    private var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> CGFloat {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return CGFloat(s % 1_000_000) / 1_000_000
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

/// The pointer drawings. Every drawing is vector, in design units, y down.
enum PointerArt {
    static let ink = rgb(0x16161B)

    // MARK: embedded artwork (Streamline cartoon hand, giraffe photo)

    static let cartoonHand = NSImage(data: Data(EmbeddedArt.cartoonHandSVG.utf8))!
    /// Index fingertip pad in the SVG's 48x48 viewBox (finger is x 29.53...34.13, top at y 6.7).
    static let cartoonTip = CGPoint(x: 31.83, y: 7.6)
    static let cartoonTilt: CGFloat = -0.5    // lean up-left like a cursor (y-down: negative = CCW); rotated about the fingertip

    /// Draws an NSImage (bitmap or vector) into `r` of a y-down context, rasterized at exactly the context's
    /// device resolution so vector art stays crisp and our own transforms (rotation etc.) apply.
    static func drawImage(_ c: CGContext, _ img: NSImage, in r: CGRect) {
        let t = c.userSpaceToDeviceSpaceTransform
        let k = hypot(t.a, t.b)
        let pw = max(1, Int(ceil(r.width * k))), ph = max(1, Int(ceil(r.height * k)))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: pw * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(x: 0, y: 0, width: pw, height: ph))
        NSGraphicsContext.restoreGraphicsState()
        c.saveGState()
        c.interpolationQuality = .high
        c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: 1, y: -1)     // bitmaps draw y-up
        c.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        c.restoreGState()
    }

    static func cartoon(_ c: CGContext) {
        c.saveGState()
        c.translateBy(x: cartoonTip.x, y: cartoonTip.y); c.rotate(by: cartoonTilt)
        c.translateBy(x: -cartoonTip.x, y: -cartoonTip.y)
        drawImage(c, cartoonHand, in: CGRect(x: 0, y: 0, width: 48, height: 48))
        c.restoreGState()
    }

    static func decode(_ data: Data) -> CGImage { NSBitmapImageRep(data: data)!.cgImage! }

    /// Tip of a raster pointer = opaque pixel nearest the top-left, nudged `inset` px inward.
    static func rasterTip(_ img: CGImage, inset: CGFloat = 2) -> CGPoint {
        let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: Draw.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var best = (x: 0, y: 0, score: Int.max)
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 128 && x + y < best.score { best = (x, y, x + y) } }
        return CGPoint(x: CGFloat(best.x) + inset, y: CGFloat(best.y) + inset)
    }

    /// Draws a bitmap with its top-left at the origin in a y-down context.
    static func drawRaster(_ c: CGContext, _ img: CGImage) {
        c.saveGState()
        c.interpolationQuality = .high
        c.translateBy(x: 0, y: CGFloat(img.height)); c.scaleBy(x: 1, y: -1)
        c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        c.restoreGState()
    }

    static let giraffe = decode(EmbeddedArt.giraffePNG)
    static let giraffeTip = rasterTip(giraffe, inset: 4)
    /// Where Eddie's tongue leaves his lips, in Assets/giraffe.png pixels.
    static let giraffeMouth = CGPoint(x: 63, y: 58)

    // MARK: fountain pen (original: lacquer barrel, gold furniture)

    static let oxblood = [rgb(0x2A0309), rgb(0x7A1424), rgb(0xD25068), rgb(0x861629), rgb(0x2A0309)]
    static let royalBlue = [rgb(0x041233), rgb(0x123C8C), rgb(0x5A8EE8), rgb(0x1A4AA6), rgb(0x041233)]
    static let racingGreen = [rgb(0x02200F), rgb(0x0E5A32), rgb(0x4FB27A), rgb(0x136B3C), rgb(0x02200F)]

    static func fountainPen(_ c: CGContext, lacquer: [CGColor] = oxblood) {
        typealias D = Draw
        c.saveGState()
        c.rotate(by: -.pi / 4)                      // nib at the origin, body up and to the right
        let line = rgb(0x140A04)
        let lw: CGFloat = 0.8
        let a = CGPoint(x: 0, y: -9.6), b = CGPoint(x: 0, y: 9.6)
        let locs: [CGFloat] = [0, 0.22, 0.4, 0.62, 1]
        let gold = [rgb(0x5E400B), rgb(0xB8862A), rgb(0xFBE7A1), rgb(0xD4A23A), rgb(0x6B4A0E)]
        let black = [rgb(0x000000), rgb(0x2B2B2E), rgb(0x7A7A82), rgb(0x1A1A1C), rgb(0x000000)]
        func piece(_ p: CGPath, _ g: [CGColor]) { D.fill(c, p, g, a, b, locs); D.stroke(c, p, line, lw) }

        piece(D.rrect(CGRect(x: 40, y: -9, width: 70, height: 18), 8.5), lacquer)      // barrel + cap
        piece(D.rrect(CGRect(x: 66, y: -9.7, width: 5, height: 19.4), 1.2), gold)      // cap band
        piece(D.rrect(CGRect(x: 107, y: -5, width: 6.5, height: 10), 3), gold)        // finial
        piece(D.rrect(CGRect(x: 36, y: -8.3, width: 5, height: 16.6), 1.2), gold)      // ring
        piece(D.poly([CGPoint(x: 20, y: -6.4), CGPoint(x: 36.5, y: -7.6), CGPoint(x: 36.5, y: 7.6),
                      CGPoint(x: 20, y: 6.4)]), black)                                // grip
        let nib = CGMutablePath()
        nib.move(to: .zero)
        nib.addQuadCurve(to: CGPoint(x: 22, y: -7), control: CGPoint(x: 9, y: -6.4))
        nib.addLine(to: CGPoint(x: 22, y: 7))
        nib.addQuadCurve(to: .zero, control: CGPoint(x: 9, y: 6.4))
        nib.closeSubpath()
        piece(nib, gold)
        D.stroke(c, D.curve(CGPoint(x: 1.5, y: 0), CGPoint(x: 8, y: 0), CGPoint(x: 13.5, y: 0)), line, 0.7)
        D.fill(c, D.circle(CGPoint(x: 15, y: 0), 1.5), line)
        D.stroke(c, D.curve(CGPoint(x: 17, y: -5), CGPoint(x: 19.5, y: 0), CGPoint(x: 17, y: 5)), rgb(0x5E400B), 0.6)
        // Clip along the top of the cap.
        piece(D.capsule(CGPoint(x: 72, y: -11.4), CGPoint(x: 103, y: -11.4), 3.2), gold)
        piece(D.circle(CGPoint(x: 72, y: -11.4), 2.6), gold)
        c.restoreGState()
    }

    // MARK: magic wand

    static func sparkle(_ c: CGContext, at p: CGPoint, r: CGFloat) {
        Draw.radial(c, nil, [rgb(0xFFF6C8, 0.85), rgb(0xFFE07A, 0.0)], center: p, radius: r * 1.1)
        let s = Draw.star(p, outer: r, inner: r * 0.26, points: 4)
        Draw.fill(c, s, rgb(0xFFD94A))
        Draw.stroke(c, s, rgb(0x9A6A00), r * 0.08)
        Draw.fill(c, Draw.star(p, outer: r * 0.55, inner: r * 0.16, points: 4), rgb(0xFFFFFF))
    }

    static func magicWand(_ c: CGContext) {
        typealias D = Draw
        c.saveGState()
        c.rotate(by: .pi / 4)                       // tip at the origin, handle down and to the right
        let a = CGPoint(x: 0, y: -5), b = CGPoint(x: 0, y: 5)
        let white = [rgb(0xFFFFFF), rgb(0xFFFFFF), rgb(0xC9CAD3)]
        let shaft = D.poly([CGPoint(x: 16, y: -4.1), CGPoint(x: 94, y: -4.9), CGPoint(x: 94, y: 4.9), CGPoint(x: 16, y: 4.1)])
        D.fill(c, shaft, [rgb(0x000000), rgb(0x6A6A74), rgb(0x141416), rgb(0x000000)], a, b, [0, 0.3, 0.55, 1])
        D.stroke(c, shaft, rgb(0x8A8A96), 0.8)
        for p in [D.capsule(CGPoint(x: 4.3, y: 0), CGPoint(x: 15, y: 0), 8.6),
                  D.capsule(CGPoint(x: 92, y: 0), CGPoint(x: 97, y: 0), 10)] {
            D.fill(c, p, white, a, b, [0, 0.35, 1])
            D.stroke(c, p, rgb(0x111111), 0.9)
        }
        c.restoreGState()
        sparkle(c, at: .zero, r: 8)
        sparkle(c, at: CGPoint(x: -9, y: 9), r: 3.2)
    }

    // MARK: foam finger

    static func foamFinger(_ c: CGContext) {
        typealias D = Draw
        c.saveGState()
        c.rotate(by: -0.3)
        let o: CGFloat = 3.6
        let edge = rgb(0x0A2266)
        let finger = D.capsule(CGPoint(x: 0, y: 12), CGPoint(x: 0, y: 58), 24)
        let palm = D.rrect(CGRect(x: -20, y: 44, width: 78, height: 80), 24)
        let bumps = [D.circle(CGPoint(x: 22, y: 49), 13), D.circle(CGPoint(x: 37, y: 53), 12.5),
                     D.circle(CGPoint(x: 50, y: 61), 11)]
        let thumb = D.capsule(CGPoint(x: 6, y: 94), CGPoint(x: -24, y: 72), 22)
        let body = [finger, palm] + bumps + [thumb]
        let foam = [rgb(0x6FA8FF), rgb(0x2E63E0), rgb(0x143C9E)]
        let g0 = CGPoint(x: -20, y: 0), g1 = CGPoint(x: 60, y: 125)
        for p in body { D.stroke(c, p, edge, 2 * o) }
        for p in body { D.fill(c, p, foam, g0, g1, [0, 0.5, 1]) }
        let fEdge = CGMutablePath()
        fEdge.move(to: CGPoint(x: 12, y: 40)); fEdge.addLine(to: CGPoint(x: 12, y: 58))
        fEdge.addArc(center: CGPoint(x: 0, y: 58), radius: 12, startAngle: 0, endAngle: 2.0, clockwise: false)
        D.stroke(c, fEdge, edge, o * 0.6)
        D.stroke(c, D.curve(CGPoint(x: 29.5, y: 41), CGPoint(x: 31.5, y: 47), CGPoint(x: 30.5, y: 53)), edge, o * 0.5)
        D.stroke(c, D.curve(CGPoint(x: 44.5, y: 49), CGPoint(x: 46.5, y: 54), CGPoint(x: 45.5, y: 59)), edge, o * 0.5)
        D.fill(c, thumb, foam, g0, g1, [0, 0.5, 1])
        D.stroke(c, thumb, edge, o * 0.6)
        // Sleeve opening at the bottom.
        let hole = D.ellipse(CGPoint(x: 19, y: 123), 62, 13)
        D.fill(c, hole, [rgb(0x061540), rgb(0x0F2A78)], CGPoint(x: 0, y: 117), CGPoint(x: 0, y: 129))
        D.stroke(c, hole, edge, o * 0.6)
        // Foam sheen + "#1".
        D.fill(c, D.ellipse(CGPoint(x: -5, y: 22), 6, 26), rgb(0xFFFFFF, 0.35))
        D.text(c, "#1", center: CGPoint(x: 26, y: 91), size: 32, fill: rgb(0xFFFFFF),
               stroke: edge, strokeWidth: 5)
        c.restoreGState()
    }

    // MARK: laser pointer

    static func laserDot(_ c: CGContext) {
        Draw.radial(c, nil, [rgb(0xFF2020, 0.55), rgb(0xFF2020, 0.18), rgb(0xFF2020, 0)], center: .zero,
                    radius: 17, [0, 0.45, 1])
        Draw.radial(c, Draw.circle(.zero, 5.5), [rgb(0xFFFFFF), rgb(0xFF8080), rgb(0xFF1A1A), rgb(0xC00000)],
                    center: CGPoint(x: -1, y: -1), radius: 6.5, [0, 0.25, 0.7, 1])
    }

    // MARK: cat paw (toe beans up)

    static func catPaw(_ c: CGContext) {
        typealias D = Draw
        c.saveGState()
        c.rotate(by: -0.35)
        let o: CGFloat = 3
        let edge = rgb(0x6B3A12)
        let toes = [CGPoint(x: -23, y: 30), CGPoint(x: -8, y: 17), CGPoint(x: 8, y: 17), CGPoint(x: 23, y: 30)]
        let fur = [D.circle(CGPoint(x: 0, y: 62), 34), D.circle(CGPoint(x: 0, y: 40), 28)] + toes.map { D.circle($0, 15.5) }
        let coat = [rgb(0xFFE2BC), rgb(0xF6B26E), rgb(0xE08A45)]
        for p in fur { D.stroke(c, p, edge, 2 * o) }
        for p in fur { D.fill(c, p, coat, CGPoint(x: -20, y: 0), CGPoint(x: 25, y: 96), [0, 0.5, 1]) }
        // A few fur tufts.
        for (p, q) in [(CGPoint(x: -34, y: 70), CGPoint(x: -29, y: 72)), (CGPoint(x: 34, y: 68), CGPoint(x: 29, y: 71)),
                       (CGPoint(x: -15, y: 93), CGPoint(x: -12, y: 89))] {
            D.stroke(c, D.curve(p, CGPoint(x: (p.x + q.x) / 2, y: p.y - 2), q), edge, o * 0.45)
        }
        let bean = [rgb(0xFFB3C6), rgb(0xF08AA6), rgb(0xD9607F)]
        let pad = [D.circle(CGPoint(x: -11, y: 67), 13), D.circle(CGPoint(x: 11, y: 67), 13),
                   D.circle(CGPoint(x: 0, y: 59), 13), D.ellipse(CGPoint(x: 0, y: 74), 46, 22)]
        for p in pad { D.fill(c, p, bean, CGPoint(x: 0, y: 46), CGPoint(x: 0, y: 86), [0, 0.5, 1]) }
        D.fill(c, D.ellipse(CGPoint(x: -7, y: 57), 8, 5, angle: -0.4), rgb(0xFFFFFF, 0.55))
        for (i, t) in toes.enumerated() {
            let p = D.ellipse(t, 14, 18, angle: [-0.4, -0.12, 0.12, 0.4][i])
            D.fill(c, p, bean, CGPoint(x: t.x, y: t.y - 9), CGPoint(x: t.x, y: t.y + 9), [0, 0.5, 1])
            D.fill(c, D.ellipse(CGPoint(x: t.x - 2, y: t.y - 4), 4, 3, angle: -0.4), rgb(0xFFFFFF, 0.55))
        }
        c.restoreGState()
    }
    /// Top of the leading toe, after the paw's tilt.
    static let pawTip = CGPoint(x: 8, y: 2.5).applying(CGAffineTransform(rotationAngle: -0.35))

    // MARK: retro pixel hand (original 16 x 18 bitmap)

    static let pixelRows = [
        "....XX..........",
        "...XooX.........",
        "...XooX.........",
        "...XooX.........",
        "...XooXXX.......",
        "...XooXooXXX....",
        "...XooXooXooXX..",
        ".XXXooXooXooXoX.",
        "XooXoooooooooooX",
        "XoooXooooooooooX",
        ".XoooooooooooooX",
        ".XoooooooooooogX",
        "..XooooooooooggX",
        "..XoooooooooogX.",
        "...XoooooooogX..",
        "...XXXXXXXXXXX..",
        "...XgggggggggX..",
        "...XXXXXXXXXXX..",
    ]
    static let pixel: CGFloat = 6

    static func retroPixel(_ c: CGContext) {
        c.setShouldAntialias(false)
        for (y, row) in pixelRows.enumerated() {
            for (x, ch) in row.enumerated() {
                let col: CGColor
                switch ch { case "X": col = rgb(0x000000); case "o": col = rgb(0xFFFFFF); case "g": col = rgb(0xB8B8B8)
                default: continue }
                c.setFillColor(col)
                c.fill(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel + 0.01, height: pixel + 0.01))
            }
        }
        c.setShouldAntialias(true)
    }
}
