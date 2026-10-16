import AppKit

/// Watches global mouse and keyboard events and decides when to show or hide the bar.
final class SelectionMonitor {
    private enum Trigger: String { case drag, multiClick = "multi-click", shiftClick = "shift-click", click }

    private var monitors: [Any] = []
    /// Monitors needed only while the bar or the result card is on screen.
    private var transientMonitors: [Any] = []
    private var downPoint = NSPoint.zero
    private var downInMenuBar = false
    /// Read and written on `queue` only.
    private var downOnControl = false
    private var generation = 0
    private var lastFinderSelection: [String] = []
    private let queue = DispatchQueue(label: "app.popoli.selection", qos: .userInteractive)
    /// Finder can take a while to answer, so it gets its own queue.
    private let finderQueue = DispatchQueue(label: "app.popoli.finder", qos: .userInteractive)

    /// Roles where a press is never the start of a text selection (title bars, buttons, scroll bars…).
    private static let nonTextRoles: Set<String> = [
        "AXButton", "AXScrollBar", "AXValueIndicator", "AXSplitter", "AXSlider", "AXMenuBar",
        "AXMenuBarItem", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXTabGroup",
        "AXToolbar", "AXWindow", "AXIncrementor", "AXDisclosureTriangle", "AXDockItem", "AXImage",
    ]

