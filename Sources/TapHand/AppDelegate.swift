// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayController()
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        settings.onChange = { [weak self] in self?.refresh() }
        settings.onResize = { [weak self] in guard let self else { return }; overlay.updateArt(settings) }
        refresh()
    }

    func applicationWillTerminate(_ n: Notification) { overlay.cursor.setHidden(false) }

    private func refresh() {
        overlay.apply(settings)
        if settings.hideSystemCursor && !overlay.cursor.isHidden && settings.enabled {
            // Private API missing: turn the option back off so the menu tells the truth.
            settings.onChange = nil
            settings.hideSystemCursor = false
            settings.onChange = { [weak self] in self?.refresh() }
        }
        let symbol = settings.enabled ? "hand.point.up.left.fill" : "hand.point.up.left"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "TapHand")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.menu = buildMenu()
    }

    private func item(_ title: String, on: Bool, enabled: Bool = true, _ action: @escaping () -> Void) -> NSMenuItem {
        let i = ClosureMenuItem(title: title, action: action)
        i.state = on ? .on : .off
        i.isEnabled = enabled
        return i
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        m.addItem(item("Show Tapping Hand", on: settings.enabled) { [unowned self] in settings.enabled.toggle() })
        m.addItem(.separator())

        let themes = NSMenu()
        themes.autoenablesItems = false
        let current = settings.pointer
        for t in Theme.allCases {
            themes.addItem(item(t.title, on: current.id == t.rawValue) { [unowned self] in settings.pointerID = t.rawValue })
        }
        themes.addItem(.separator())
        let customs = CustomCursors.all()
        let header = NSMenuItem(title: customs.isEmpty ? "Custom (none yet)" : "Custom", action: nil, keyEquivalent: "")
        header.isEnabled = false
        themes.addItem(header)
        for c in customs {
            themes.addItem(item(c.title, on: current.id == c.id) { [unowned self] in settings.pointerID = c.id })
        }
        themes.addItem(item("Open Custom Cursors Folder…", on: false) {
            CustomCursors.ensureFolder()
            NSWorkspace.shared.open(CustomCursors.folder)
        })
        themes.addItem(item("Reload Custom Cursors", on: false) { [unowned self] in
            CustomCursors.reload()
            refresh()
        })
        let ti = NSMenuItem(title: "Theme: \(current.title)", action: nil, keyEquivalent: "")
        ti.submenu = themes
        m.addItem(ti)

        let intensity = NSMenu()
        intensity.autoenablesItems = false
        for v in TapIntensity.allCases {
            intensity.addItem(item(v.title, on: settings.intensity == v) { [unowned self] in settings.intensity = v })
        }
        let ii = NSMenuItem(title: "Tap Intensity", action: nil, keyEquivalent: "")
        ii.submenu = intensity
        m.addItem(ii)

        let size = NSMenuItem()
        size.view = SliderMenuView(title: "Size", value: settings.pointerSize, range: PointerSize.range) { [unowned self] v in
            settings.pointerSize = v
        }
        m.addItem(size)

        m.addItem(.separator())
        let pres = item("Presentation Mode (clicks don't reach apps)", on: settings.presentationMode,
                        enabled: settings.enabled) { [unowned self] in settings.presentationMode.toggle() }
        pres.toolTip = "Shows the tap but swallows mouse clicks. The menu bar stays clickable so you can turn it off."
        m.addItem(pres)
        let hide = item("Hide System Cursor (private API)", on: settings.hideSystemCursor,
                        enabled: settings.enabled && CursorHider.privateAPIAvailable) { [unowned self] in
            settings.hideSystemCursor.toggle()
        }
        hide.toolTip = "Uses an undocumented macOS setting so only the hand shows. May break in future macOS versions."
        m.addItem(hide)

        m.addItem(.separator())
        m.addItem(item("About TapHand…", on: false) { About.show() })
        let quit = NSMenuItem(title: "Quit TapHand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(quit)
        return m
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// A labelled slider that lives inside a menu; reports values continuously while dragging.
final class SliderMenuView: NSView {
    private let slider: NSSlider
    private let readout = NSTextField(labelWithString: "")
    private let onChange: (Double) -> Void

    init(title: String, value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        readout.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        readout.textColor = .secondaryLabelColor
        readout.alignment = .right
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(changed)
        for v in [label, slider, readout] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            readout.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            readout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            readout.centerYAnchor.constraint(equalTo: centerYAnchor),
            readout.widthAnchor.constraint(equalToConstant: 46),
        ])
        updateReadout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateReadout() { readout.stringValue = "\(Int(slider.doubleValue.rounded())) pt" }
    @objc private func changed() {
        updateReadout()
        onChange(slider.doubleValue.rounded())
    }
}
