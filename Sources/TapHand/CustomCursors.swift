// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

/// User-supplied pointers, loaded at runtime and never bundled: every PNG, SVG or PDF in
/// ~/Library/Application Support/TapHand/Cursors becomes a Theme menu entry.
///
/// Optional sidecar `<name>.json` next to the image (all keys optional):
///   { "title": "My Cursor",          // menu title (default: file name)
///     "hotspot": [x, y],             // click point, image units from the top-left (default: opaque pixel nearest the top-left)
///     "size": 54,                    // image units that equal the Size slider (default: image height)
///     "effect": "rings",             // rings, inkSplat, stars, confetti, laserFlash, comicBurst, pawPrint, pixelRipple, lick
///     "tilts": true }                // tilt on press (default true)
/// Image units = pixels for bitmaps, points for SVG/PDF (which stay vector at every size).
enum CustomCursors {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TapHand/Cursors", isDirectory: true)
    static let prefix = "custom:"
    private static let extensions: Set<String> = ["png", "svg", "pdf"]
    private static var cache: [PointerStyle]?

    private struct Config: Decodable {
        var title: String?
        var hotspot: [Double]?
        var size: Double?
        var effect: String?
        var tilts: Bool?
    }

    static func all() -> [PointerStyle] {
        if let cache { return cache }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let styles = urls.filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap(load)
        cache = styles
        return styles
    }

    static func reload() { cache = nil }

    static func style(id: String) -> PointerStyle? { all().first { $0.id == id } }

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private static func load(_ url: URL) -> PointerStyle? {
        guard let img = NSImage(contentsOf: url) else {
            NSLog("TapHand: can't read custom cursor \(url.lastPathComponent)")
            return nil
        }
        let name = url.deletingPathExtension().lastPathComponent
        var cfg = Config()
        let side = url.deletingPathExtension().appendingPathExtension("json")
        if let data = try? Data(contentsOf: side) {
            if let c = try? JSONDecoder().decode(Config.self, from: data) { cfg = c }
            else { NSLog("TapHand: ignoring malformed \(side.lastPathComponent)") }
        }
        // Natural size in image units: pixels for bitmaps, points for vector art.
        let bitmap = img.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
        let units = bitmap.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? img.size
        guard units.width > 0, units.height > 0 else { return nil }
        let hotspot: CGPoint
        if let h = cfg.hotspot, h.count == 2 {
            hotspot = CGPoint(x: h[0], y: h[1])
        } else {
            let probe = makeSprite(box: CGRect(origin: .zero, size: units), hotspot: .zero, k: 1, scale: 1) {
                PointerArt.drawImage($0, img, in: CGRect(origin: .zero, size: units))
            }
            hotspot = PointerArt.rasterTip(probe.image, inset: 2)   // probe is uncropped at 1 px per unit
        }
        let body = CGFloat(cfg.size ?? Double(units.height))
        let effect = cfg.effect.flatMap(EffectKind.init(rawValue:)) ?? .rings
        return PointerStyle(id: prefix + name, title: cfg.title ?? name, effect: effect, tilts: cfg.tilts ?? true,
                            castsShadow: true) { points, scale in
            makeSprite(box: CGRect(origin: .zero, size: units), hotspot: hotspot, k: points / body, scale: scale) {
                PointerArt.drawImage($0, img, in: CGRect(origin: .zero, size: units))
            }
        }
    }
}
