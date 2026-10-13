import AppKit

/// Borderless panel that floats above everything without activating Popoli,
/// so the app the user is working in keeps keyboard focus (⌘X/⌘V reach it).
final class FloatingPanel: NSPanel {
    private var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    init(allowsKey: Bool = false) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.allowsKey = allowsKey
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}

/// A Liquid Glass surface (macOS 26+) with a soft shadow and a hairline edge, so it stays
/// visible on white pages where plain glass nearly disappears. It fills its view, leaving
/// `margin` around the glass for the shadow; use it as a panel's content view.
final class GlassSurface: NSView {
    let glass = NSGlassEffectView()
    let margin: CGFloat
    private let cornerRadius: CGFloat
    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()
    private let edge = EdgeView()
    /// Sits inside the glass behind the content. Liquid Glass lightens itself over light
    /// pages, so on its own it cannot stay dark; this smoky layer keeps the text readable
    /// while the glass edges and blur still show.
    private let tint = NSView()
    private let content: NSView

    init(content: NSView, cornerRadius: CGFloat, margin: CGFloat, interactive: Bool) {
        self.cornerRadius = cornerRadius
        self.margin = margin
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true

        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.22
        shadowLayer.shadowRadius = 9
        shadowLayer.shadowOffset = CGSize(width: 0, height: -3)
        // Only draw the shadow outside the glass, so it does not darken the glass itself.
        shadowMask.fillRule = .evenOdd
        shadowLayer.mask = shadowMask
        layer?.addSublayer(shadowLayer)

        glass.style = .regular
        glass.cornerRadius = cornerRadius
        // macOS 27 lets glass react to clicks. Set by name so the app also builds with the
        // macOS 26 SDK (CI uses it), where the property does not exist yet.
        if glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
            glass.setValue(interactive, forKey: "effectIsInteractive")
        }
        tint.wantsLayer = true
        tint.layer?.cornerRadius = cornerRadius
        tint.layer?.cornerCurve = .continuous
        tint.addSubview(content)
        glass.contentView = tint
        addSubview(glass)
        edge.cornerRadius = cornerRadius
        addSubview(edge)
        applyStyle()
    }

    /// Applies Settings.barStyle: smoky dark glass with light text (default), light glass,
    /// or the plain system look. Text uses label colors, so it follows the appearance.
    func applyStyle() {
        switch Settings.barStyle {
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
            glass.tintColor = NSColor.black.withAlphaComponent(0.45)
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        case .light:
            appearance = NSAppearance(named: .aqua)
            glass.tintColor = NSColor.white.withAlphaComponent(0.55)
            tint.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        case .system:
            appearance = nil
            glass.tintColor = nil
            tint.layer?.backgroundColor = nil
        }
        edge.needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Panels start at a placeholder size; wait for a real one.
        guard newSize.width > margin * 2, newSize.height > margin * 2 else { return }
        let rect = NSRect(origin: .zero, size: newSize).insetBy(dx: margin, dy: margin)
        glass.frame = rect
        tint.frame = NSRect(origin: .zero, size: rect.size)
        content.frame = tint.bounds
        edge.frame = rect

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shape = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = shape
        let mask = CGMutablePath()
        mask.addRect(bounds)
        mask.addPath(shape)
        shadowMask.frame = bounds
        shadowMask.path = mask
        CATransaction.commit()
    }
}

/// Hairline border on top of the glass. Lets clicks through to the buttons below.
private final class EdgeView: NSView {
    var cornerRadius: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.14)).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5)
        path.lineWidth = 1
        path.stroke()
    }
}

enum Glass {
    /// Frame for a floating surface of `size` centered above `anchor` (or below it when
    /// there is no room), kept inside the visible area of the anchor's screen.
    static func frame(for size: NSSize, above anchor: NSRect, gap: CGFloat = 8) -> NSRect {
        let point = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.midX - size.width / 2
        var y = anchor.maxY + gap
        if y + size.height > visible.maxY { y = anchor.minY - gap - size.height }
        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        y = min(max(y, visible.minY + 6), visible.maxY - size.height - 6)
        return NSRect(origin: NSPoint(x: x.rounded(), y: y.rounded()), size: size)
    }
}

// MARK: - Bar

final class BarButton: NSView {
    static let height: CGFloat = 36

    enum DragPhase { case began, moved, ended }

