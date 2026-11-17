// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

/// Offscreen renders (no screen capture involved), built from the same HandOverlayView the app uses.
/// `TapHand --render-frames <dir>`: per-intensity rest/pressed frames for the current default theme.
/// `TapHand --render-themes <dir>`: approval sheet of every theme (rest / left click / right click on white and
/// black) plus a size strip showing the vector art from 24 to 128 pt.
enum FrameRenderer {
    static let scale: CGFloat = 2

    /// Renders one cell: pointer hotspot at `tip` (y-up, points), optionally pressed with its effect frozen at t.
    static func cell(style: PointerStyle, points: CGFloat, intensity: TapIntensity = .normal, size: CGSize, tip: CGPoint,
                     background: CGColor, pressed: Bool, right: Bool, crosshair: Bool = false, t: CGFloat? = nil) -> CGImage {
        let v = HandOverlayView(frame: NSRect(origin: .zero, size: size))
        v.root.frame = v.bounds
        v.configure(style: style, points: points, intensity: intensity, scale: scale)
        v.moveHand(toLocal: tip)
        if pressed { v.setPressed(true, animated: false) }
        // The effect plays on after the press is released, so draw it whenever a time is given.
        if pressed || t != nil { v.effect(atLocal: tip, right: right, frozenAt: t ?? style.previewT) }
        if crosshair {
            let mark = CAShapeLayer()
            let p = CGMutablePath()
            p.move(to: CGPoint(x: tip.x - 6, y: tip.y)); p.addLine(to: CGPoint(x: tip.x + 6, y: tip.y))
            p.move(to: CGPoint(x: tip.x, y: tip.y - 6)); p.addLine(to: CGPoint(x: tip.x, y: tip.y + 6))
            mark.path = p; mark.strokeColor = NSColor.systemRed.cgColor; mark.lineWidth = 1
            v.root.addSublayer(mark)
        }
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: Draw.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        v.root.render(in: ctx)
        return ctx.makeImage()!
    }

    static func save(_ img: CGImage, _ dir: String, _ name: String) {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
    }

    static func run(outDir: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        for intensity in TapIntensity.allCases {
            for (name, pressed, right) in [("rest", false, false), ("pressed-left", true, false), ("pressed-right", true, true)] {
                let img = cell(style: Theme.plain.pointerStyle, points: 66, intensity: intensity, size: CGSize(width: 220, height: 180),
                               tip: CGPoint(x: 70, y: 120), background: rgb(0xEDEDED), pressed: pressed, right: right,
                               crosshair: true)
                save(img, outDir, "\(intensity.rawValue)-\(name).png")
            }
        }
        print("Wrote frames to \(outDir)")
    }

    // MARK: theme sheet

    /// Where to put the hotspot so the pointer's art is centered in a cell.
    static func tip(for style: PointerStyle, points: CGFloat, in size: CGSize) -> CGPoint {
        let s = style.sprite(points, scale)
        return CGPoint(x: size.width / 2 + (s.anchor.x - 0.5) * s.size.width,
                       y: size.height / 2 + (s.anchor.y - 0.5) * s.size.height)
    }

