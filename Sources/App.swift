import AppKit
import Carbon.HIToolbox
import Sparkle
import SwiftUI
import Translation
import UserNotifications

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
    /// A version found by a scheduled update check that the user hasn't looked at yet.
    private var availableUpdate: String?
    /// A version Sparkle downloaded on its own (automatic downloads): it installs when Popoli
    /// quits, or right away with `install`.
    private var downloadedUpdate: (version: String, install: () -> Void)?
    private static let updateNotification = "update"

    static func main() {
        // Writing to an extension that stopped reading must not kill Popoli.
        signal(SIGPIPE, SIG_IGN)
        if CLI.run(CommandLine.arguments) { return }
        // The demo takes snapshots next to the Popoli you are using.
        if !CommandLine.arguments.contains("--demo"), !SingleInstance.claim() { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CommandLine.arguments.contains("--demo") {
            SingleInstance.listen()
            SingleInstance.keepOwnFinderExtension()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { SingleInstance.refreshOutdatedFinderExtension() }
        }
        Settings.registerDefaults()
        Settings.excludePasswordManagers()
        CardWebView.compileRules()
        Keyboard.refreshLayout()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { _ in Keyboard.refreshLayout() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            AX.primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? AX.primaryScreenHeight
        }

        // Before the first launch creates the extensions folder: a new install gets no "What's new".
        WhatsNew.wasInstalled = FileManager.default.fileExists(atPath: ExtensionStore.folder.path)
        ExtensionStore.seedExamplesIfNeeded()
        ExtensionStore.writeGuide()
        Collections.shared.load()
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
        OpenIn.refresh()
        // Settings change from the menu and the Settings window alike.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            if !Settings.enabled { Popoli.bar.hide() }
            self?.updateStatusIcon()
        }

        if CommandLine.arguments.contains("--demo") { Demo.show(); return }
        // From the disk image, moving comes first: the permission follows the app either way.
        if MoveToApplications.offerIfNeeded() { return }
        if !AXIsProcessTrusted() { requestAccessibility() }
        WhatsNew.showIfUpdated()
    }

    /// Opening Popoli again while it runs (from Finder, Launchpad or Spotlight) shows Settings:
    /// a menu bar app has no window to bring forward otherwise.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// popoli:// links (Finder menu, install links) and extension files opened with Popoli.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "popoli" {
                handle(url)
            } else if url.isFileURL {
                ExtensionInstaller.reviewFile(url)
            }
        }
    }

    /// popoli://terminal?path=… and popoli://open-in?target=… (Finder menu),
    /// popoli://install?url=https://… (share links), and popoli://collections.
    private func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "terminal":
            // Only Popoli's Finder extension knows the token: any web page or app can open
            // popoli:// links, and a terminal in a folder they choose can run that folder's code
            // (a shell prompt runs git there, and a repository's config can run commands).
            guard let path = value("path"), let token = value("token"), TerminalLauncher.isFinderToken(token) else {
                NSLog("Popoli: ignored a terminal link that didn't come from the Finder menu")
                return
            }
            TerminalLauncher.open(path: path)
        case "install":
            if let link = value("url").flatMap(URL.init(string:)) { ExtensionInstaller.reviewLink(link) }
        case "open-in":
            OpenIn.handle(items)
        case "collections":
            CollectionsWindow.show()
        default:
            break
        }
    }

    // MARK: Updates

    /// Sparkle checks the appcast (SUFeedURL) for signed updates. Builds without the update
    /// signing key (SUPublicEDKey) skip it entirely, so development builds never try to update.
    private func startUpdater() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else { return }
        UNUserNotificationCenter.current().delegate = self
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        updaterController = controller
        Popoli.updater = controller.updater
    }

    @objc private func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    @objc private func installDownloadedUpdate() {
        downloadedUpdate?.install()
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

    /// The logo glyph; dimmed while Popoli is switched off or lacks Accessibility access, with
    /// a dot while an update is waiting.
    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        StatusIcon.setBadge(availableUpdate != nil || downloadedUpdate != nil, on: button)
        button.appearsDisabled = !(Settings.enabled && AXIsProcessTrusted())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let header = NSMenuItem(title: "Popoli \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let version = downloadedUpdate?.version {
            menu.addItem(item("Install Popoli \(version) and Restart", #selector(installDownloadedUpdate)))
        } else if let version = availableUpdate {
            menu.addItem(item("Update to Popoli \(version)…", #selector(checkForUpdates)))
        }
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
        menu.addItem(item("Collections…", #selector(showCollections)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("New Extension…", #selector(newExtension)))
        menu.addItem(item("Install Extension…", #selector(installExtension)))
        menu.addItem(item("Extension Guide…", #selector(openGuide)))
        menu.addItem(item("What’s New…", #selector(showWhatsNew)))
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

    @objc private func showCollections() {
        CollectionsWindow.show()
    }

    @objc private func installExtension() {
        InstallPrompt.run()
    }

    @objc private func showWhatsNew() {
        WhatsNew.showLatest()
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

// MARK: - Update reminders

/// Popoli lives in the menu bar, so an update window that opens on its own lands behind other
/// windows and goes unnoticed. When a scheduled check finds an update, Popoli puts a dot on its
/// menu bar icon and "Update to Popoli …" at the top of its menu, and posts a notification once
/// per version; the menu item and the notification open Sparkle's window in front. With
/// automatic downloads, the downloaded version waits for Popoli to quit, which a menu bar app
/// rarely does, so the menu offers to install it and restart.
extension AppDelegate: SPUUpdaterDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Right after launch, or when the Mac was idle, Sparkle shows its window in front anyway.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        availableUpdate = update.displayVersionString
        updateStatusIcon()
        if !handleShowingUpdate { postUpdateNotification(version: update.displayVersionString, downloaded: false) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.updateNotification])
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableUpdate = nil
        updateStatusIcon()
    }

    /// Automatic downloads: Popoli takes over installing (returns true) so it can offer it now.
    /// Quitting still installs it.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        downloadedUpdate = (item.displayVersionString, immediateInstallHandler)
        updateStatusIcon()
        postUpdateNotification(version: item.displayVersionString, downloaded: true)
        return true
    }

    /// Once per version, so a check every hour doesn't repeat it. macOS asks for permission the
    /// first time; without it, the dot and the menu item still show.
    private func postUpdateNotification(version: String, downloaded: Bool) {
        let key = "updateNotified"
        let mark = downloaded ? "\(version) downloaded" : version
        guard UserDefaults.standard.string(forKey: key) != mark else { return }
        UserDefaults.standard.set(mark, forKey: key)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            if downloaded {
                content.title = "Popoli \(version) is ready"
                content.body = "Click to restart Popoli with the new version. It also installs when you quit Popoli."
            } else {
                content.title = "Popoli \(version) is available"
                content.body = "Click to see what’s new and install it."
            }
            center.add(UNNotificationRequest(identifier: Self.updateNotification, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == Self.updateNotification {
            DispatchQueue.main.async {
                if let update = self.downloadedUpdate { update.install() } else { self.checkForUpdates() }
            }
        }
        completionHandler()
    }

    /// Show the banner even if a Popoli window (Settings) is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
                let icon = StatusIcon.plain
                let image = NSImage(size: size, flipped: false) { rect in
                    icon.draw(in: rect)
                    return true
                }
                if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appendingPathComponent("status-icon@\(scale)x.png"))
                }
            }
            return true
        case "--open-in":
            // --open-in: the editors and AI tools Open in › finds on this Mac.
            DispatchQueue.global().async {
                let (apps, commands) = OpenIn.installed()
                for target in apps + commands {
                    print("\(target.isCommand ? "command" : "app    ")  \(target.name)  (\(target.id))")
                }
                exit(0)
            }
            RunLoop.main.run()
            return true
        case "--open-in-bar", "--open-in-run":
            // --open-in-bar <path>…: the Open in › buttons the bar would show for these Finder items.
            // --open-in-run <id> <path>…: opens them with one of the targets turned on in Settings.
            Settings.registerDefaults()
            let paths = Array(args.dropFirst(args[1] == "--open-in-run" ? 3 : 2)).map { URL(fileURLWithPath: $0).path }
            OpenIn.refresh {
                if args[1] == "--open-in-bar" {
                    var ctx = SelectionContext()
                    ctx.files = paths
                    for action in OpenIn.actions where action.prepare(ctx) != nil { print(action.title) }
                    exit(0)
                }
                guard Settings.openInEnabled.contains(args[2]), let target = OpenInTarget(id: args[2]) else {
                    print("not turned on in Settings: \(args[2])"); exit(1)
                }
                OpenIn.open(target, paths: paths)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
            }
            RunLoop.main.run()
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
        case "--install-check":
            // Reads extension text from stdin and prints what the review window would show.
            Keyboard.refreshLayout()
            let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            let candidate = ExtensionInstaller.candidate(text: text, suggestedFileName: args.count > 2 ? args[2] : nil, origin: "stdin")
            print("looks like an extension: \(ExtensionInstaller.looksLikeExtension(text))")
            print("file name: \(candidate.fileName)")
            if let ext = candidate.ext {
                print("name: \(ext.name)")
                ExtensionInstaller.warnings(in: candidate.contents, for: ext).forEach { print("\($0.level == .danger ? "!!" : "!") \($0.text)") }
                ExtensionInstaller.facts(about: ext).forEach { print("- \($0.text)") }
            } else {
                print("problem: \(candidate.problem ?? "?")")
            }
            return true
        case "--fetch-check":
            // Downloads like popoli://install does and prints what would be installed.
            Keyboard.refreshLayout()
            ExtensionInstaller.fetch(URL(string: args[2])!) { result in
                switch result {
                case .success(let (text, finalURL)):
                    let candidate = ExtensionInstaller.candidate(text: text, suggestedFileName: finalURL.lastPathComponent, origin: args[2])
                    print("fetched \(text.utf8.count) bytes from \(finalURL.absoluteString)")
                    print("file name: \(candidate.fileName), name: \(candidate.ext?.name ?? "-"), problem: \(candidate.problem ?? "none")")
                case .failure(let error):
                    print("error: \(error.message)")
                }
                exit(0)
            }
            RunLoop.main.run()
            return true
        case "--secret-access-selftest":
            // A saved secret goes only to extensions allowed to have it, and only while unchanged.
            let name = "POPOLI_SELFTEST_SECRET"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).sh")
            let script = "#!/bin/zsh\n# name: Self Test\n# secret: \(name)\n\nprint ok\n"
            try? script.write(to: file, atomically: true, encoding: .utf8)
            _ = Keychain.set("s3cret", for: name)
            guard let ext = try? ExtensionStore.parse(file) else { print("parse failed"); return true }
            print("allowed before asking: \(SecretAccess.isAllowed(ext, name))")
            SecretAccess.allow(ext, name)
            print("allowed after allowing: \(SecretAccess.isAllowed(ext, name))")
            try? (script + "# changed\n").write(to: file, atomically: true, encoding: .utf8)
            print("allowed after the file changed: \(SecretAccess.isAllowed(ext, name))")
            Keychain.delete(name)
            SecretAccess.forget(name)
            try? FileManager.default.removeItem(at: file)
            return true
        case "--clipboard-selftest":
            // A concealed password must not come back after the ⌘C round trip; other content must.
            let pb = NSPasteboard.general
            let original = Clipboard.snapshot(pb)
            pb.clearContents()
            pb.setString("hunter2", forType: .string)
            pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            Clipboard.restore(Clipboard.snapshot(pb), to: pb)
            print("concealed password put back: \(pb.string(forType: .string) != nil)")
            pb.clearContents()
            pb.setString("plain text", forType: .string)
            Clipboard.restore(Clipboard.snapshot(pb), to: pb)
            print("plain text put back: \(pb.string(forType: .string) == "plain text"), marked auto-generated: \(pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")) == true)")
            Clipboard.restore(original, to: pb)
            return true
        case "--catalog-index":
            // Prints catalog/index.json for a catalog folder; CI checks the committed one matches.
            Keyboard.refreshLayout()
            do {
                print(try Catalog.json(Catalog.index(of: URL(fileURLWithPath: args.count > 2 ? args[2] : "catalog"))), terminator: "")
            } catch {
                FileHandle.standardError.write("error: \((error as? ExtensionError)?.message ?? error.localizedDescription)\n".data(using: .utf8)!)
                exit(1)
            }
            return true
        case "--browser-tab":
            // What $POPOLI_BROWSER_URL and $POPOLI_BROWSER_TITLE would be for this browser.
            guard args.count > 2, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first else {
                print("usage: --browser-tab <bundle id of a running browser>")
                return true
            }
            BrowserTab.current(in: app) { page in
                print(page.map { "url: \($0.url)\ntitle: \($0.title)" } ?? "not a browser Popoli knows, or no page")
                exit(0)
            }
            RunLoop.main.run()
            return true
        case "--raw-url":
            print(ExtensionInstaller.rawURL(for: URL(string: args[2])!).absoluteString)
            return true
        case "--collect-source":
            // --collect-source <bundle id>: which collection a selection in that app would go to.
            guard args.count > 2, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first else {
                print("usage: --collect-source <bundle id of a running app>")
                return true
            }
            let source = SnippetSource.read(app)
            print("key: \(source.key)\ntitle: \(source.title)\nurl: \(source.url ?? "-")")
            return true
        case "--collections-selftest":
            Collections.selfTest()
            return true
        case "--is-control":
            // --is-control <x> <y> (screen points, top-left origin): whether a press there counts as
            // a press on a control, where a drag doesn't select text.
            guard args.count > 3, let x = Double(args[2]), let y = Double(args[3]) else {
                print("usage: --is-control <x> <y>")
                return true
            }
            let point = NSPoint(x: x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - y)
            print(AX.isControl(at: point, roles: SelectionMonitor.nonTextRoles) ? "control" : "text")
            return true
        case "--text-fragment":
            // --text-fragment <url> <text>: the link Collections opens a snippet's page with.
            print(TextFragment.link(args[2], text: args.dropFirst(3).joined(separator: " "))?.absoluteString ?? "(none)")
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
            // One tab after the other: opening the window the first time takes a moment.
            func capture(_ index: Int) {
                guard index < tabs.count else { return }
                let (tab, name) = tabs[index]
                settings.show(tab)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if let window = settings.window {
                        snapshot(window, to: folder.appendingPathComponent("settings-\(name).png"))
                    }
                    capture(index + 1)
                }
            }
            capture(0)
            // The Guide tab scrolls, which the snapshot cannot capture: also draw its full content.
            let guide = NSHostingView(rootView: GuideContent(model: settings.model).frame(width: 560))
            guide.appearance = NSAppearance(named: .aqua)
            let holder = NSWindow(contentRect: NSRect(origin: .zero, size: guide.fittingSize), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            holder.contentView = guide
            guide.frame = NSRect(origin: .zero, size: guide.fittingSize)
            snapshot(holder, to: folder.appendingPathComponent("guide-content.png"))
            // The install review window, with a bundled extension.
            if let url = Bundle.main.resourceURL?.appendingPathComponent("Extensions/improve-writing.sh"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                    ExtensionInstaller.reviewSelection(text, appName: "Safari")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if let window = NSApp.windows.first(where: { $0.title == "Install Extension" }) {
                            window.appearance = NSAppearance(named: .aqua)
                            window.contentView?.layoutSubtreeIfNeeded()
                            snapshot(window, to: folder.appendingPathComponent("install-review.png"))
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) { NSApp.terminate(nil) }
        }
    }

    private static func snapshot(_ window: NSWindow, to url: URL) {
        // The frame view includes the title bar and toolbar of titled windows.
        let frameView = window.styleMask.contains(.titled) ? window.contentView?.superview : nil
        guard let view = frameView ?? window.contentView,
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