    /// Called with the modifier keys held at the click.
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    /// ⌘-drag: called with how far the pointer moved since the mouse went down. Buttons
    /// without it can't be moved.
    var onDrag: ((DragPhase, CGFloat) -> Void)?
    /// Where the mouse went down with ⌘ held: the press may become a drag.
    private var dragStartX: CGFloat?
    private var dragging = false
    private let imageView: NSImageView?
    private let label: NSTextField?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(icon: NSImage?, title: String, hint: String? = nil) {
        if let icon {
            let view = NSImageView(image: icon)
            view.contentTintColor = .labelColor
            view.imageScaling = .scaleNone
            imageView = view
            label = nil
        } else {
            let field = NSTextField(labelWithString: title)
            field.font = .systemFont(ofSize: 13, weight: .medium)
            field.textColor = .labelColor
            field.lineBreakMode = .byTruncatingTail
            label = field
            imageView = nil
        }
        super.init(frame: .zero)
        if let imageView { addSubview(imageView) }
        if let label { addSubview(label) }
        toolTip = hint.map { "\(title)\n\($0)" } ?? title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var contentSize: NSSize {
        if let image = imageView?.image { return image.size }
        guard let label else { return .zero }
        // cellSize includes the cell's padding; intrinsicContentSize is a few points short
        // and would make the label truncate when used as the frame.
        let s = label.cell?.cellSize ?? label.intrinsicContentSize
        return NSSize(width: min(ceil(s.width), 180), height: ceil(s.height))
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: contentSize.width + 22, height: Self.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let s = contentSize
        let rect = NSRect(x: ((newSize.width - s.width) / 2).rounded(), y: ((newSize.height - s.height) / 2).rounded(),
                          width: s.width, height: s.height)
        imageView?.frame = rect
        label?.frame = rect
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        NSColor.labelColor.withAlphaComponent(pressed ? 0.16 : 0.08).setFill()
        let r = bounds.insetBy(dx: 2, dy: 4)
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) {
        guard !dragging else { return }
        hovering = false; pressed = false
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        dragStartX = event.modifierFlags.contains(.command) && onDrag != nil ? event.locationInWindow.x : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartX else { return }
        let dx = event.locationInWindow.x - start
        if !dragging {
            // A ⌘-click that barely moves stays a click (extensions can read ⌘).
            guard abs(dx) > 3 else { return }
            dragging = true
            hovering = true
            NSCursor.closedHand.push()
            onDrag?(.began, dx)
        }
        onDrag?(.moved, dx)
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        if dragging, let start = dragStartX {
            dragging = false
            dragStartX = nil
            NSCursor.pop()
            onDrag?(.ended, event.locationInWindow.x - start)
            return
        }
        dragStartX = nil
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside { onClick?(event.modifierFlags.intersection([.shift, .option, .control, .command])) }
    }
}

/// The glass pill of action buttons shown above a selection.
final class BarController {
    private let panel = FloatingPanel()
    private var entries: [BarEntry] = []
    private var anchor = NSRect.zero
    private var page = 0
    private let perPage = 10
    private let margin: CGFloat = 14
    /// The buttons of the entries on the current page, left to right.
    private var slots: [(button: BarButton, entry: BarEntry)] = []
    /// Their frames when a ⌘-drag began.
    private var dragFrames: [NSRect] = []

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }
    var window: NSWindow { panel }

    func show(_ entries: [BarEntry], anchor: NSRect) {
        self.entries = entries
        self.anchor = anchor
        page = 0
        rebuild(fadeIn: true)
        Popoli.monitor.updateTransient()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        Popoli.monitor.updateTransient()
    }

