// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit
import QuartzCore

/// One moving piece of a click effect. Its look over time is a pure function of progress t (0...1),
/// so the live animation (sampled into keyframes) and the still frames for --render-themes match exactly.
struct Particle {
    struct State {
        var offset = CGPoint.zero      // points, y UP (layer space), from the click point
        var scale: CGFloat = 1
        var rotation: CGFloat = 0
        var opacity: Float = 1
        var stretch: CGFloat = 1       // extra scale along the image's own x axis (applied before rotation)

        var transform: CATransform3D {
            CATransform3DConcat(CATransform3DMakeScale(scale * stretch, scale, 1), CATransform3DMakeRotation(rotation, 0, 0, 1))
        }
    }
    let image: CGImage
    let size: CGSize                  // points
    let at: (CGFloat) -> State
}

struct Effect {
    let duration: CFTimeInterval
    let particles: [Particle]
    var aboveHand = false             // drawn in front of the pointer (e.g. Eddie's tongue leaving his mouth)
}

enum EffectKind: String, CaseIterable {
    case rings, inkSplat, stars, confetti, laserFlash, comicBurst, pawPrint, pixelRipple, lick

    /// Effect progress used for the still "click" frame in --render-themes.
    var previewT: CGFloat {
        switch self {
        case .rings: 0.5
        case .inkSplat: 0.3
        case .stars: 0.45
        case .confetti: 0.35
        case .laserFlash: 0.3
        case .comicBurst: 0.35
        case .pawPrint: 0.3
        case .pixelRipple: 0.5
        case .lick: 0.35
        }
    }
}

private func clamp(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
/// Progress through the [a, b] slice of t.
private func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { clamp((t - a) / (b - a)) }
private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
private func easeOutBack(_ t: CGFloat) -> CGFloat {
    let c1: CGFloat = 1.9, c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}

/// Draws a picture of `size` points in a y-down context.
private func picture(_ size: CGSize, _ scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
    let pw = max(1, Int(ceil(size.width * scale))), ph = max(1, Int(ceil(size.height * scale)))
    let c = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                      space: Draw.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(ph)); c.scaleBy(x: scale, y: -scale)
    c.setLineJoin(.round); c.setLineCap(.round)
    draw(c)
    return c.makeImage()!
}

extension EffectKind {
    /// `R` = effect radius in points, `seq` = click counter (varies POW words, splat shapes, paw angle).
    /// `mouth` = where the pointer's mouth is, relative to the click point (layer space, points); only `lick` uses it.
    func make(R: CGFloat, right: Bool, scale: CGFloat, opacity: Float, seq: Int, mouth: CGPoint = .zero) -> Effect {
        switch self {
        case .rings: return rings(R, right, scale, opacity)
        case .inkSplat: return inkSplat(R, right, scale, opacity, seq)
        case .stars: return stars(R, right, scale, seq)
        case .confetti: return confetti(R, right, scale, seq)
        case .laserFlash: return laserFlash(R, right, scale, opacity)
        case .comicBurst: return powBurst(R, right, scale, seq)
        case .pawPrint: return pawPrint(R, right, scale, opacity, seq)
        case .pixelRipple: return pixelRipple(R, right, scale)
        case .lick: return right ? hearts(R, scale, seq) : lick(R, scale, seq, mouth: mouth)
        }
    }

    // Blue ring (left) / orange double ring (right): the original TapHand ripple.
    private func rings(_ R: CGFloat, _ right: Bool, _ scale: CGFloat, _ op: Float) -> Effect {
        let col = right ? rgb(0xFF8C1A) : rgb(0x338CFF)
        let d = 2 * R
        let img = picture(CGSize(width: d, height: d), scale) { c in
            let p = Draw.circle(CGPoint(x: R, y: R), R - 2)
            Draw.fill(c, p, col.copy(alpha: 0.22)!)
            Draw.stroke(c, p, col, 3)
        }
        let delays: [CGFloat] = right ? [0, 0.2] : [0]
        return Effect(duration: right ? 0.52 : 0.42, particles: delays.map { delay in
            Particle(image: img, size: CGSize(width: d, height: d)) { t in
                let u = seg(t, delay, delay + (right ? 0.8 : 1))
                return .init(scale: 0.2 + 0.8 * easeOut(u), opacity: t < delay ? 0 : op * Float(1 - u))
            }
        })
    }

