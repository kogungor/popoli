import AppKit
import ApplicationServices

/// Everything an action needs to know about the current selection.
struct SelectionContext {
    /// Text the action works on (an extension regex may narrow it).
    var text = ""
    /// The whole selected text, before any regex narrowing.
    var fullText = ""
    /// POSIX paths of files selected in Finder.
    var files: [String] = []
    var app: NSRunningApplication?
    var canCut = false
    var canCopy = false
    var canPaste = false
    /// Screen rectangle (Cocoa coordinates) the bar is placed above.
    var anchor = NSRect.zero
    /// Modifier keys held when a bar button was clicked (⇧ ⌥ ⌃ ⌘).
    var modifiers: NSEvent.ModifierFlags = []
    /// How the text was read, for the diagnostics log: "accessibility", "copy" or "none".
    var readBy = "none"

    var bundleID: String { app?.bundleIdentifier ?? "" }
    var appName: String { app?.localizedName ?? "" }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func links() -> [URL] {
        guard let detector = Self.detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    var webURLs: [URL] { links().filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } }
    var emails: [String] {
        links().filter { $0.scheme == "mailto" }.map { String($0.absoluteString.dropFirst("mailto:".count)) }
    }
}

/// Thin helpers over the C Accessibility API.
enum AX {
    /// Height of the primary screen, used to flip between AX (top-left origin) and Cocoa
    /// (bottom-left origin) coordinates. Updated on the main thread.
    static var primaryScreenHeight: CGFloat = NSScreen.screens.first?.frame.maxY ?? 0

    static let systemWide = AXUIElementCreateSystemWide()

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func multiple(_ element: AXUIElement, _ attributes: [String]) -> [Any]? {
        var out: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray,
                                                            AXCopyMultipleAttributeOptions(rawValue: 0), &out)
        guard status == .success else { return nil }
        return out as? [Any]
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    /// A text field, text view, or text inside an editable web region.
    static func isEditable(_ element: AXUIElement) -> Bool {
        isSettable(element, kAXValueAttribute) || value(element, "AXEditableAncestor") != nil
    }

    static func toAX(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: primaryScreenHeight - p.y) }

    static func toCocoa(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryScreenHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Role of the UI element under a screen point (Cocoa coordinates).
    static func role(at point: NSPoint) -> String? {
        let p = toAX(point)
        var element: AXUIElement?
        AXUIElementSetMessagingTimeout(systemWide, 0.1)
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &element) == .success,
              let element else { return nil }
        return string(element, kAXRoleAttribute)
    }

    /// Screen rectangle of the selected text range, if the app exposes it.
    static func selectionBounds(_ element: AXUIElement) -> NSRect? {
        guard let range = value(element, kAXSelectedTextRangeAttribute) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &out) == .success,
              let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        return toCocoa(rect)
    }

    /// WebKit (Safari, Mail…) leaves AXSelectedText empty for text selected on a page, but its
    /// text markers hold the selection and where it is on screen.
    static func selectionByTextMarkers(_ element: AXUIElement) -> (text: String, bounds: NSRect?)? {
        guard let range = value(element, "AXSelectedTextMarkerRange") else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString,
                                                         range, &text) == .success,
              let string = text as? String, !string.isEmpty else { return nil }
        var out: CFTypeRef?
        var rect = CGRect.zero
        if AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString,
                                                      range, &out) == .success,
           let out, CFGetTypeID(out) == AXValueGetTypeID(),
           AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 {
            return (string, toCocoa(rect))
        }
        return (string, nil)
    }

    // MARK: Edit menu

    struct EditMenuState { var cut: Bool?; var copy: Bool?; var paste: Bool? }

    private static var editMenuIndex: [pid_t: Int] = [:]
    private static var manualAccessibilityPIDs = Set<pid_t>()

    /// Reads whether Edit ▸ Cut/Copy/Paste are enabled. This is the most reliable signal
    /// for "is there a selection" and "is this an editable field" across apps.
    /// Called on the selection queue only.
    static func editMenuState(_ app: AXUIElement, pid: pid_t) -> EditMenuState? {
        guard let menuBar = element(app, kAXMenuBarAttribute) else { return nil }
        let items = children(menuBar)
        guard items.count > 1 else { return nil }
        var order: [Int] = []
        if let cached = editMenuIndex[pid], cached < items.count { order.append(cached) }
        for i in [3, 2, 4, 1, 5, 6, 7] where i < items.count && !order.contains(i) { order.append(i) }

        for index in order {
            guard let menu = children(items[index]).first else { continue }
            var state = EditMenuState()
            for entry in children(menu) {
                guard let values = multiple(entry, [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
                                                    kAXEnabledAttribute]),
                      values.count == 3,
                      let char = values[0] as? String,
                      let modifiers = values[1] as? Int, modifiers == 0 else { continue }
                let enabled = (values[2] as? Bool) ?? false
                switch char.uppercased() {
                case "X": state.cut = enabled
                case "C": state.copy = enabled
                case "V": state.paste = enabled
                default: break
                }
            }
            if state.copy != nil {
                editMenuIndex[pid] = index
                return state
            }
        }
        return nil
    }

    /// Electron apps only build their accessibility tree when asked to.
    static func enableManualAccessibility(_ app: AXUIElement, pid: pid_t) {
        guard manualAccessibilityPIDs.insert(pid).inserted else { return }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}

