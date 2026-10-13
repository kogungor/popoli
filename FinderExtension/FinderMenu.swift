import Cocoa
import FinderSync

/// Finder Sync extension that adds "Open in Terminal" and "Copy Path" to Finder's
/// right-click menu, both for selected items and for a window's background.
///
/// The extension is sandboxed, so it does not launch Terminal itself: it hands the
/// folder to the Popoli app through a popoli://terminal URL. The URL carries a token that only
/// this extension and the app can read, so a web page can't make Popoli open a terminal.
final class FinderMenu: FIFinderSync {
    private var lastMenuKind = FIMenuKind.contextualMenuForItems

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return nil }
        lastMenuKind = menuKind
        let menu = NSMenu(title: "")
        if terminalTarget() != nil {
            menu.addItem(item("Open in Terminal", symbol: "terminal", action: #selector(openTerminal(_:))))
        }
        menu.addItem(item("Copy Path", symbol: "doc.on.clipboard", action: #selector(copyPath(_:))))
        return menu
    }

    private func item(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    /// Right-clicked items, or the folder of the window when its background was clicked.
    private func targets() -> [URL] {
        let controller = FIFinderSyncController.default()
        if lastMenuKind == .contextualMenuForItems, let selected = controller.selectedItemURLs(), !selected.isEmpty {
            return selected
        }
        return controller.targetedURL().map { [$0] } ?? []
    }

    /// Where Open in Terminal goes: the one item, or the folder several items are all in.
    /// nil when they are in different folders (the same rule as the bar's button).
    private func terminalTarget() -> URL? {
        let items = targets()
        guard let first = items.first else { return nil }
        if items.count == 1 { return first }
        let folders = Set(items.map { $0.standardizedFileURL.deletingLastPathComponent().path })
        return folders.count == 1 ? folders.first.map { URL(fileURLWithPath: $0) } : nil
    }

    @objc func openTerminal(_ sender: AnyObject?) {
        guard let target = terminalTarget() else { return }
        var components = URLComponents()
        components.scheme = "popoli"
        components.host = "terminal"
        components.queryItems = [URLQueryItem(name: "path", value: target.path), URLQueryItem(name: "token", value: Self.token)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    /// Random, made once and kept in this extension's own container, where the (unsandboxed)
    /// Popoli app reads it to check terminal links.
    private static let token: String = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = folder.appendingPathComponent("terminal-token")
        if let saved = try? String(contentsOf: file, encoding: .utf8), saved.count == 64 { return saved }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? token.write(to: file, atomically: true, encoding: .utf8)
        return token
    }()

    @objc func copyPath(_ sender: AnyObject?) {
        let paths = targets().map(\.path)
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }
}