    /// Only clicks are watched all the time. Mouse moves, scrolling and key presses arrive
    /// constantly, so they are watched only while something is on screen (see `updateTransient`).
    func start() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in self?.mouseDown() }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in self?.mouseUp(event) }) {
            monitors.append(monitor)
        }
        // Esc while the result card itself has focus.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { Popoli.result.hide(); return nil }
            return event
        }
    }

    /// Starts or stops the extra monitors to match whether the bar or the card is visible.
    func updateTransient() {
        let needed = Popoli.bar.isVisible || Popoli.result.isVisible
        if needed && transientMonitors.isEmpty {
            func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
                if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
                    transientMonitors.append(monitor)
                }
            }
            add([.rightMouseDown, .otherMouseDown, .scrollWheel, .leftMouseDragged]) { _ in Popoli.bar.hide() }
            add(.mouseMoved) { [weak self] _ in self?.mouseMoved() }
            add(.keyDown) { event in
                Popoli.bar.hide()
                if event.keyCode == 53 { Popoli.result.hide() }
            }
        } else if !needed && !transientMonitors.isEmpty {
            transientMonitors.forEach(NSEvent.removeMonitor)
            transientMonitors.removeAll()
        }
    }

    private func mouseDown() {
        generation += 1
        Popoli.bar.hide()
        // Global monitors only see clicks outside Popoli's own windows.
        Popoli.result.hide()
        downPoint = NSEvent.mouseLocation
        // The menu bar (Popoli's own icon included) never holds a text selection.
        downInMenuBar = Self.isInMenuBar(downPoint)
        guard Settings.enabled, !downInMenuBar else { return }
        // Asking the app under the mouse what was clicked is an Accessibility round trip that
        // can take up to its timeout, so it must never run on the main thread.
        let point = downPoint
        queue.async { [weak self] in
            let onControl = AXIsProcessTrusted() && AX.isControl(at: point, roles: Self.nonTextRoles)
            self?.downOnControl = onControl
        }
    }

    private static func isInMenuBar(_ p: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            p.x >= screen.frame.minX && p.x <= screen.frame.maxX
                && p.y > screen.visibleFrame.maxY && p.y <= screen.frame.maxY
        }
    }

    private func mouseUp(_ event: NSEvent) {
        guard Settings.enabled, !downInMenuBar, AXIsProcessTrusted() else { return }
        let up = NSEvent.mouseLocation
        let distance = hypot(up.x - downPoint.x, up.y - downPoint.y)
        let modifiers = event.modifierFlags
        if modifiers.contains(.command) || modifiers.contains(.control) { return }

        let trigger: Trigger
        if distance > 6 { trigger = .drag }
        else if event.clickCount >= 2 { trigger = .multiClick }
        else if modifiers.contains(.shift) { trigger = .shiftClick }
        else { trigger = .click }

        let gen = generation
        let start = event.timestamp
        // A short wait lets double/triple clicks finish (a new mouse-down cancels this check).
        let delay = trigger == .multiClick ? 0.15 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.evaluate(trigger, at: up, generation: gen, since: start)
        }
    }

    private func mouseMoved() {
        guard Popoli.bar.isVisible else { return }
        let p = NSEvent.mouseLocation
        let f = Popoli.bar.frame
        let dx = max(f.minX - p.x, 0, p.x - f.maxX)
        let dy = max(f.minY - p.y, 0, p.y - f.maxY)
        if hypot(dx, dy) > 110 { Popoli.bar.hide() }
    }

    private func evaluate(_ trigger: Trigger, at point: NSPoint, generation gen: Int, since start: TimeInterval) {
        guard gen == generation,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        // Plain clicks are logged only when they show something (Finder, Paste in empty fields).
        let logged = trigger != .click
        var appOnly = SelectionContext()
        appOnly.app = app
        if Settings.excludedApps.contains(app.bundleIdentifier ?? "") {
            if logged { Diagnostics.record(trigger.rawValue, appOnly, note: "app is in the list where the bar stays away") }
            return
        }
        let isFinder = app.bundleIdentifier == FinderBridge.bundleID
        AX.primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? AX.primaryScreenHeight

        queue.async { [weak self] in
            guard let self else { return }
            // Pressed on a button, scroll bar, title bar…: not a text selection. In Finder a file's
            // icon counts as an image, but clicking it selects the file.
            if self.downOnControl && trigger != .multiClick && !isFinder {
                if logged { Diagnostics.record(trigger.rawValue, appOnly, note: "started on a control, not on text") }
                return
            }
            if trigger == .click {
                if isFinder {
                    DispatchQueue.main.async {
                        if gen == self.generation { self.showFinderFiles(app, at: point, since: start) }
                    }
                } else if Settings.pasteOnEmptyField, Clipboard.hasContent,
                          SelectionReader.focusIsEmptyTextField(app: app) {
                    var ctx = SelectionContext()
                    ctx.app = app
                    ctx.canPaste = true
                    ctx.anchor = NSRect(x: point.x, y: point.y - 8, width: 0, height: 22)
                    DispatchQueue.main.async {
                        if gen == self.generation { self.present(ctx, "click in empty field", since: start) }
                    }
                }
                return
            }
            let ctx = SelectionReader.read(app: app, mouse: point, allowCopyFallback: !isFinder)
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                if ctx.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if isFinder && trigger == .drag {
                        self.showFinderFiles(app, at: point, since: start)
                    } else {
                        Diagnostics.record(trigger.rawValue, ctx, since: start, note: "no selected text found")
                    }
                    return
                }
                self.present(ctx, trigger.rawValue, since: start)
            }
        }
    }

    /// The keyboard shortcut: shows the bar for whatever is selected in the frontmost app,
    /// even in excluded apps. With nothing selected it offers Paste in a text field, or the
    /// file actions in Finder.
    func showForShortcut() {
        guard Settings.enabled, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        generation += 1
        let gen = generation
        let start = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation
        let isFinder = app.bundleIdentifier == FinderBridge.bundleID
        AX.primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? AX.primaryScreenHeight
        queue.async { [weak self] in
            var ctx = SelectionReader.read(app: app, mouse: mouse, allowCopyFallback: !isFinder, anchorToSelection: true)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if !ctx.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.present(ctx, "shortcut", since: start)
                } else if isFinder {
                    self.showFinderFiles(app, at: mouse, force: true, since: start)
                } else if ctx.canPaste && Clipboard.hasContent {
                    ctx.text = ""
                    self.present(ctx, "shortcut", since: start)
                } else {
                    Diagnostics.record("shortcut", ctx, since: start, note: "no selected text found")
                    HUD.shared.show(symbol: "text.cursor", text: "Select some text first", near: ctx.anchor)
                }
            }
        }
    }

    /// In Finder, a click that changes the file selection shows the bar with Path/Copy.
    private func showFinderFiles(_ app: NSRunningApplication, at point: NSPoint, force: Bool = false,
                                 since start: TimeInterval) {
        guard Settings.finderFiles || force else { return }
        let gen = generation
        finderQueue.async { [weak self] in
            // A later click already replaced this one.
            guard let self, gen == self.generation else { return }
            let paths = FinderBridge.selectedPaths()
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                defer { self.lastFinderSelection = paths }
                if paths.isEmpty {
                    var appOnly = SelectionContext()
                    appOnly.app = app
                    Diagnostics.record("finder files", appOnly, since: start,
                                       note: "Finder gave no selection (nothing selected, or Popoli may not control Finder)")
                }
                guard !paths.isEmpty, force || paths != self.lastFinderSelection else { return }
                var ctx = SelectionContext()
                ctx.app = app
                ctx.files = paths
                ctx.canCopy = true
                ctx.anchor = NSRect(x: point.x, y: point.y - 8, width: 0, height: 22)
                self.present(ctx, "finder files", since: start)
            }
        }
    }

    private func present(_ ctx: SelectionContext, _ trigger: String, since start: TimeInterval) {
        let entries = Popoli.registry.entries(for: ctx)
        Diagnostics.record(trigger, ctx, buttons: entries.map(\.action.title), since: start,
                           note: entries.isEmpty ? "no button fits this selection" : nil)
        guard !entries.isEmpty else { return }
        Popoli.bar.show(entries, anchor: ctx.anchor)
    }
}
