// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import Foundation
import CoreGraphics

enum TapIntensity: String, CaseIterable {
    case subtle, normal, expressive

    var title: String { rawValue.capitalized }
    /// Scale of the hand while pressed (shrinks toward the fingertip, as if pushing "into" the screen).
    var pressScale: CGFloat { switch self { case .subtle: 0.93; case .normal: 0.85; case .expressive: 0.74 } }
    /// Tilt while pressed, in radians, around the fingertip.
    var tilt: CGFloat { switch self { case .subtle: 0.03; case .normal: 0.09; case .expressive: 0.18 } }
    /// Ripple diameter relative to the hand size.
    var rippleScale: CGFloat { switch self { case .subtle: 0.6; case .normal: 1.0; case .expressive: 1.5 } }
    var rippleOpacity: Float { switch self { case .subtle: 0.45; case .normal: 0.7; case .expressive: 0.9 } }
    var pressDuration: CFTimeInterval { switch self { case .subtle: 0.05; case .normal: 0.06; case .expressive: 0.08 } }
    /// Very fast clicks (trackpad tap-to-click) can be a few ms long; keep the press visible at least this long.
    var minimumPress: CFTimeInterval { switch self { case .subtle: 0.07; case .normal: 0.10; case .expressive: 0.13 } }
    var springDamping: CGFloat { switch self { case .subtle: 26; case .normal: 18; case .expressive: 11 } }
}

/// Pointer size range for the menu's Size slider, in points (the pointer's main body).
enum PointerSize {
    static let range: ClosedRange<Double> = 24...128
    static let standard: Double = 48
    /// Old "Hand Size" menu choices, migrated to the slider.
    static let legacy: [String: Double] = ["small": 34, "medium": 48, "large": 66, "extraLarge": 90]
}

/// All state lives in UserDefaults (domain `local.taphand`). Nothing leaves the machine.
final class Settings {
    static let shared = Settings()
    var onChange: (() -> Void)?
    /// Size changes come from a slider while the menu is open; they only re-render the art.
    var onResize: (() -> Void)?
    private let d = UserDefaults.standard

    private func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }

    var enabled: Bool {
        get { bool("enabled", true) }
        set { d.set(newValue, forKey: "enabled"); onChange?() }
    }
    var intensity: TapIntensity {
        get { TapIntensity(rawValue: d.string(forKey: "intensity") ?? "") ?? .normal }
        set { d.set(newValue.rawValue, forKey: "intensity"); onChange?() }
    }
    /// Selected pointer: a Theme raw value or "custom:<file name>" (key kept as "theme" for older settings).
    var pointerID: String {
        get { d.string(forKey: "theme") ?? Theme.plain.rawValue }
        set { d.set(newValue, forKey: "theme"); onChange?() }
    }
    var pointer: PointerStyle { PointerStyle.resolve(pointerID) }
    var pointerSize: Double {
        get {
            if let v = d.object(forKey: "pointerSize") as? Double { return min(max(v, PointerSize.range.lowerBound), PointerSize.range.upperBound) }
            return PointerSize.legacy[d.string(forKey: "handSize") ?? ""] ?? PointerSize.standard
        }
        set { d.set(newValue, forKey: "pointerSize"); onResize?() }
    }
    /// Show taps but stop clicks from reaching apps (public API: a click-catching window).
    var presentationMode: Bool {
        get { bool("presentationMode", false) }
        set { d.set(newValue, forKey: "presentationMode"); onChange?() }
    }
    /// Opt-in: hide the real arrow using a private WindowServer property.
    var hideSystemCursor: Bool {
        get { bool("hideSystemCursor", false) }
        set { d.set(newValue, forKey: "hideSystemCursor"); onChange?() }
    }
}
