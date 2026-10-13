import AppKit
import Carbon.HIToolbox

struct KeyCombo: CustomStringConvertible {
    var keyCode: CGKeyCode
    var flags: CGEventFlags

    var description: String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        return parts.joined() + "key\(keyCode)"
    }
}

/// Synthesizes key presses and parses key combo descriptions.
enum Keyboard {
    private static let lock = NSLock()
    private static var layoutMap: [String: CGKeyCode] = [:]

    /// Builds a character → key code map from the current keyboard layout, so ⌘C still
    /// lands on "C" with non-US layouts. TIS calls must run on the main thread.
    static func refreshLayout() {
        assert(Thread.isMainThread)
        var map: [String: CGKeyCode] = [:]
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            data.withUnsafeBytes { buffer in
                guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
                for code in 0..<128 {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                                &deadKeys, chars.count, &length, &chars)
                    guard status == noErr, length > 0 else { continue }
                    let key = String(utf16CodeUnits: chars, count: length).lowercased()
                    if map[key] == nil { map[key] = CGKeyCode(code) }
                }
            }
        }
        lock.lock(); layoutMap = map; lock.unlock()
    }

    private static let named: [String: CGKeyCode] = [
        "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "forwarddelete": 117, "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125,
        "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// ANSI positions, used when the current layout does not produce the character.
    private static let ansi: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
    ]

    private static let symbols: [String: String] = [
        "return": "↩", "enter": "⌅", "tab": "⇥", "space": "Space", "delete": "⌫", "backspace": "⌫",
        "forwarddelete": "⌦", "escape": "⎋", "esc": "⎋", "left": "←", "right": "→", "up": "↑", "down": "↓",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    /// How a key code is shown in a shortcut, e.g. "P", "↩" or "F5".
    static func keyName(for code: CGKeyCode) -> String {
        if let name = named.first(where: { $0.value == code })?.key {
            return symbols[name] ?? name.uppercased()
        }
        lock.lock()
        let character = layoutMap.first(where: { $0.value == code })?.key
        lock.unlock()
        return (character ?? ansi.first(where: { $0.value == code })?.key ?? "?").uppercased()
    }

    static func keyCode(for key: String) -> CGKeyCode? {
        let k = key.lowercased()
        if let code = named[k] { return code }
        lock.lock(); let fromLayout = layoutMap[k]; lock.unlock()
        return fromLayout ?? ansi[k]
    }

    static func press(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let held = CGEventSource.flagsState(.hidSystemState).intersection(modifiers)
        let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false)
        down?.flags = combo.flags
        up?.flags = combo.flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        // The system keeps the modifiers of the last posted key as pressed: without letting go
        // of them, the next click would count as a ⌘-click (and Popoli ignores those).
        if !combo.flags.subtracting(held).isEmpty,
           let release = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) {
            release.type = .flagsChanged
            release.flags = held
            release.post(tap: .cghidEventTap)
        }
    }

    /// Presses ⌘ + `key` (e.g. "c" for Copy).
    static func command(_ key: String) {
        guard let code = keyCode(for: key) else { return }
        press(KeyCombo(keyCode: code, flags: .maskCommand))
    }

    static func press(sequence combos: [KeyCombo]) {
        for (i, combo) in combos.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.03) { press(combo) }
        }
    }

    // MARK: Parsing

    /// Parses descriptions like "cmd shift H", "option command 1" or "return".
    static func parse(string: String) -> KeyCombo? {
        var flags: CGEventFlags = []
        var key: String?
        for token in string.split(whereSeparator: { $0 == " " || $0 == "+" }) {
            switch token.lowercased() {
            case "command", "cmd", "⌘": flags.insert(.maskCommand)
            case "option", "opt", "alt", "⌥": flags.insert(.maskAlternate)
            case "control", "ctrl", "⌃": flags.insert(.maskControl)
            case "shift", "⇧": flags.insert(.maskShift)
            default: key = String(token)
            }
        }
        guard let key, let code = keyCode(for: key) else { return nil }
        return KeyCombo(keyCode: code, flags: flags)
    }
}
