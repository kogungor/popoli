import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut in Carbon terms (what RegisterEventHotKey wants).
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// From a key event, e.g. while recording a new shortcut in Settings. Requires at
    /// least ⌘, ⌥ or ⌃ so that ordinary typing is never captured.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        keyCode = UInt32(event.keyCode)
        modifiers = carbon
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// "⌃⌥P"
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Keyboard.keyName(for: CGKeyCode(keyCode))
    }
}

/// The global shortcut that shows the bar for the current selection.
final class Hotkey {
    static let shared = Hotkey()

    var onPress: () -> Void = {}
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.shared.onPress() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        register()
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// (Re)registers the shortcut saved in Settings; call after it changes.
    func register() {
        unregister()
        guard let shortcut = Settings.hotkey else { return }
        let id = EventHotKeyID(signature: OSType(0x504F_504C), id: 1) // "POPL"
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
