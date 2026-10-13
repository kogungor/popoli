import AppKit
import Carbon.HIToolbox
import Sparkle
import SwiftUI
import Translation

/// Shared app-wide objects.
enum Popoli {
    static var registry: ActionRegistry!
    static var bar: BarController!
    static var result: ResultController!
    static var monitor: SelectionMonitor!
    /// nil in builds without an update feed (no SUPublicEDKey), e.g. local development builds.
    static var updater: SPUUpdater?
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var delegate: AppDelegate?

    private var statusItem: NSStatusItem!
    private var updaterController: SPUStandardUpdaterController?
    private var permissionTimer: Timer?

    static func main() {
        // Writing to an extension that stopped reading must not kill Popoli.
        signal(SIGPIPE, SIG_IGN)
        if CLI.run(CommandLine.arguments) { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        Keyboard.refreshLayout()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { _ in Keyboard.refreshLayout() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            AX.primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? AX.primaryScreenHeight
        }

        ExtensionStore.seedExamplesIfNeeded()
        ExtensionStore.writeGuide()
        Popoli.registry = ActionRegistry()
        Popoli.registry.reload()
        Popoli.bar = BarController()
        Popoli.result = ResultController()

        setUpStatusItem()
        Popoli.monitor = SelectionMonitor()
        Popoli.monitor.start()
        Hotkey.shared.onPress = { Popoli.monitor.showForShortcut() }
        Hotkey.shared.install()
        startUpdater()
        Languages.shared.load()
        // Settings change from the menu and the Settings window alike.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            if !Settings.enabled { Popoli.bar.hide() }
            self?.updateStatusIcon()
        }

        if CommandLine.arguments.contains("--demo") { Demo.show(); return }
        if !AXIsProcessTrusted() { requestAccessibility() }
    }

