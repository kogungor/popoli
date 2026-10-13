import Cocoa
import FinderSync

/// Finder Sync extension that adds "Open in Terminal" and "Copy Path" to Finder's
/// right-click menu, both for selected items and for a window's background.
///
/// The extension is sandboxed, so it does not launch Terminal itself: it hands the
/// folder to the Popoli app through a popoli://terminal URL.
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
        menu.addItem(item("Open in Terminal", symbol: "terminal", action: #selector(openTerminal(_:))))
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

    @objc func openTerminal(_ sender: AnyObject?) {
        guard let target = targets().first else { return }
        var components = URLComponents()
        components.scheme = "popoli"
        components.host = "terminal"
        components.queryItems = [URLQueryItem(name: "path", value: target.path)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    @objc func copyPath(_ sender: AnyObject?) {
        let paths = targets().map(\.path)
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }
}