    private func inkSplat(_ R: CGFloat, _ right: Bool, _ scale: CGFloat, _ op: Float, _ seq: Int) -> Effect {
        let col = right ? rgb(0xA3122A) : rgb(0x1B2F7A)
        let S = 1.7 * R
        var rng = RNG(UInt64(seq + 7))
        let img = picture(CGSize(width: S, height: S), scale) { c in
            let m = CGPoint(x: S / 2, y: S / 2)
            Draw.fill(c, Draw.circle(m, S * 0.26), col)
            for i in 0..<9 {
                let a = CGFloat(i) / 9 * 2 * .pi + rng.range(-0.25, 0.25)
                let d = S * rng.range(0.2, 0.3)
                Draw.fill(c, Draw.circle(CGPoint(x: m.x + d * cos(a), y: m.y + d * sin(a)), S * rng.range(0.07, 0.12)), col)
            }
            for _ in 0..<7 {
                let a = rng.range(0, 2 * .pi), d = S * rng.range(0.36, 0.47)
                Draw.fill(c, Draw.circle(CGPoint(x: m.x + d * cos(a), y: m.y + d * sin(a)), S * rng.range(0.018, 0.04)), col)
            }
            Draw.fill(c, Draw.ellipse(CGPoint(x: m.x - S * 0.08, y: m.y - S * 0.09), S * 0.12, S * 0.07, angle: -0.5),
                      rgb(0xFFFFFF, 0.35))
        }
        return Effect(duration: 0.85, particles: [
            Particle(image: img, size: CGSize(width: S, height: S)) { t in
                .init(scale: 0.25 + 0.75 * easeOutBack(seg(t, 0, 0.22)), rotation: CGFloat(seq % 5) * 0.7,
                      opacity: op * Float(1 - seg(t, 0.45, 1)))
            },
        ])
    }

    private func stars(_ R: CGFloat, _ right: Bool, _ scale: CGFloat, _ seq: Int) -> Effect {
        let palette = right ? [rgb(0xFF5FD2), rgb(0x7DF9FF), rgb(0xFFFFFF)] : [rgb(0xFFD23F), rgb(0xFFFFFF), rgb(0xFFF09A)]
        let s = 0.42 * R
        let glow = picture(CGSize(width: R, height: R), scale) { c in
            Draw.radial(c, nil, [palette[1].copy(alpha: 0.95)!, palette[0].copy(alpha: 0)!],
                        center: CGPoint(x: R / 2, y: R / 2), radius: R / 2)
        }
        var parts = [Particle(image: glow, size: CGSize(width: R, height: R)) { t in
            .init(scale: 0.5 + 0.8 * easeOut(t), opacity: Float(pow(1 - t, 2)))
        }]
        var rng = RNG(UInt64(seq + 3))
        let n = 8
        for i in 0..<n {
            let col = palette[i % palette.count]
            let img = picture(CGSize(width: s, height: s), scale) { c in
                let p = Draw.star(CGPoint(x: s / 2, y: s / 2), outer: s / 2 - 1, inner: s * 0.2, points: 5)
                Draw.fill(c, p, col)
                Draw.stroke(c, p, rgb(0x6A4A00, 0.6), max(0.8, s * 0.04))
            }
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi + rng.range(-0.2, 0.2)
            let dist = R * rng.range(0.85, 1.25)
            let spin: CGFloat = i.isMultiple(of: 2) ? 2.5 : -2.5
            parts.append(Particle(image: img, size: CGSize(width: s, height: s)) { t in
                let e = easeOut(t)
                return .init(offset: CGPoint(x: dist * e * cos(a), y: dist * e * sin(a)), scale: 1.1 - 0.6 * t,
                             rotation: spin * t, opacity: Float(1 - seg(t, 0.5, 1)))
            })
        }
        return Effect(duration: 0.6, particles: parts)
    }

