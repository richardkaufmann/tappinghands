// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit
import QuartzCore

/// Layer-hosting view for one screen: draws the themed pointer and click effects. Never handles mouse events.
final class HandOverlayView: NSView {
    let root = CALayer()
    let hand = CALayer()
    var intensity: TapIntensity = .normal
    private var style: PointerStyle = Theme.plain.pointerStyle
    private var pointerPoints: CGFloat = 48
    private var clickCount = 0
    private var link: CADisplayLink?
    private var lastLocal = CGPoint(x: -1, y: -1)
    private var lastVisible = false
    private var pressedAt: CFTimeInterval = 0
    private var pressToken = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root
        wantsLayer = true
        root.masksToBounds = false
        hand.shadowColor = NSColor.black.cgColor
        hand.shadowOpacity = 0.45
        hand.shadowRadius = 3
        hand.shadowOffset = CGSize(width: 2, height: -3)
        hand.isHidden = true
        root.addSublayer(hand)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(style: PointerStyle, points: CGFloat, intensity: TapIntensity, scale: CGFloat) {
        self.intensity = intensity
        self.style = style
        pointerPoints = points
        let art = style.sprite(points, scale)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hand.contents = art.image
        hand.contentsScale = scale
        hand.bounds = CGRect(origin: .zero, size: art.size)
        hand.anchorPoint = art.anchor
        hand.shadowOpacity = style.castsShadow ? 0.45 : 0
        root.contentsScale = scale
        CATransaction.commit()
    }

    // MARK: following the pointer (polled once per display refresh; needs no permission)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)   // keep running while menus are tracking
        link = l
        tick()
    }

    func stop() { link?.invalidate(); link = nil }

    @objc private func tick() {
        guard let frame = window?.frame else { return }
        let p = NSEvent.mouseLocation
        let visible = p.x >= frame.minX && p.x <= frame.maxX && p.y >= frame.minY && p.y <= frame.maxY
        let local = CGPoint(x: p.x - frame.minX, y: p.y - frame.minY)
        if local == lastLocal && visible == lastVisible { return }
        lastLocal = local; lastVisible = visible
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hand.position = local
        hand.isHidden = !visible
        CATransaction.commit()
    }

    func moveHand(toLocal p: CGPoint) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hand.position = p; hand.isHidden = false
        CATransaction.commit()
    }

    // MARK: tapping

    func press(globalPoint p: CGPoint, right: Bool) {
        pressedAt = CACurrentMediaTime()
        pressToken += 1
        setPressed(true, animated: true)
        guard let frame = window?.frame, frame.contains(p) || frame.maxY == p.y || frame.maxX == p.x else { return }
        effect(atLocal: CGPoint(x: p.x - frame.minX, y: p.y - frame.minY), right: right)
    }

    func release() {
        let token = pressToken
        let wait = max(0, intensity.minimumPress - (CACurrentMediaTime() - pressedAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.pressToken == token else { return }   // a newer press is in progress
            self.setPressed(false, animated: true)
        }
    }

    func setPressed(_ pressed: Bool, animated: Bool) {
        let s: CGFloat = pressed ? intensity.pressScale : 1
        let r: CGFloat = pressed && style.tilts ? intensity.tilt : 0
        let pres = hand.presentation()
        let fromS = (pres?.value(forKeyPath: "transform.scale.x") as? CGFloat) ?? (pressed ? 1 : s)
        let fromR = (pres?.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
        let fromShadow = pres?.shadowOffset ?? hand.shadowOffset
        let fromRadius = pres?.shadowRadius ?? hand.shadowRadius
        let shadow = pressed ? CGSize(width: 0.5, height: -0.5) : CGSize(width: 2, height: -3)
        let radius: CGFloat = pressed ? 1 : 3

        CATransaction.begin(); CATransaction.setDisableActions(true)
        hand.transform = CATransform3DRotate(CATransform3DMakeScale(s, s, 1), r, 0, 0, 1)
        hand.shadowOffset = shadow
        hand.shadowRadius = radius
        CATransaction.commit()
        guard animated else { hand.removeAllAnimations(); return }

        func anim(_ key: String, _ from: Any, _ to: Any) -> CABasicAnimation {
            let a: CABasicAnimation
            if pressed {
                a = CABasicAnimation(keyPath: key)
                a.duration = intensity.pressDuration
                a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            } else {
                let sp = CASpringAnimation(keyPath: key)
                sp.mass = 1; sp.stiffness = 500; sp.damping = intensity.springDamping
                sp.duration = sp.settlingDuration
                a = sp
            }
            a.fromValue = from; a.toValue = to
            return a
        }
        hand.add(anim("transform.scale.x", fromS, s), forKey: "sx")
        hand.add(anim("transform.scale.y", fromS, s), forKey: "sy")
        hand.add(anim("transform.rotation.z", fromR, r), forKey: "rot")
        hand.add(anim("shadowOffset", NSValue(size: fromShadow), NSValue(size: shadow)), forKey: "shOff")
        hand.add(anim("shadowRadius", fromRadius, radius), forKey: "shRad")
    }

    func effect(atLocal p: CGPoint, right: Bool, frozenAt progress: CGFloat? = nil) {
        clickCount += 1
        let R = pointerPoints * 0.55 * intensity.rippleScale
        // The mouth moves with the pressed pose: scaled and tilted about the hotspot like the art.
        var mouth = CGPoint.zero
        if let m = style.mouth?(pointerPoints) {
            let s = intensity.pressScale, r = style.tilts ? intensity.tilt : 0
            mouth = CGPoint(x: s * (m.x * cos(r) - m.y * sin(r)), y: s * (m.x * sin(r) + m.y * cos(r)))
        }
        style.effect.make(R: R, right: right, scale: root.contentsScale, opacity: intensity.rippleOpacity, seq: clickCount,
                          mouth: mouth)
            .play(in: root, below: hand, at: p, scale: root.contentsScale, frozenAt: progress)
    }
}

/// Swallows mouse clicks in Presentation mode. Sits below the menu bar so the menu bar
/// (and TapHand's own menu) stays clickable.
final class ClickCatcherView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
}
