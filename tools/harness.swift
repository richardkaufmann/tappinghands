// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
// Test harness: a separate app with a click target. Moves the pointer, posts real clicks,
// captures screenshots, and reports whether the click reached this window (click-through).
import AppKit
let out = CommandLine.arguments[1]
let tag = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "run"
final class V: NSView {
    var downs = 0
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { downs += 1 }
    override func draw(_ r: NSRect) { NSColor(srgbRed: 0.95, green: 0.95, blue: 0.9, alpha: 1).setFill(); r.fill()
        ("Click target – downs: \(downs)" as NSString).draw(at: NSPoint(x: 20, y: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 22)]) }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let screenH = NSScreen.screens[0].frame.height
let win = NSWindow(contentRect: NSRect(x: 1000, y: screenH - 1000, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
let v = V(frame: NSRect(x: 0, y: 0, width: 500, height: 300)); win.contentView = v; win.title = "TapHand test target"
win.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
let original = CGEvent(source: nil)!.location   // top-left origin
func shot(_ name: String, _ c: CGPoint) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-C", "-R", "\(Int(c.x) - 120),\(Int(c.y) - 90),260,200", "\(out)/\(tag)-\(name).png"]
    try? p.run(); p.waitUntilExit()
}
func move(_ c: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap) }
DispatchQueue.global().async {
    Thread.sleep(forTimeInterval: 1.0)
    // 1. follow: glide along a path, snapshot at two points
    let a = CGPoint(x: 1150, y: 750), b = CGPoint(x: 1350, y: 850)
    for i in 0...30 { let t = CGFloat(i) / 30; move(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); Thread.sleep(forTimeInterval: 0.01) }
    Thread.sleep(forTimeInterval: 0.2); shot("move-b", b)
    move(a); Thread.sleep(forTimeInterval: 0.2); shot("move-a", a)
    // 2. left click held ~0.5 s, snapshot while pressed, then after release
    let c = CGPoint(x: 1250, y: 850)
    move(c); Thread.sleep(forTimeInterval: 0.15)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.06); shot("left-pressed", c)
    Thread.sleep(forTimeInterval: 0.2)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.6); shot("released", c)
    // 3. quick tap (down/up 5 ms apart, like trackpad tap-to-click)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.005)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.03); shot("quicktap", c)
    Thread.sleep(forTimeInterval: 0.5)
    DispatchQueue.main.async {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        print("downs_received=\(v.downs) frontmost=\(front) key=\(win.isKeyWindow)")
        move(original)
        exit(0)
    }
}
app.run()