    private func confetti(_ R: CGFloat, _ right: Bool, _ scale: CGFloat, _ seq: Int) -> Effect {
        let palette = right
            ? [rgb(0xFFD700), rgb(0xE6E6EE), rgb(0xFFB000), rgb(0xFFFFFF)]
            : [rgb(0xFF3B5C), rgb(0xFFD23F), rgb(0x2ED47A), rgb(0x2E8BFF), rgb(0xB45CFF), rgb(0xFF8A1F)]
        var rng = RNG(UInt64(seq + 11))
        let w = 0.13 * R, h = 0.22 * R
        let parts: [Particle] = (0..<16).map { i in
            let col = palette[i % palette.count]
            let img = picture(CGSize(width: w, height: h), scale) { c in
                Draw.fill(c, Draw.rrect(CGRect(x: 0, y: 0, width: w, height: h), w * 0.2), col)
            }
            let a = .pi / 2 + rng.range(-1.25, 1.25)         // mostly upward (layer space is y-up)
            let v = R * rng.range(1.5, 2.6)
            let spin = rng.range(-9, 9)
            let g = R * 3.2
            return Particle(image: img, size: CGSize(width: w, height: h)) { t in
                .init(offset: CGPoint(x: v * cos(a) * t, y: v * sin(a) * t - g * t * t), scale: 1,
                      rotation: spin * t, opacity: Float(1 - seg(t, 0.65, 1)))
            }
        }
        return Effect(duration: 0.95, particles: parts)
    }

    private func laserFlash(_ R: CGFloat, _ right: Bool, _ scale: CGFloat, _ op: Float) -> Effect {
        let col = right ? rgb(0x39FF6A) : rgb(0xFF2A2A)
        let g = 1.3 * R
        let glow = picture(CGSize(width: g, height: g), scale) { c in
            Draw.radial(c, nil, [rgb(0xFFFFFF), col.copy(alpha: 0.85)!, col.copy(alpha: 0)!],
                        center: CGPoint(x: g / 2, y: g / 2), radius: g / 2, [0, 0.25, 1])
        }
        let d = 2 * R
        let ring = picture(CGSize(width: d, height: d), scale) { c in
            Draw.stroke(c, Draw.circle(CGPoint(x: R, y: R), R - 2), col, 2.5)
        }
        return Effect(duration: 0.36, particles: [
            Particle(image: glow, size: CGSize(width: g, height: g)) { t in
                .init(scale: 0.4 + 0.8 * easeOut(t), opacity: op * Float(pow(1 - t, 1.5)))
            },
            Particle(image: ring, size: CGSize(width: d, height: d)) { t in
                .init(scale: 0.25 + 0.75 * easeOut(t), opacity: op * Float(1 - t))
            },
        ])
    }

    static let powWords = ["POW!", "BAM!", "ZAP!", "BOOP!", "CLICK!", "WHAM!"]
    static let powWordsRight = ["KA-CHUNK!", "ZOK!", "SPLAT!", "KAPOW!"]

    private func powBurst(_ R: CGFloat, _ right: Bool, _ scale: CGFloat, _ seq: Int) -> Effect {
        let words = right ? Self.powWordsRight : Self.powWords
        let word = words[seq % words.count]
        let S = 2.3 * R
        let fill = right ? rgb(0x29D3FF) : rgb(0xFFE11A)
        let edge = right ? rgb(0x1440C8) : rgb(0xE3261B)
        let img = picture(CGSize(width: S, height: S), scale) { c in
            let m = CGPoint(x: S / 2, y: S / 2)
            let burst = Draw.star(m, outer: S * 0.48, inner: S * 0.32, points: 13, jitter: 0.18, seed: UInt64(seq + 1))
            Draw.fill(c, burst, fill)
            Draw.stroke(c, burst, edge, max(1.5, S * 0.03))
            Draw.fill(c, Draw.star(m, outer: S * 0.33, inner: S * 0.24, points: 13, jitter: 0.12, seed: UInt64(seq + 5)),
                      rgb(0xFFFFFF, 0.45))
            Draw.text(c, word, center: m, size: S * 0.24, fill: right ? rgb(0xFFFFFF) : edge,
                      stroke: rgb(0x111111), strokeWidth: max(1.5, S * 0.035), maxWidth: S * 0.62)
        }
        let tilt: CGFloat = seq.isMultiple(of: 2) ? 0.14 : -0.1
        return Effect(duration: 0.8, particles: [
            Particle(image: img, size: CGSize(width: S, height: S)) { t in
                let s: CGFloat = t < 0.16 ? 0.3 + 0.95 * (t / 0.16) : (t < 0.28 ? 1.25 - 0.25 * seg(t, 0.16, 0.28) : 1)
                return .init(offset: CGPoint(x: R * 0.55, y: R * 0.55), scale: s, rotation: tilt,
                             opacity: Float(1 - seg(t, 0.62, 1)))
            },
        ])
    }

