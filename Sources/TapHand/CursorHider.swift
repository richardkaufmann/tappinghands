// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

/// OPTIONAL, OFF BY DEFAULT. macOS only lets the frontmost app hide the cursor. A menu bar app is
/// never frontmost, so CGDisplayHideCursor alone does nothing. The widely used workaround sets the
/// undocumented WindowServer connection property "SetsCursorInBackground". This is private API:
/// it may stop working in any macOS update and would get the app rejected from the App Store.
/// Symbols are looked up at runtime with dlsym, so if Apple removes them the app still launches and
/// simply leaves the cursor visible. If TapHand quits or crashes, WindowServer drops the hide with
/// the connection, so the cursor cannot stay stuck hidden.
final class CursorHider {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private(set) var isHidden = false
    /// CGDisplayHideCursor is reference-counted; remember how many hides we issued.
    private var hideCount = 0
    private var activationObserver: Any?

    static var privateAPIAvailable: Bool { symbols() != nil }

    private static func symbols() -> (DefaultConnection, SetConnectionProperty)? {
        guard let h = dlopen(nil, RTLD_NOW),
              let a = dlsym(h, "_CGSDefaultConnection"),
              let b = dlsym(h, "CGSSetConnectionProperty") else { return nil }
        return (unsafeBitCast(a, to: DefaultConnection.self), unsafeBitCast(b, to: SetConnectionProperty.self))
    }

    private func hideOnce() {
        CGDisplayHideCursor(CGMainDisplayID())
        hideCount += 1
    }

    /// Returns false if hiding was requested but the private API is unavailable.
    @discardableResult
    func setHidden(_ hide: Bool) -> Bool {
        if hide == isHidden { return true }
        if hide {
            guard let (conn, set) = Self.symbols() else { return false }
            let cid = conn()
            _ = set(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
            hideOnce()
            isHidden = true
            // Another app becoming frontmost resets the cursor to visible, so hide again whenever
            // the active app changes.
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                    guard let self, self.isHidden else { return }
                    self.hideOnce()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if self.isHidden { self.hideOnce() } }
                }
        } else {
            if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
            activationObserver = nil
            for _ in 0..<max(hideCount, 1) { CGDisplayShowCursor(CGMainDisplayID()) }
            hideCount = 0
            isHidden = false
        }
        return true
    }
}
