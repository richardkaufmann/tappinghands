// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import AppKit

/// "About TapHand…": app blurb plus Eddie the Giraffe's story (same text as the README's "Meet Eddie" section).
enum About {
    static let fundraiseURL = URL(string: "https://www.giraffecentre.org/fundraise/")!
    static let readmeURL = URL(string: "https://github.com/richardkaufmann/tappinghands#readme")!

    static let eddieMarkdown = """
        Eddie is a **Rothschild’s giraffe** (*Giraffa camelopardalis rothschildi*, also classified under the northern giraffe). \
        He is well-known at the Nairobi Giraffe Centre (run by the African Fund for Endangered Wildlife) as a prominent member \
        of their breeding herd.

        To support the center's conservation and education programs, you can direct contributions through the \
        [Giraffe Centre Fundraise Page](https://www.giraffecentre.org/fundraise/), which outlines direct bank transfer details, \
        M-Pesa channels, and ways to sponsor local school conservation trips.
        """

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Markdown (bold, italics, links) -> AppKit attributed text in the system font.
    static func styled(_ markdown: String, size: CGFloat = NSFont.systemFontSize) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: size)
        let parsed = (try? NSAttributedString(markdown: markdown,
                                              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? NSAttributedString(string: markdown)
        let out = NSMutableAttributedString(attributedString: parsed)
        let all = NSRange(location: 0, length: out.length)
        out.addAttributes([.font: base, .foregroundColor: NSColor.labelColor], range: all)
        out.enumerateAttribute(.inlinePresentationIntent, in: all) { value, range, _ in
            guard let raw = (value as? NSNumber)?.uintValue else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if !traits.isEmpty {
                let d = base.fontDescriptor.withSymbolicTraits(traits)
                out.addAttribute(.font, value: NSFont(descriptor: d, size: size) ?? base, range: range)
            }
        }
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 0
        out.addAttribute(.paragraphStyle, value: para, range: all)
        return out
    }

    /// The "Meet Eddie" text view used as the alert's accessory (also rendered offscreen by --render-about).
    static func eddieView(width: CGFloat = 380) -> NSTextView {
        let text = NSMutableAttributedString(attributedString: styled(
            "Free software (GPLv3). Read the [README on GitHub](\(readmeURL.absoluteString)) for themes, custom cursors and more.\n\n"))
        text.append(NSAttributedString(string: "Meet Eddie the Giraffe\n",
                                             attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 1),
                                                          .foregroundColor: NSColor.labelColor]))
        text.append(styled(eddieMarkdown))
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textStorage?.setAttributedString(text)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let h = ceil(tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 120)
        tv.frame.size.height = h
        return tv
    }

    static func show() {
        let alert = NSAlert()
        alert.messageText = "TapHand \(version)"
        alert.informativeText = "A pointer that visibly taps on every click, for screen recordings and demos. "
            + "No permissions, no keyboard reading, no network."
        alert.accessoryView = eddieView()
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Visit the Giraffe Centre")
        alert.addButton(withTitle: "README")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn: NSWorkspace.shared.open(fundraiseURL)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(readmeURL)
        default: break
        }
    }
}