    private func pawPrint(_ R: CGFloat, _ right: Bool, _ scale: CGFloat, _ op: Float, _ seq: Int) -> Effect {
        let col = right ? rgb(0x5B3A29, 0.85) : rgb(0xE0708C, 0.85)
        let S = 1.2 * R
        let img = picture(CGSize(width: S, height: S), scale) { c in
            let u = S / 100
            c.scaleBy(x: u, y: u)
            for p in [Draw.circle(CGPoint(x: 39, y: 66), 15), Draw.circle(CGPoint(x: 61, y: 66), 15),
                      Draw.circle(CGPoint(x: 50, y: 58), 15), Draw.ellipse(CGPoint(x: 50, y: 74), 52, 24)] {
                Draw.fill(c, p, col)
            }
            for (i, t) in [CGPoint(x: 22, y: 38), CGPoint(x: 39, y: 22), CGPoint(x: 61, y: 22), CGPoint(x: 78, y: 38)].enumerated() {
                Draw.fill(c, Draw.ellipse(t, 16, 21, angle: [-0.4, -0.12, 0.12, 0.4][i]), col)
            }
        }
        let rot = CGFloat((seq * 37) % 50 - 25) / 100
        return Effect(duration: 1.1, particles: [
            Particle(image: img, size: CGSize(width: S, height: S)) { t in
                let s: CGFloat = t < 0.08 ? 1.35 - 0.35 * (t / 0.08) : 1
                let o: CGFloat = t < 0.08 ? t / 0.08 : 1 - seg(t, 0.35, 1)
                return .init(scale: s, rotation: rot, opacity: op * Float(o))
            },
        ])
    }

    static let tonguePink = [rgb(0xF7B6CF), rgb(0xE98AB0), rgb(0xC9668F)]

