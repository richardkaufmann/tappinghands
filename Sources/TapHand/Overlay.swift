// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

/// Borderless, transparent, non-activating panel that joins every Space, including full-screen apps.
final class OverlayPanel: NSPanel {
    init(frame: NSRect, level: NSWindow.Level, clickThrough: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = clickThrough ? .clear : NSColor(white: 0, alpha: 0.001)
        hasShadow = false
        ignoresMouseEvents = clickThrough
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        setFrame(frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Watches mouse buttons only (left/right down/up). No keyboard, no movement events.
/// Global monitors for mouse-button events do not require Accessibility or Input Monitoring.
final class ClickMonitor {
    var onDown: ((Bool) -> Void)?
    var onUp: (() -> Void)?
    private var global: Any?
    private var local: Any?

    func start() {
        guard global == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e) }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e); return e }
    }

    func stop() {
        if let g = global { NSEvent.removeMonitor(g) }
        if let l = local { NSEvent.removeMonitor(l) }
        global = nil; local = nil
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown: onDown?(false)
        case .rightMouseDown: onDown?(true)
        default: onUp?()
        }
    }
}

final class OverlayController {
    private var handPanels: [OverlayPanel] = []
    private var handViews: [HandOverlayView] = []
    private var catchers: [OverlayPanel] = []
    private let clicks = ClickMonitor()
    let cursor = CursorHider()

    /// Above menus, the Dock and full-screen apps; below the real cursor.
    static let handLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
    /// Above normal and full-screen app windows and the Dock, but below the menu bar, so the
    /// menu bar (and TapHand's own menu) still works while Presentation mode swallows clicks.
    static let catcherLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)

    init() {
        clicks.onDown = { [weak self] right in
            let p = NSEvent.mouseLocation
            self?.handViews.forEach { $0.press(globalPoint: p, right: right) }
        }
        clicks.onUp = { [weak self] in self?.handViews.forEach { $0.release() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.apply(Settings.shared)
        }
    }

    func apply(_ s: Settings) {
        tearDown()
        guard s.enabled else {
            clicks.stop()
            cursor.setHidden(false)
            return
        }
        for screen in NSScreen.screens {
            let panel = OverlayPanel(frame: screen.frame, level: Self.handLevel, clickThrough: true)
            let view = HandOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.configure(style: s.pointer, points: CGFloat(s.pointerSize), intensity: s.intensity,
                           scale: screen.backingScaleFactor)
            panel.contentView = view
            panel.orderFrontRegardless()
            handPanels.append(panel); handViews.append(view)

            if s.presentationMode {
                let catcher = OverlayPanel(frame: screen.frame, level: Self.catcherLevel, clickThrough: false)
                catcher.contentView = ClickCatcherView(frame: NSRect(origin: .zero, size: screen.frame.size))
                catcher.orderFrontRegardless()
                catchers.append(catcher)
            }
        }
        clicks.start()
        if s.hideSystemCursor, !cursor.setHidden(true) {
            NSLog("TapHand: private cursor-hiding API unavailable; leaving the system cursor visible")
        } else if !s.hideSystemCursor {
            cursor.setHidden(false)
        }
    }

    /// Re-render the pointer art in place (Size slider); no window churn while the menu is open.
    func updateArt(_ s: Settings) {
        for (panel, view) in zip(handPanels, handViews) {
            view.configure(style: s.pointer, points: CGFloat(s.pointerSize), intensity: s.intensity,
                           scale: panel.screen?.backingScaleFactor ?? 2)
        }
    }

    private func tearDown() {
        handViews.forEach { $0.stop() }
        (handPanels + catchers).forEach { $0.orderOut(nil); $0.close() }
        handPanels = []; handViews = []; catchers = []
    }
}