    static func runThemes(outDir: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let pts: CGFloat = 64
        let labelW: CGFloat = 170, cellW: CGFloat = 200, header: CGFloat = 40, gap: CGFloat = 16
        // Built-ins plus any custom cursors installed on this Mac (rendered locally only).
        let rows: [(PointerStyle, CGFloat)] = (Theme.allCases.map(\.pointerStyle) + CustomCursors.all()).map { t in
            let s = t.sprite(pts, scale)
            return (t, max(190, s.size.height + 110))   // headroom so click effects aren't clipped
        }
        let W = labelW + cellW * 6 + gap
        let H = header + rows.reduce(0) { $0 + $1.1 }
        let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: Draw.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: labelW + cellW * 3, height: H))
        ctx.setFillColor(rgb(0x7F7F7F)); ctx.fill(CGRect(x: labelW + cellW * 3, y: 0, width: gap, height: H))
        ctx.setFillColor(rgb(0x000000)); ctx.fill(CGRect(x: labelW + cellW * 3 + gap, y: 0, width: cellW * 3, height: H))

        // y-up drawing; text helper wants y-down, so flip locally for labels.
        func label(_ s: String, x: CGFloat, yTop: CGFloat, size: CGFloat, color: CGColor, bold: Bool = true) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
            Draw.text(ctx, s, center: CGPoint(x: x, y: yTop), size: size, fill: color,
                      font: bold ? "HelveticaNeue-Bold" : "HelveticaNeue")
            ctx.restoreGState()
        }
        let heads = ["Rest", "Left click", "Right click"]
        for (i, h) in heads.enumerated() {
            label(h, x: labelW + cellW * (CGFloat(i) + 0.5), yTop: header / 2, size: 15, color: rgb(0x333333))
            label(h, x: labelW + cellW * 3 + gap + cellW * (CGFloat(i) + 0.5), yTop: header / 2, size: 15, color: rgb(0xDDDDDD))
        }
        var yTop = header
        for (n, (theme, rowH)) in rows.enumerated() {
            let y = H - yTop - rowH
            label("\(n). \(theme.title)", x: labelW / 2, yTop: yTop + rowH / 2, size: 16, color: rgb(0x111111))
            let size = CGSize(width: cellW, height: rowH)
            var tip = tip(for: theme, points: pts, in: size)
            tip.y = min(tip.y, rowH - 80); tip.x = max(tip.x, 70)
            for (bgIndex, bg) in [rgb(0xFFFFFF), rgb(0x000000)].enumerated() {
                for (i, (pressed, right)) in [(false, false), (true, false), (true, true)].enumerated() {
                    let img = cell(style: theme, points: pts, size: size, tip: tip, background: bg,
                                   pressed: pressed, right: right)
                    let x = labelW + CGFloat(bgIndex) * (cellW * 3 + gap) + cellW * CGFloat(i)
                    ctx.draw(img, in: CGRect(x: x, y: y, width: cellW, height: rowH))
                }
            }
            ctx.setFillColor(rgb(0x888888, 0.35))
            ctx.fill(CGRect(x: 0, y: y, width: W, height: 1))
            yTop += rowH
        }
        save(ctx.makeImage()!, outDir, "themes-sheet.png")

        // Size strip: cartoon hand, giraffe and the blue pen at several sizes, white then black.
        let sizes: [CGFloat] = [24, 40, 64, 96, 128]
        let strip: [PointerStyle] = [Theme.cartoonHand.pointerStyle, Theme.giraffe.pointerStyle, Theme.fountainPenBlue.pointerStyle]
        for (bgName, bg) in [("white", rgb(0xFFFFFF)), ("black", rgb(0x000000))] {
            // Height per theme row = tallest at 128 pt.
            let rowHs = strip.map { $0.sprite(128, scale).size.height + 24 }
            let rowW = strip.map { t in sizes.reduce(0) { $0 + max(60, t.sprite($1, scale).size.width + 24) } }
            let SW = rowW.max()! + 20, SH = rowHs.reduce(0, +)
            let sc = CGContext(data: nil, width: Int(SW * scale), height: Int(SH * scale), bitsPerComponent: 8,
                               bytesPerRow: 0, space: Draw.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sc.scaleBy(x: scale, y: scale)
            sc.setFillColor(bg); sc.fill(CGRect(x: 0, y: 0, width: SW, height: SH))
            var top: CGFloat = 0
            for (r, t) in strip.enumerated() {
                var x: CGFloat = 10
                for p in sizes {
                    let sp = t.sprite(p, scale)
                    let w = max(60, sp.size.width + 24)
                    let cs = CGSize(width: w, height: rowHs[r])
                    let img = cell(style: t, points: p, size: cs,
                                   tip: CGPoint(x: (w - sp.size.width) / 2 + sp.anchor.x * sp.size.width,
                                                y: 12 + sp.anchor.y * sp.size.height + (rowHs[r] - 24 - sp.size.height)),
                                   background: bg, pressed: false, right: false)
                    sc.draw(img, in: CGRect(x: x, y: SH - top - rowHs[r], width: w, height: rowHs[r]))
                    x += w
                }
                top += rowHs[r]
            }
            save(sc.makeImage()!, outDir, "sizes-\(bgName).png")
        }
        // Frame-by-frame strips of the giraffe's effects (left = lick, right = hearts).
        for (name, right) in [("left", false), ("right", true)] {
            let times: [CGFloat] = [0.08, 0.2, 0.35, 0.5, 0.7, 0.9]
            let cs = CGSize(width: 230, height: 230)
            let st = CGContext(data: nil, width: Int(cs.width * CGFloat(times.count) * scale), height: Int(cs.height * scale),
                               bitsPerComponent: 8, bytesPerRow: 0, space: Draw.sRGB,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            st.scaleBy(x: scale, y: scale)
            for (i, t) in times.enumerated() {
                let img = cell(style: Theme.giraffe.pointerStyle, points: pts, size: cs, tip: CGPoint(x: 80, y: 130),
                               background: rgb(0xFFFFFF), pressed: true, right: right, t: t)
                st.draw(img, in: CGRect(x: cs.width * CGFloat(i), y: 0, width: cs.width, height: cs.height))
            }
            save(st.makeImage()!, outDir, "giraffe-\(name)-frames.png")
        }
        print("Wrote theme sheet to \(outDir)")
    }

    // MARK: app icon

    /// `TapHand --render-icon <dir>`: writes <dir>/AppIcon.iconset (blue fountain pen on paper) for iconutil.
    static func runIcon(outDir: String) {
        let set = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for mult in [1, 2] {
                let px = base * mult
                let name = mult == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                save(icon(px: px), set.path, name)
            }
        }
        print("Wrote \(set.path)")
    }

    /// Drawn on a 1024-unit canvas (y down), scaled to `px`.
    static func icon(px: Int) -> CGImage {
        let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: Draw.sRGB,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let k = CGFloat(px) / 1024
        c.translateBy(x: 0, y: CGFloat(px)); c.scaleBy(x: k, y: -k)
        c.setLineJoin(.round); c.setLineCap(.round)
        // macOS icon grid: 824-unit rounded square centred in 1024, with a soft drop shadow.
        let tile = Draw.rrect(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x000000, 0.28))
        Draw.fill(c, tile, rgb(0xFFFFFF))
        c.restoreGState()
        Draw.fill(c, tile, [rgb(0xFFFFFF), rgb(0xF3F6FB), rgb(0xDCE4F0)], CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 924))
        // A blot of blue ink where the nib touches the paper.
        let ink = rgb(0x1B3FA0, 0.92)
        let nib = CGPoint(x: 292, y: 742)
        var rng = RNG(42)
        Draw.fill(c, Draw.ellipse(CGPoint(x: nib.x - 6, y: nib.y + 8), 150, 104, angle: -0.3), ink)
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * 2 * .pi + rng.range(-0.2, 0.2), d = rng.range(58, 80)
            Draw.fill(c, Draw.circle(CGPoint(x: nib.x - 6 + d * cos(a) * 1.2, y: nib.y + 8 + d * sin(a) * 0.8),
                                     rng.range(16, 28)), ink)
        }
        for _ in 0..<6 {
            let a = rng.range(0, 2 * .pi), d = rng.range(115, 150)
            Draw.fill(c, Draw.circle(CGPoint(x: nib.x + d * cos(a) * 1.1, y: nib.y + d * sin(a) * 0.75), rng.range(6, 12)), ink)
        }
        // The pen: nib at `nib`, body up and to the right.
        c.saveGState()
        c.translateBy(x: nib.x, y: nib.y)
        c.scaleBy(x: 5.2, y: 5.2)
        c.setShadow(offset: CGSize(width: 2, height: 3), blur: 4, color: rgb(0x000000, 0.35))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        PointerArt.fountainPen(c, lacquer: PointerArt.royalBlue)
        c.endTransparencyLayer()
        c.restoreGState()
        return c.makeImage()!
    }

    // MARK: README animation

    /// `TapHand --render-demo <dir>`: 20 fps frames for the README demo GIF: every built-in theme in a grid, taking
    /// turns (one click at a time, in menu order, so it never gets busy). Writes `p<tile>_<frame>.png` plus
    /// `manifest.json` (columns, labels); tools/make_demo_gif.py assembles docs/taphand-demo.gif.
    static func runDemoFrames(outDir: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        // Roomy canvas per theme; tools/make_demo_gif.py crops each to what its pointer + effect actually touch.
        let bg = rgb(0xFBF8F2), pts: CGFloat = 56, size = CGSize(width: 380, height: 320), cols = 4
        let styles = Theme.allCases.map(\.pointerStyle)
        let tips: [CGPoint] = styles.map { style in
            var t = tip(for: style, points: pts, in: size)
            t.y = min(t.y, size.height - 110); t.x = max(t.x, 120)     // headroom for effects above / left
            return t
        }
        // Click schedule: one theme at a time, each for its effect's length, with a short breather between.
        var schedule: [(start: Int, length: Int)] = []
        var f = 6
        for style in styles {
            let d = style.effect.make(R: pts * 0.55, right: false, scale: 1, opacity: 1, seq: 0).duration
            let n = max(8, Int(ceil(d * 20)))
            schedule.append((f, n)); f += n + 3
        }
        let total = f + 8
        for frame in 0..<total {
            for (i, style) in styles.enumerated() {
                let (start, n) = schedule[i], k = frame - start
                let img = (0..<n).contains(k)
                    ? cell(style: style, points: pts, size: size, tip: tips[i], background: bg, pressed: k < 3, right: false,
                           t: CGFloat(k) / CGFloat(n - 1))
                    : cell(style: style, points: pts, size: size, tip: tips[i], background: bg, pressed: false, right: false)
                save(img, outDir, String(format: "p%02d_%03d.png", i, frame))
            }
        }
        let manifest: [String: Any] = ["cols": cols, "frames": total, "labels": styles.map(\.title)]
        if let data = try? JSONSerialization.data(withJSONObject: manifest) {
            try? data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("manifest.json"))
        }
        print("Wrote \(total) frames x \(styles.count) tiles to \(outDir)")
    }
}