    /// Eddie's left click: a pink tongue shoots out of his mouth, past the click point, and snaps back,
    /// flicking off a couple of droplets. Reach = half the old lick swoosh.
    private func lick(_ R: CGFloat, _ scale: CGFloat, _ seq: Int, mouth: CGPoint) -> Effect {
        let L = 1.1 * R                        // full reach from the lips
        let W = 0.2 * L
        let H = W * 1.3
        // Image: tongue along +x from the image centre (its root), so stretching about the centre grows it from the mouth.
        let tongue = picture(CGSize(width: 2 * L, height: H), scale) { c in
            let cy = H / 2, x0 = L, tipX = 2 * L - W * 0.5 - 1
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x0, y: cy - W * 0.3))
            path.addCurve(to: CGPoint(x: tipX, y: cy - W * 0.5),
                          control1: CGPoint(x: x0 + L * 0.35, y: cy - W * 0.42), control2: CGPoint(x: x0 + L * 0.7, y: cy - W * 0.52))
            path.addArc(center: CGPoint(x: tipX, y: cy), radius: W * 0.5, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            path.addCurve(to: CGPoint(x: x0, y: cy + W * 0.3),
                          control1: CGPoint(x: x0 + L * 0.7, y: cy + W * 0.52), control2: CGPoint(x: x0 + L * 0.35, y: cy + W * 0.42))
            path.closeSubpath()
            Draw.fill(c, path, Self.tonguePink, CGPoint(x: 0, y: cy - W * 0.5), CGPoint(x: 0, y: cy + W * 0.5), [0, 0.5, 1])
            Draw.stroke(c, path, rgb(0x9E4A6E, 0.6), max(0.7, W * 0.06))
            Draw.stroke(c, Draw.curve(CGPoint(x: x0 + W * 0.4, y: cy), CGPoint(x: x0 + L * 0.5, y: cy + W * 0.04),
                                      CGPoint(x: tipX - W * 0.4, y: cy)), rgb(0xB84E78, 0.5), max(0.5, W * 0.07))
            Draw.stroke(c, Draw.curve(CGPoint(x: x0 + L * 0.3, y: cy - W * 0.24), CGPoint(x: x0 + L * 0.55, y: cy - W * 0.32),
                                      CGPoint(x: x0 + L * 0.8, y: cy - W * 0.26)), rgb(0xFFFFFF, 0.6), max(0.5, W * 0.07))
        }
        // Out along his own tongue (mouth -> click point), curling up a touch.
        let dir = atan2(-mouth.y, -mouth.x) - 0.1
        func reach(_ t: CGFloat) -> CGFloat {
            if t < 0.28 { return max(0.02, easeOutBack(t / 0.28)) }
            if t < 0.55 { return 1 }
            return max(0.02, 1 - easeOut(seg(t, 0.55, 0.88)))
        }
        var parts = [Particle(image: tongue, size: CGSize(width: 2 * L, height: H)) { t in
            .init(offset: mouth, rotation: dir + 0.08 * sin(t * 18) * reach(t), opacity: t > 0.9 ? 0 : 1, stretch: reach(t))
        }]
        var rng = RNG(UInt64(seq + 21))
        let d = 0.09 * R
        let tip = CGPoint(x: mouth.x + L * cos(dir), y: mouth.y + L * sin(dir))
        for _ in 0..<3 {
            let drop = picture(CGSize(width: d, height: d), scale) { c in
                Draw.fill(c, Draw.circle(CGPoint(x: d / 2, y: d / 2), d / 2 - 0.3), rgb(0xE98AB0, 0.9))
                Draw.fill(c, Draw.circle(CGPoint(x: d * 0.38, y: d * 0.36), d * 0.14), rgb(0xFFFFFF, 0.8))
            }
            let a = dir + rng.range(-0.6, 0.6), v = R * rng.range(0.4, 0.7)
            parts.append(Particle(image: drop, size: CGSize(width: d, height: d)) { t in
                let u = seg(t, 0.25, 0.85)
                return .init(offset: CGPoint(x: tip.x + v * cos(a) * u, y: tip.y + v * sin(a) * u - R * 0.6 * u * u),
                             opacity: t < 0.25 ? 0 : Float(1 - u))
            })
        }
        return Effect(duration: 0.75, particles: parts, aboveHand: true)
    }

    /// Giraffe right click: three pink hearts float up.
    private func hearts(_ R: CGFloat, _ scale: CGFloat, _ seq: Int) -> Effect {
        var rng = RNG(UInt64(seq + 31))
        let parts: [Particle] = (0..<3).map { i in
            let s = R * rng.range(0.4, 0.55)
            let img = picture(CGSize(width: s, height: s), scale) { c in
                let shapes = [Draw.circle(CGPoint(x: s * 0.3, y: s * 0.36), s * 0.22),
                              Draw.circle(CGPoint(x: s * 0.7, y: s * 0.36), s * 0.22),
                              Draw.poly([CGPoint(x: s * 0.1, y: s * 0.45), CGPoint(x: s * 0.9, y: s * 0.45),
                                         CGPoint(x: s * 0.5, y: s * 0.9)])]
                for p in shapes { Draw.stroke(c, p, rgb(0x9E2E5E), max(1.5, s * 0.08)) }
                for p in shapes { Draw.fill(c, p, [rgb(0xFF9EC4), rgb(0xF0508A)], CGPoint(x: 0, y: 0), CGPoint(x: 0, y: s)) }
                Draw.fill(c, Draw.ellipse(CGPoint(x: s * 0.3, y: s * 0.3), s * 0.14, s * 0.09, angle: -0.5), rgb(0xFFFFFF, 0.7))
            }
            let delay = CGFloat(i) * 0.15, dx = R * CGFloat(i - 1) * 0.55, sway = rng.range(0.15, 0.3) * R
            return Particle(image: img, size: CGSize(width: s, height: s)) { t in
                let u = seg(t, delay, delay + 0.7)
                return .init(offset: CGPoint(x: dx + sway * sin(u * 2 * .pi), y: R * 0.2 + R * 1.3 * u),
                             scale: 0.5 + 0.6 * easeOutBack(min(1, u * 3)), rotation: 0.25 * sin(u * 3 * .pi),
                             opacity: t < delay ? 0 : Float(1 - seg(u, 0.6, 1)))
            }
        }
        return Effect(duration: 1.0, particles: parts)
    }

    private func pixelRipple(_ R: CGFloat, _ right: Bool, _ scale: CGFloat) -> Effect {
        let col = right ? rgb(0xFF3EA5) : rgb(0xFFD400)
        let th = max(2, (R * 0.1).rounded())
        let parts: [Particle] = (0..<4).map { i in
            let d = (2 * R * CGFloat(i + 1) / 4).rounded()
            let img = picture(CGSize(width: d, height: d), scale) { c in
                c.setShouldAntialias(false)
                c.setFillColor(rgb(0x000000, 0.6))
                c.fill(CGRect(x: 0, y: 0, width: d, height: d).insetBy(dx: th * 0.5, dy: th * 0.5))
                c.setBlendMode(.clear)
                c.fill(CGRect(x: 0, y: 0, width: d, height: d).insetBy(dx: th * 1.5, dy: th * 1.5))
                c.setBlendMode(.normal)
                c.setFillColor(col)
                c.fill(CGRect(x: 0, y: 0, width: d, height: th))
                c.fill(CGRect(x: 0, y: d - th, width: d, height: th))
                c.fill(CGRect(x: 0, y: 0, width: th, height: d))
                c.fill(CGRect(x: d - th, y: 0, width: th, height: d))
            }
            let start = CGFloat(i) * 0.2
            return Particle(image: img, size: CGSize(width: d, height: d)) { t in
                let on = t >= start && t < start + 0.32
                return .init(opacity: on ? Float(1 - 0.5 * seg(t, start, start + 0.32)) : 0)
            }
        }
        return Effect(duration: 0.5, particles: parts)
    }
}

