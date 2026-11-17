// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import CoreGraphics

/// Everything the overlay needs to draw a pointer. Built-in themes and custom cursors both produce one.
struct PointerStyle {
    let id: String              // stored in settings: a Theme raw value, or "custom:<file name>"
    let title: String
    let effect: EffectKind
    let tilts: Bool
    let castsShadow: Bool
    /// (points, backing scale) -> rendered art; `points` = the pointer's main body size (the Size slider).
    let sprite: (CGFloat, CGFloat) -> Sprite
    /// Where the pointer's mouth is relative to its hotspot, in layer points for a given size (Eddie's tongue).
    var mouth: ((CGFloat) -> CGPoint)? = nil
    var previewT: CGFloat { effect.previewT }

    /// Resolves a stored id; unknown or missing custom cursors fall back to the Plain Hand.
    static func resolve(_ id: String) -> PointerStyle {
        if let t = Theme(rawValue: id) { return t.pointerStyle }
        return CustomCursors.style(id: id) ?? Theme.plain.pointerStyle
    }
}

/// A built-in pointer theme = vector/embedded artwork + hotspot + click effect.
enum Theme: String, CaseIterable {
    case plain, cartoonHand, giraffe, fountainPen, fountainPenBlue, fountainPenGreen, magicWand, foamFinger,
         laserPointer, comicPow, catPaw, retroPixel

    var title: String {
        switch self {
        case .plain: "Plain Hand"
        case .cartoonHand: "Cartoon Hand"
        case .giraffe: "Eddie the Giraffe"
        case .fountainPen: "Fountain Pen (Oxblood)"
        case .fountainPenBlue: "Fountain Pen (Blue)"
        case .fountainPenGreen: "Fountain Pen (Green)"
        case .magicWand: "Magic Wand"
        case .foamFinger: "Foam Finger"
        case .laserPointer: "Laser Pointer"
        case .comicPow: "Comic POW"
        case .catPaw: "Cat Paw"
        case .retroPixel: "Retro Pixel"
        }
    }

    var effect: EffectKind {
        switch self {
        case .plain, .cartoonHand: .rings
        case .giraffe: .lick
        case .fountainPen, .fountainPenBlue, .fountainPenGreen: .inkSplat
        case .magicWand: .stars
        case .foamFinger: .confetti
        case .laserPointer: .laserFlash
        case .comicPow: .comicBurst
        case .catPaw: .pawPrint
        case .retroPixel: .pixelRipple
        }
    }

    /// Whether the press animation tilts the art (tilting a dot or pixel art looks wrong).
    var tilts: Bool { self != .laserPointer && self != .retroPixel }
    var castsShadow: Bool { self != .laserPointer }

    var pointerStyle: PointerStyle {
        var s = PointerStyle(id: rawValue, title: title, effect: effect, tilts: tilts, castsShadow: castsShadow) { points, scale in
            sprite(points: points, scale: scale)
        }
        if self == .giraffe {
            s.mouth = { points in
                let k = points / 380, m = PointerArt.giraffeMouth, t = PointerArt.giraffeTip
                return CGPoint(x: (m.x - t.x) * k, y: -(m.y - t.y) * k)      // image is y-down, layers are y-up
            }
        }
        return s
    }

    /// `points` = the pointer's main body size (the Size slider).
    func sprite(points: CGFloat, scale: CGFloat) -> Sprite {
        func art(_ box: CGRect, _ hot: CGPoint, body: CGFloat, _ draw: (CGContext) -> Void) -> Sprite {
            makeSprite(box: box, hotspot: hot, k: points / body, scale: scale, draw: draw)
        }
        let penBox = CGRect(x: -20, y: -105, width: 125, height: 125)
        switch self {
        case .plain:
            let h = HandArt.make(pointSize: points * 0.82, scale: scale)
            return Sprite(image: h.image, size: h.size, anchor: h.tipAnchor)
        case .cartoonHand, .comicPow:
            return art(CGRect(x: -6, y: -2, width: 72, height: 56), PointerArt.cartoonTip, body: 34) { PointerArt.cartoon($0) }
        case .giraffe:
            let g = PointerArt.giraffe
            return art(CGRect(x: 0, y: 0, width: g.width, height: g.height), PointerArt.giraffeTip, body: 380) {
                PointerArt.drawRaster($0, g)
            }
        case .fountainPen:
            return art(penBox, .zero, body: 85) { PointerArt.fountainPen($0) }
        case .fountainPenBlue:
            return art(penBox, .zero, body: 85) { PointerArt.fountainPen($0, lacquer: PointerArt.royalBlue) }
        case .fountainPenGreen:
            return art(penBox, .zero, body: 85) { PointerArt.fountainPen($0, lacquer: PointerArt.racingGreen) }
        case .magicWand:
            return art(CGRect(x: -20, y: -20, width: 110, height: 110), .zero, body: 78) { PointerArt.magicWand($0) }
        case .foamFinger:
            let tip = CGPoint(x: 0, y: 3).applying(CGAffineTransform(rotationAngle: -0.3))
            return art(CGRect(x: -50, y: -25, width: 170, height: 175), tip, body: 125) { PointerArt.foamFinger($0) }
        case .laserPointer:
            return art(CGRect(x: -20, y: -20, width: 40, height: 40), .zero, body: 70) { PointerArt.laserDot($0) }
        case .catPaw:
            return art(CGRect(x: -60, y: -25, width: 130, height: 135), PointerArt.pawTip, body: 100) { PointerArt.catPaw($0) }
        case .retroPixel:
            return art(CGRect(x: -4, y: -4, width: 104, height: 116), CGPoint(x: 30, y: 3), body: 108) { PointerArt.retroPixel($0) }
        }
    }
}
