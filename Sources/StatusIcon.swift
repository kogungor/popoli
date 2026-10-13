import AppKit

/// The menu bar icon: a one-color version of the app logo — the bar of buttons above a
/// line of selected text. It is a template image, so macOS draws it white or black to
/// match the menu bar.
enum StatusIcon {
    static func image() -> NSImage {
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
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Popoli"
        return image
    }
}
