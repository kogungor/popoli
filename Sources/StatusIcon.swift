import AppKit

/// The menu bar icon: a one-color version of the app logo — the bar of buttons above a
/// line of selected text. It is a template image, so macOS draws it white or black to
/// match the menu bar.
enum StatusIcon {
    static let plain = image(badged: false)
    static let badged = image(badged: true)

    /// Where the update badge sits, in the 18-point icon's coordinates: just off the top-right
    /// corner of the bar, clear of its buttons.
    private static let badgeCenter = NSPoint(x: 18.3, y: 17.1)
    private static let badgeRadius: CGFloat = 2.8

    private static func image(badged: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // The action bar: an outlined bubble with three buttons.
            let bar = NSBezierPath(roundedRect: NSRect(x: 3.0, y: 9.3, width: 14.0, height: 7.4), xRadius: 2.8, yRadius: 2.8)
            bar.lineWidth = 1.3
            bar.stroke()
            for x in [4.8, 8.6, 12.4] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 11.6, width: 2.8, height: 2.8), xRadius: 0.8, yRadius: 0.8).fill()
            }

            // The selected text: a solid strip with two lines of text cut out of it.
            NSBezierPath(roundedRect: NSRect(x: 1.0, y: 1.3, width: 12.0, height: 6.4), xRadius: 2.0, yRadius: 2.0).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(roundedRect: NSRect(x: 2.8, y: 4.8, width: 7.8, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
            NSBezierPath(roundedRect: NSRect(x: 2.8, y: 2.8, width: 4.8, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()

            // A gap around the badge, so it doesn't touch the bar.
            if badged {
                let gap = badgeRadius + 1.2
                NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - gap, y: badgeCenter.y - gap, width: gap * 2, height: gap * 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badged ? "Popoli, update available" : "Popoli"
        return image
    }

    /// A red dot on the icon while an update is waiting, like the badge macOS puts on System
    /// Settings for a software update. The glyph is a template image that macOS colors, so the
    /// dot is a view on top of it.
    static func setBadge(_ shown: Bool, on button: NSStatusBarButton) {
        button.image = shown ? badged : plain
        let id = NSUserInterfaceItemIdentifier("updateBadge")
        let existing = button.subviews.first { $0.identifier == id }
        if !shown {
            existing?.removeFromSuperview()
        } else if existing == nil {
            let dot = NSView()
            dot.identifier = id
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            dot.layer?.cornerRadius = badgeRadius
            dot.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(dot)
            // The icon is centered in the button; Auto Layout's y grows downward.
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: badgeRadius * 2),
                dot.heightAnchor.constraint(equalToConstant: badgeRadius * 2),
                dot.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: badgeCenter.x - 9),
                dot.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 9 - badgeCenter.y),
            ])
        }
    }
}