extension Effect {
    /// Adds the effect's layers under `below` at `p` (layer space). With `frozenAt`, renders a still frame.
    func play(in root: CALayer, below: CALayer, at p: CGPoint, scale: CGFloat, frozenAt: CGFloat? = nil) {
        for part in particles {
            let l = CALayer()
            l.contents = part.image
            l.contentsScale = scale
            l.bounds = CGRect(origin: .zero, size: part.size)
            func apply(_ s: Particle.State) {
                l.position = CGPoint(x: p.x + s.offset.x, y: p.y + s.offset.y)
                l.transform = s.transform
                l.opacity = s.opacity
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            apply(part.at(frozenAt ?? 1))
            if aboveHand { root.insertSublayer(l, above: below) } else { root.insertSublayer(l, below: below) }
            CATransaction.commit()
            if frozenAt != nil { continue }

            let n = 30
            let times = (0...n).map { CGFloat($0) / CGFloat(n) }
            let states = times.map(part.at)
            func kf(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
                let a = CAKeyframeAnimation(keyPath: key)
                a.values = values; a.keyTimes = times.map { NSNumber(value: Double($0)) }
                return a
            }
            let g = CAAnimationGroup()
            g.animations = [
                kf("position", states.map { NSValue(point: CGPoint(x: p.x + $0.offset.x, y: p.y + $0.offset.y)) }),
                kf("transform", states.map {
                    NSValue(caTransform3D: $0.transform)
                }),
                kf("opacity", states.map { NSNumber(value: $0.opacity) }),
            ]
            g.duration = duration
            CATransaction.begin()
            CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
            l.add(g, forKey: "effect")
            CATransaction.commit()
        }
    }
}