enum SelectionReader {
    /// Reads the selection of `app`. Runs on a background queue: it may post ⌘C and
    /// wait for the clipboard when the app does not expose its selection over AX.
    /// With `anchorToSelection` (the keyboard shortcut) the bar goes above the selection
    /// wherever it is; otherwise it stays near the mouse.
    static func read(app: NSRunningApplication, mouse: NSPoint, allowCopyFallback: Bool,
                     anchorToSelection: Bool = false) -> SelectionContext {
        var ctx = SelectionContext()
        ctx.app = app
        ctx.anchor = NSRect(x: mouse.x, y: mouse.y - 8, width: 0, height: 22)

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        AX.enableManualAccessibility(appElement, pid: pid)

        let menu = AX.editMenuState(appElement, pid: pid)
        let focused = AX.element(appElement, kAXFocusedUIElementAttribute)
        var axText = focused.flatMap { AX.string($0, kAXSelectedTextAttribute) }
        var markerBounds: NSRect?
        if axText?.isEmpty ?? true, let focused, let selection = AX.selectionByTextMarkers(focused) {
            axText = selection.text
            markerBounds = selection.bounds
        }
        // Browsers leave Edit ▸ Cut/Paste enabled on read-only pages, so when the app exposes
        // its focused element, Cut/Paste also require that element to be editable. A focused
        // window (Sublime Text reports one) says nothing about that; the Edit menu decides.
        let textFocus = focused.flatMap { AX.string($0, kAXRoleAttribute) == kAXWindowRole ? nil : $0 }
        if let editable = textFocus.map(AX.isEditable) {
            ctx.canCut = editable && (menu?.cut ?? true)
            ctx.canPaste = editable && (menu?.paste ?? true)
        } else {
            ctx.canCut = menu?.cut ?? false
            ctx.canPaste = menu?.paste ?? false
        }
        ctx.canCopy = menu?.copy ?? true

        if let text = axText, !text.isEmpty {
            ctx.text = text
            ctx.readBy = "accessibility"
            // Sit right above a single-line selection; for multi-line ones stay near the mouse.
            if let focused, let bounds = markerBounds ?? AX.selectionBounds(focused) {
                if anchorToSelection {
                    let top = min(bounds.height, 22)
                    ctx.anchor = NSRect(x: bounds.minX + min(bounds.width, 300) / 2, y: bounds.maxY - top,
                                        width: 0, height: top)
                } else if bounds.height < 40, abs(bounds.midY - mouse.y) < 60,
                          mouse.x > bounds.minX - 80, mouse.x < bounds.maxX + 80 {
                    ctx.anchor = NSRect(x: mouse.x, y: bounds.minY, width: 0, height: bounds.height)
                }
            }
        } else if allowCopyFallback {
            // No AX text: fall back to ⌘C only when the Edit menu suggests something is selected.
            let worthTrying = axText == nil ? (menu?.copy ?? true) : (menu?.copy ?? false)
            if worthTrying, let text = Clipboard.copySelection() {
                ctx.text = text
                ctx.canCopy = true
                ctx.readBy = "copy"
            }
        }
        ctx.fullText = ctx.text
        return ctx
    }
}