    /// Handles popoli:// URLs from the Finder menu.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "popoli" { handle(url) }
    }

    private func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let path = items.first(where: { $0.name == "path" })?.value else { return }
        switch url.host {
        case "terminal": TerminalLauncher.open(path: path)
        default: break
        }
    }

    // MARK: Updates

    /// Sparkle checks the appcast (SUFeedURL) for signed updates. Builds without the update
    /// signing key (SUPublicEDKey) skip it entirely, so development builds never try to update.
    private func startUpdater() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController = controller
        Popoli.updater = controller.updater
    }

    @objc private func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    // MARK: Accessibility permission

    private func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.updateStatusIcon()
            }
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    /// The logo glyph; dimmed while Popoli is switched off or lacks Accessibility access.
    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        if button.image == nil { button.image = StatusIcon.image() }
        button.appearsDisabled = !(Settings.enabled && AXIsProcessTrusted())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let header = NSMenuItem(title: "Popoli \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !AXIsProcessTrusted() {
            menu.addItem(item("Allow Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Enabled", #selector(toggleEnabled), state: Settings.enabled))
        // The app in front stays in front while this menu is open (Popoli never activates).
        if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let entry = item("Don’t Show in \(app.localizedName ?? id)", #selector(toggleExcluded(_:)),
                             state: Settings.excludedApps.contains(id))
            entry.representedObject = id
            menu.addItem(entry)
        }
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("New Extension…", #selector(newExtension)))
        menu.addItem(item("Extension Guide…", #selector(openGuide)))
        if updaterController != nil {
            menu.addItem(.separator())
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Popoli", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, state: Bool? = nil, key: String = "",
                      target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let state { item.state = state ? .on : .off }
        return item
    }

    @objc private func toggleEnabled() {
        Settings.enabled.toggle()
    }

    @objc private func toggleExcluded(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if Settings.excludedApps.contains(id) {
            Settings.excludedApps.removeAll { $0 == id }
        } else {
            Settings.excludedApps.append(id)
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openGuide() {
        SettingsWindowController.shared.show(.guide)
    }

    @objc private func newExtension() {
        SettingsWindowController.shared.model.newExtension()
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Command line helpers (for testing without the UI)

enum CLI {
    /// Returns true when a CLI command was handled and the app should exit.
    static func run(_ args: [String]) -> Bool {
        guard args.count >= 2 else { return false }
        switch args[1] {
        case "--list-extensions":
            let folder = args.count > 2 ? URL(fileURLWithPath: args[2]) : ExtensionStore.folder
            Keyboard.refreshLayout()
            for ext in ExtensionStore.loadAll(from: folder) {
                print("\(ext.ext == nil ? "✗" : "✓") \(ext.file.lastPathComponent): \(ext.name)\(ext.problem.map { " — \($0)" } ?? "")")
            }
            return true
        case "--define":
            print(Definitions.define(args.dropFirst(2).joined(separator: " ")) ?? "(no definition)")
            return true
        case "--parse-key":
            Keyboard.refreshLayout()
            print(Keyboard.parse(string: args.dropFirst(2).joined(separator: " ")).map(\.description) ?? "(invalid)")
            return true
        case "--exec":
            // --exec <extension file> <text>: runs an extension on <text> without the UI
            // (link extensions print their URL instead of opening it). For `for: files`
            // extensions, the remaining arguments are the file paths.
            Settings.registerDefaults()
            Keyboard.refreshLayout()
            let info = ExtensionStore.load(URL(fileURLWithPath: args[2]))
            guard let ext = info.ext else { print("error: \(info.problem ?? "?")"); return true }
            var ctx = SelectionContext()
            let rest = Array(args.dropFirst(3))
            if ext.target == .files { ctx.files = rest } else { ctx.text = rest.joined(separator: " ") }
            ctx.fullText = ctx.text
            ctx.canCopy = true
            ctx.canPaste = true
            guard let c = ext.prepare(ctx) else { print("\(ext.name): not applicable"); return true }
            if let url = ext.resolvedURL(c) { print("\(ext.name): open \(url.absoluteString)"); return true }
            if case .keys(let combos) = ext.kind { print("\(ext.name): press \(combos)"); return true }
            ext.run(c) { result in
                switch result {
                case .success(let output): print("\(ext.name) [after: \(ext.after?.rawValue ?? "show")]: \(output)")
                case .failure(let error): print("\(ext.name): error: \(error.message)")
                }
                exit(0)
            }
            RunLoop.main.run()
            return true
        case "--render-icons":
            let folder = URL(fileURLWithPath: args.count > 2 ? args[2] : ".")
            for scale in [1, 2, 8] {
                let size = NSSize(width: 18 * scale, height: 18 * scale)
                let icon = StatusIcon.image()
                let image = NSImage(size: size, flipped: false) { rect in
                    icon.draw(in: rect)
                    return true
                }
                if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appendingPathComponent("status-icon@\(scale)x.png"))
                }
            }
            return true
        case "--html-to-md":
            let html = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            print(HTMLToMarkdown.convert(html) ?? "(could not parse)")
            return true
        case "--md-to-html":
            let markdown = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            print(MarkdownToHTML.convert(markdown))
            return true
        case "--keychain-selftest":
            // Writes, reads and deletes a throwaway item.
            let name = "POPOLI_SELFTEST_\(UUID().uuidString.prefix(8))"
            let wrote = Keychain.set("s3cret", for: name)
            let read = Keychain.get(name)
            Keychain.delete(name)
            print("write: \(wrote), read back: \(read == "s3cret"), deleted: \(!Keychain.has(name))")
            return true
        case "--terminal-folder":
            print(TerminalLauncher.folder(for: args.dropFirst(2).joined(separator: " "))?.path ?? "(none)")
            return true
        case "--translate":
            Translate.runCLI(args.dropFirst(2).joined(separator: " "))
            return true
        default:
            return false
        }
    }
}

enum Translate {
    static func runCLI(_ text: String) {
        Settings.registerDefaults()
        Task {
            let source = Translator.detect(text)
            let target = Locale.Language(identifier: Translator.targetCode(for: source))
            let status = source != nil ? await LanguageAvailability().status(from: source!, to: target) : .unsupported
            print("source: \(source?.minimalIdentifier ?? "?") target: \(target.minimalIdentifier) status: \(status)")
            if status == .installed, let source {
                do {
                    let response = try await TranslationSession(installedSource: source, target: target).translate(text)
                    print(response.targetText)
                } catch {
                    print("error: \(error)")
                }
            }
            exit(0)
        }
        RunLoop.main.run()
    }
}

/// `Popoli --demo` shows the bar and a translation card with sample data. With
/// POPOLI_SNAPSHOT_DIR set, it also opens each Settings tab, writes PNGs of all windows
/// (over a sample background, since glass is composited by the window server) and quits.
enum Demo {
    static func show() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var ctx = SelectionContext()
        ctx.text = "serendipity"
        ctx.fullText = ctx.text
        ctx.canCut = true
        ctx.canCopy = true
        ctx.canPaste = true
        ctx.anchor = NSRect(x: screen.midX, y: screen.midY + 140, width: 0, height: 20)
        Popoli.bar.show(Popoli.registry.entries(for: ctx), anchor: ctx.anchor)

        var card = ctx
        card.text = "Good morning, how are you today?"
        card.anchor = NSRect(x: screen.midX, y: screen.midY - 60, width: 0, height: 20)
        Popoli.result.showTranslation(card)

        guard let dir = ProcessInfo.processInfo.environment["POPOLI_SNAPSHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            snapshot(Popoli.bar.window, to: folder.appendingPathComponent("bar.png"))
            snapshot(Popoli.result.window, to: folder.appendingPathComponent("result.png"))
            let settings = SettingsWindowController.shared
            let tabs: [(SettingsModel.Tab, String)] = [(.translate, "translate"), (.general, "general"), (.buttons, "buttons"), (.guide, "guide")]
            for (i, (tab, name)) in tabs.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.0) {
                    settings.show(tab)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if let window = settings.window {
                            snapshot(window, to: folder.appendingPathComponent("settings-\(name).png"))
                        }
                    }
                }
            }
            // The Guide tab scrolls, which the snapshot cannot capture: also draw its full content.
            let guide = NSHostingView(rootView: GuideContent(model: settings.model).frame(width: 560))
            guide.appearance = NSAppearance(named: .aqua)
            let holder = NSWindow(contentRect: NSRect(origin: .zero, size: guide.fittingSize), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            holder.contentView = guide
            guide.frame = NSRect(origin: .zero, size: guide.fittingSize)
            snapshot(holder, to: folder.appendingPathComponent("guide-content.png"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { NSApp.terminate(nil) }
        }
    }

    private static func snapshot(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let size = view.bounds.size
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemIndigo, .systemTeal, .systemOrange])?.draw(in: rect, angle: 30)
            rep.draw(in: rect)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
