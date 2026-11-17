// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

/// Renders the pointing hand from the built-in SF Symbol "hand.point.up.left" (white fill, black outline)
/// and finds the fingertip so it can be pinned exactly to the pointer's hotspot.
struct HandArt {
    let image: CGImage
    let size: CGSize         // in points
    let tipAnchor: CGPoint   // unit coordinates, y-up (CALayer anchorPoint)

    static func make(pointSize: CGFloat, scale: CGFloat) -> HandArt {
        let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .light)
        let fill = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(base.applying(.init(paletteColors: [.white])))!
        let line = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: nil)!
            .withSymbolConfiguration(base.applying(.init(paletteColors: [.black])))!

        let pad: CGFloat = 2
        let size = CGSize(width: ceil(max(fill.size.width, line.size.width) + pad * 2),
                          height: ceil(max(fill.size.height, line.size.height) + pad * 2))
        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: pw * 4, bitsPerPixel: 32)!
        rep.size = size
        func centered(_ s: CGSize) -> CGRect {
            CGRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2, width: s.width, height: s.height)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        fill.draw(in: centered(fill.size))
        line.draw(in: centered(line.size))
        NSGraphicsContext.restoreGraphicsState()

        // Fingertip = the opaque pixel furthest toward the top-left (the finger points up-left).
        var best = (x: 0, y: 0, score: Int.max)
        if let data = rep.bitmapData {
            for y in 0..<ph {
                for x in 0..<pw where data[(y * pw + x) * 4 + 3] > 128 {
                    if x + y < best.score { best = (x, y, x + y) }
                }
            }
        }
        // Nudge ~1pt inward so the finger pad, not its outer edge, sits on the hotspot.
        let tipX = (CGFloat(best.x) + 0.5) / scale + 1
        let tipY = (CGFloat(best.y) + 0.5) / scale + 1
        let anchor = CGPoint(x: tipX / size.width, y: 1 - tipY / size.height)
        return HandArt(image: rep.cgImage!, size: size, tipAnchor: anchor)
    }
}