    private func rebuild(fadeIn: Bool) {
        var views: [NSView] = []
        let paged = entries.count > perPage + 1
        let start = paged ? page * perPage : 0
        let end = paged ? min(start + perPage, entries.count) : entries.count

        if paged && page > 0 {
            views.append(navButton(symbol: "chevron.left", title: "Previous") { [weak self] _ in
                self?.page -= 1; self?.rebuild(fadeIn: false)
            })
        }
        slots = []
        for entry in entries[start..<end] {
            let button = BarButton(icon: entry.action.icon, title: entry.action.title, hint: entry.action.hint)
            button.toolTip = (button.toolTip ?? entry.action.title) + "\n⌘-drag to move"
            button.onClick = { [weak self] modifiers in self?.perform(entry, modifiers: modifiers) }
            button.onDrag = { [weak self, weak button] phase, dx in
                guard let self, let button else { return }
                self.drag(button, phase, dx)
            }
            slots.append((button, entry))
            views.append(button)
        }
        if paged && end < entries.count {
            views.append(navButton(symbol: "chevron.right", title: "More") { [weak self] _ in
                self?.page += 1; self?.rebuild(fadeIn: false)
            })
        }

        // Plain frame layout: every button gets exactly its natural width.
        let row = NSView()
        var x: CGFloat = 4
        for view in views {
            let width = view.intrinsicContentSize.width
            view.frame = NSRect(x: x, y: 0, width: width, height: BarButton.height)
            row.addSubview(view)
            x += width
        }
        let size = NSSize(width: x + 4, height: BarButton.height)
        row.frame = NSRect(origin: .zero, size: size)

        let surface = GlassSurface(content: row, cornerRadius: size.height / 2, margin: margin, interactive: true)
        panel.contentView = surface

        let barFrame = Glass.frame(for: size, above: anchor)
        panel.setFrame(barFrame.insetBy(dx: -margin, dy: -margin), display: true)

        if fadeIn {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    // MARK: Rearranging

    /// ⌘-drag: the button follows the pointer along the bar, the others make room, and the
    /// new order is saved when it is let go (the same order as Settings ▸ Buttons).
    private func drag(_ button: BarButton, _ phase: BarButton.DragPhase, _ dx: CGFloat) {
        guard let index = slots.firstIndex(where: { $0.button === button }) else { return }
        switch phase {
        case .began:
            dragFrames = slots.map(\.button.frame)
            button.superview?.addSubview(button)    // above its neighbours
        case .moved:
            guard let first = dragFrames.first, let last = dragFrames.last else { return }
            var frame = dragFrames[index]
            frame.origin.x = min(max(frame.minX + dx, first.minX), last.maxX - frame.width)
            button.frame = frame
            layOut(dragged: index, at: target(for: index, midX: frame.midX), animated: true)
        case .ended:
            let frame = dragFrames[index].offsetBy(dx: dx, dy: 0)
            let to = target(for: index, midX: frame.midX)
            guard to != index else {
                layOut(dragged: index, at: index, animated: true)
                return
            }
            save(moving: index, to: to)
        }
    }

    /// The place among the page's buttons for the dragged one, from where its middle is.
    private func target(for index: Int, midX: CGFloat) -> Int {
        dragFrames.indices.filter { $0 != index && dragFrames[$0].midX < midX }.count
    }

    /// Puts every button but the dragged one where it goes if the dragged one lands at `to`.
    private func layOut(dragged index: Int, at to: Int, animated: Bool) {
        var order = Array(slots.indices.filter { $0 != index })
        order.insert(index, at: to)
        var x = dragFrames.first?.minX ?? 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            for i in order {
                let width = dragFrames[i].width
                if i != index { slots[i].button.animator().setFrameOrigin(NSPoint(x: x, y: 0)) }
                x += width
            }
        }
    }

    /// Saves the new order and redraws the bar with it.
    private func save(moving index: Int, to: Int) {
        var visible = slots.map(\.entry.action.id)
        let moved = visible.remove(at: index)
        visible.insert(moved, at: to)

        // The bar shows only some buttons, so the moved one goes next to its new neighbour in
        // the full order and everything else keeps its place.
        var order = Popoli.registry.items().map(\.id).filter { $0 != moved }
        if to + 1 < visible.count, let next = order.firstIndex(of: visible[to + 1]) {
            order.insert(moved, at: next)
        } else if to > 0, let previous = order.firstIndex(of: visible[to - 1]) {
            order.insert(moved, at: previous + 1)
        } else {
            order.insert(moved, at: 0)
        }
        Settings.buttonOrder = order

        let start = entries.firstIndex { $0.action.id == slots.first?.entry.action.id } ?? 0
        let pageEntries = visible.compactMap { id in slots.first { $0.entry.action.id == id }?.entry }
        entries.replaceSubrange(start..<(start + slots.count), with: pageEntries)
        rebuild(fadeIn: false)
        if SettingsWindowController.shared.window?.isVisible == true { SettingsWindowController.shared.model.refresh() }
    }

    private func navButton(symbol: String, title: String, action: @escaping (NSEvent.ModifierFlags) -> Void) -> BarButton {
        let button = BarButton(icon: Icons.symbol(symbol), title: title)
        button.onClick = action
        return button
    }

    private func perform(_ entry: BarEntry, modifiers: NSEvent.ModifierFlags) {
        hide()
        var context = entry.context
        context.modifiers = modifiers
        // Let the panel disappear before keystrokes are sent to the target app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            entry.action.perform(context)
        }
    }
}

// MARK: - HUD

/// A small glass toast ("Copied", errors) that fades out on its own.
final class HUD {
    static let shared = HUD()

    private let panel = FloatingPanel()
    private var hideWork: DispatchWorkItem?
    private let margin: CGFloat = 14

    init() {
        panel.ignoresMouseEvents = true
    }

    func show(symbol: String, text: String, near anchor: NSRect) {
        let image = NSImageView(image: Icons.symbol(symbol) ?? NSImage())
        image.contentTintColor = symbol == "xmark" ? .systemRed : .labelColor
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1

        let imageSize = image.image?.size ?? .zero
        let labelSize = label.cell?.cellSize ?? label.intrinsicContentSize
        let labelWidth = min(ceil(labelSize.width), 380)
        let size = NSSize(width: 14 + imageSize.width + 7 + labelWidth + 16, height: 36)
        image.frame = NSRect(x: 14, y: ((size.height - imageSize.height) / 2).rounded(),
                             width: imageSize.width, height: imageSize.height)
        label.frame = NSRect(x: 14 + imageSize.width + 7, y: ((size.height - labelSize.height) / 2).rounded(),
                             width: labelWidth, height: labelSize.height)
        let row = NSView(frame: NSRect(origin: .zero, size: size))
        row.addSubview(image)
        row.addSubview(label)

        let surface = GlassSurface(content: row, cornerRadius: size.height / 2, margin: margin, interactive: false)
        panel.contentView = surface
        panel.setFrame(Glass.frame(for: size, above: anchor).insetBy(dx: -margin, dy: -margin), display: true)

        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.panel.animator().alphaValue = 0
            }, completionHandler: { self.panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (symbol == "xmark" ? 2.5 : 1.1), execute: work)
    }
}