extension SelectionReader {
    /// True when the app's focused element is an editable, empty text field (not a
    /// password field): clicking into one offers a Paste-only bar.
    static func focusIsEmptyTextField(app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        guard let focused = AX.element(appElement, kAXFocusedUIElementAttribute),
              AX.string(focused, kAXSubroleAttribute) != "AXSecureTextField",
              AX.isEditable(focused) else { return false }
        let role = AX.string(focused, kAXRoleAttribute) ?? ""
        guard ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) else { return false }
        if let count = AX.value(focused, kAXNumberOfCharactersAttribute) as? Int { return count == 0 }
        return (AX.string(focused, kAXValueAttribute) ?? "").isEmpty
    }
}

enum Clipboard {
    typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    static func snapshot(_ pb: NSPasteboard = .general) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    /// Markers from nspasteboard.org. Password managers mark a copied password as concealed or
    /// transient, and clear it after a while; clipboard histories skip what is marked.
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    static func restore(_ snapshot: Snapshot, to pb: NSPasteboard = .general) {
        pb.clearContents()
        // A password is not put back: written again by Popoli, its app would no longer clear it.
        if snapshot.contains(where: { $0.contains { $0.0 == concealed || $0.0 == transient } }) { return }
        let items = snapshot.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            // The same content again: clipboard histories need not save it twice.
            item.setData(Data(), forType: autoGenerated)
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// Sends ⌘C, reads the copied text and puts the previous clipboard back.
    /// Returns nil when nothing was copied. Blocks for up to ~0.4 s: call off the main thread.
    static func copySelection() -> String? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        Keyboard.command("c")
        let deadline = Date().addingTimeInterval(0.35)
        while pb.changeCount == before && Date() < deadline { usleep(10_000) }
        guard pb.changeCount != before else { return nil }
        usleep(30_000)
        let text = pb.string(forType: .string)
        restore(saved, to: pb)
        return text
    }

    struct Formats {
        var text: String?
        var html: String?
        var rtf: Data?
    }

    /// Like `copySelection`, but keeps the formatted versions the app put on the clipboard.
    /// Blocks for up to ~0.4 s: call off the main thread.
    static func copySelectionFormats() -> Formats? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        Keyboard.command("c")
        let deadline = Date().addingTimeInterval(0.4)
        while pb.changeCount == before && Date() < deadline { usleep(10_000) }
        guard pb.changeCount != before else { return nil }
        usleep(30_000)
        let formats = Formats(text: pb.string(forType: .string), html: pb.string(forType: .html),
                              rtf: pb.data(forType: .rtf))
        restore(saved, to: pb)
        return formats
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Puts `text` on the clipboard and pastes it into the frontmost app.
    static func paste(_ text: String) {
        copy(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Keyboard.command("v") }
    }

    static var hasContent: Bool { !(NSPasteboard.general.pasteboardItems ?? []).isEmpty }
}

/// Asks Finder for its selected files (needs the Automation permission for Finder).
enum FinderBridge {
    static let bundleID = "com.apple.finder"

    /// The selected files, at most `limit` of them. Waits at most `timeout` for Finder, which
    /// can be busy copying or reading a slow network volume. Safe on any thread.
    ///
    /// Sends what `tell application "Finder" to get selection as alias list` sends, without
    /// NSAppleScript, which only works on the main thread and has no time limit.
    static func selectedPaths(limit: Int = 1000, timeout: TimeInterval = 1) -> [String] {
        guard let selection = NSAppleEventDescriptor.record().coerce(toDescriptorType: code("obj ")) else { return [] }
        selection.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        selection.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        selection.setDescriptor(NSAppleEventDescriptor(typeCode: code("sele")), forKeyword: code("seld"))
        selection.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: code("from"))

        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: code("core"), eventID: code("getd"),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(selection, forKeyword: code("----"))
        event.setParam(NSAppleEventDescriptor(typeCode: code("alst")), forKeyword: code("rtyp"))

        guard let reply = try? event.sendEvent(options: .defaultOptions, timeout: timeout),
              reply.paramDescriptor(forKeyword: code("errn")) == nil,
              let list = reply.paramDescriptor(forKeyword: code("----")), list.numberOfItems > 0 else { return [] }
        return (1...min(list.numberOfItems, limit)).compactMap { list.atIndex($0)?.fileURLValue?.path }
    }

    /// A four-character Apple Event code such as "core".
    private static func code(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
