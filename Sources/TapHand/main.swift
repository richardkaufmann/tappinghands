// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-frames"), i + 1 < args.count {
    FrameRenderer.run(outDir: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--render-about"), i + 1 < args.count {
    // Offscreen check of the About box's "Meet Eddie" text (bold/italics/link styling).
    let v = About.eddieView()
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    exit(0)
}
if let i = args.firstIndex(of: "--render-demo"), i + 1 < args.count {
    FrameRenderer.runDemoFrames(outDir: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
    FrameRenderer.runIcon(outDir: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--render-themes"), i + 1 < args.count {
    FrameRenderer.runThemes(outDir: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, never steals focus
app.run()
