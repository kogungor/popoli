import Cocoa
import FinderSync

/// Finder Sync extension that adds "Open in Terminal", "Open in ›" and "Copy Path" to Finder's
/// right-click menu, both for selected items and for a window's background.
///
/// The extension is sandboxed, so it does not launch anything itself: it hands the items to
/// the Popoli app through popoli://terminal and popoli://open-in URLs. They carry a token that
/// only this extension and the app can read, so a web page can't make Popoli open a terminal.
final class FinderMenu: FIFinderSync {
    private var lastMenuKind = FIMenuKind.contextualMenuForItems

    /// An app or command for Open in ›. Popoli writes the list chosen in its Settings into this
    /// extension's container (open-in.json), since the extension can't read Popoli's settings.
    private struct OpenInEntry {
        let id: String
        let name: String
        let isCommand: Bool
        let app: String?
    }
    private var openInEntries: [OpenInEntry] = []

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return nil }
        lastMenuKind = menuKind
        let menu = NSMenu(title: "")
        let oneFolder = terminalTarget() != nil
        if oneFolder {
            menu.addItem(item("Open in Terminal", symbol: "terminal", action: #selector(openTerminal(_:))))
        }
        // Commands start in one folder; apps take every selected item.
        openInEntries = Self.loadOpenIn().filter { !$0.isCommand || oneFolder }
        if !openInEntries.isEmpty {
            let submenu = NSMenu(title: "Open in")
            for entry in openInEntries {
                let entryItem = NSMenuItem(title: entry.name, action: #selector(openIn(_:)), keyEquivalent: "")
                entryItem.image = entry.app.map(Self.appIcon) ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
                submenu.addItem(entryItem)
            }
            let parent = item("Open in", symbol: "arrow.up.forward.app", action: nil)
            parent.submenu = submenu
            menu.addItem(parent)
        }
        menu.addItem(item("Copy Path", symbol: "doc.on.clipboard", action: #selector(copyPath(_:))))
        return menu
    }

    private static func loadOpenIn() -> [OpenInEntry] {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("open-in.json")
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["id"], let name = entry["name"] else { return nil }
            return OpenInEntry(id: id, name: name, isCommand: entry["kind"] == "command", app: entry["app"])
        }
    }

    private static func appIcon(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func item(_ title: String, symbol: String, action: Selector?) -> NSMenuItem {
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

    /// Finder hands back a copy of the menu item, so the entry is found again by its title.
    @objc func openIn(_ sender: AnyObject?) {
        guard let title = (sender as? NSMenuItem)?.title else { return }
        let entries = openInEntries.isEmpty ? Self.loadOpenIn() : openInEntries
        guard let entry = entries.first(where: { $0.name == title }) else { return }
        let items = entry.isCommand ? (terminalTarget().map { [$0] } ?? []) : targets()
        guard !items.isEmpty else { return }
        var components = URLComponents()
        components.scheme = "popoli"
        components.host = "open-in"
        components.queryItems = [URLQueryItem(name: "target", value: entry.id)]
            + items.map { URLQueryItem(name: "path", value: $0.path) }
            + [URLQueryItem(name: "token", value: Self.token)]
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
