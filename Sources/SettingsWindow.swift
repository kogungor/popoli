import AppKit
import Combine
import FinderSync
import ServiceManagement
import Sparkle
import SwiftUI

/// Opens files in the user's default text editor, never in the file's default app:
/// a .sh file might otherwise open in Terminal and run.
enum Editor {
    static func open(_ url: URL) {
        let workspace = NSWorkspace.shared
        if let editor = workspace.urlForApplication(toOpen: .plainText) {
            workspace.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.activateFileViewerSelecting([url])
        }
    }
}

/// The Settings window, in the macOS style: tabs as toolbar icons, the window titled after
/// the selected tab and resized to fit it.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    let model = SettingsModel()
    let catalog = CatalogModel()
    private(set) var window: NSWindow?
    private var tabs: NSTabViewController?
    private var tabObserver: AnyCancellable?
    private var statusTimer: Timer?

    private static let order: [SettingsModel.Tab] = [.general, .buttons, .catalog, .translate, .guide]

    func show(_ tab: SettingsModel.Tab? = nil) {
        if window == nil { makeWindow() }
        if let tab { model.tab = tab }
        model.refresh()
        if let window, !window.isVisible, let tabs, let size = tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController?.preferredContentSize {
            // Open at the selected tab's size instead of growing into it.
            window.setContentSize(size)
            window.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        startStatusPolling()
    }

    /// Opens the settings sheet of one extension (e.g. when it needs an API key).
    func showSettings(forExtension id: String) {
        show(.buttons)
        model.editing = model.rows.first { $0.id == id }
    }

    private func makeWindow() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        tabs.addTabViewItem(item("General", "gearshape", height: 600, GeneralTab(model: model)))
        tabs.addTabViewItem(item("Buttons", "square.grid.3x1.below.line.grid.1x2", height: 540, ButtonsTab(model: model)))
        tabs.addTabViewItem(item("Catalog", "puzzlepiece.extension", height: 600, CatalogTab(catalog: catalog, model: model)))
        tabs.addTabViewItem(item("Translate", "translate", height: 300, TranslateTab()))
        tabs.addTabViewItem(item("Guide", "book", height: 620, GuideTab(model: model)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        self.tabs = tabs

        // Buttons inside the tabs (e.g. "Guide") switch tabs through the model.
        tabObserver = model.$tab.sink { [weak self] tab in
            guard let index = Self.order.firstIndex(of: tab), self?.tabs?.selectedTabViewItemIndex != index else { return }
            self?.tabs?.selectedTabViewItemIndex = index
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                               queue: .main) { [weak self] _ in self?.model.refresh() }
    }

    private func item<Content: View>(_ label: String, _ symbol: String, height: CGFloat, _ view: Content) -> NSTabViewItem {
        // The tab controller sizes the window from each tab's preferred size, not from the SwiftUI frame.
        let size = NSSize(width: 560, height: height)
        let controller = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
        controller.sizingOptions = []
        controller.preferredContentSize = size
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    /// System switches the user may flip in System Settings, re-read while the window is open.
    private func startStatusPolling() {
        guard statusTimer == nil else { return }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.model.refreshStatus()
        }
    }

    func windowWillClose(_ notification: Notification) {
        statusTimer?.invalidate()
        statusTimer = nil
    }
}

// MARK: - Model

final class SettingsModel: ObservableObject {
    enum Tab: Hashable { case general, buttons, catalog, translate, guide }

    struct Row: Identifiable {
        let id: String
        let title: String
        let icon: NSImage?
        let detail: String
        let file: URL?
        let problem: String?
        var enabled: Bool
        var ext: UserExtension?
    }

    @Published var tab = Tab.general
    @Published var rows: [Row] = []
    /// The extension whose settings sheet is open.
    @Published var editing: Row?
    @Published var excludedApps = Settings.excludedApps
    @Published var finderMenuOn = false
    @Published var accessibilityAllowed = false
    @Published var launchAtLogin = false
    /// Set while a Finder menu change is being applied, so polling does not flip the switch back.
    private var finderChangePending = false

    /// Re-reads everything that can change outside the window (extension files, system settings).
    func refresh() {
        rows = Popoli.registry.items().map { item in
            Row(id: item.id, title: item.title, icon: item.icon,
                detail: item.detail, file: item.file, problem: item.problem,
                enabled: Settings.isEnabled(item.id), ext: item.ext)
        }
        excludedApps = Settings.excludedApps
        refreshStatus()
    }

    func addExcludedApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        Settings.excludedApps = Array(Set(Settings.excludedApps + ids)).sorted()
        excludedApps = Settings.excludedApps
    }

    func removeExcludedApp(_ id: String) {
        Settings.excludedApps.removeAll { $0 == id }
        excludedApps = Settings.excludedApps
    }

    /// System switches the user flips in System Settings; polled while the window is open.
    /// The checks talk to system services, so they run off the main thread.
    func refreshStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let finder = FIFinderSyncController.isExtensionEnabled
            let trusted = AXIsProcessTrusted()
            let login = SMAppService.mainApp.status == .enabled
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.finderChangePending && finder != self.finderMenuOn { self.finderMenuOn = finder }
                if trusted != self.accessibilityAllowed { self.accessibilityAllowed = trusted }
                if login != self.launchAtLogin { self.launchAtLogin = login }
            }
        }
    }

    func setEnabled(_ id: String, _ on: Bool) {
        Settings.setEnabled(id, on)
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].enabled = on }
    }

    func move(from source: IndexSet, to destination: Int) {
        rows.move(fromOffsets: source, toOffset: destination)
        Settings.buttonOrder = rows.map(\.id)
    }

    /// Creates an extension file from an example in the guide and opens it.
    func useExample(_ example: ExtensionGuide.Example) {
        do {
            Editor.open(try ExtensionStore.create(file: example.file, contents: example.code + "\n"))
            refresh()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func newExtension() {
        do {
            Editor.open(try ExtensionStore.createNew())
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Turns the Finder right-click menu on or off. This is the same switch as in
    /// System Settings ▸ General ▸ Login Items & Extensions, so the two stay in sync.
    func setFinderMenu(_ on: Bool) {
        finderMenuOn = on
        finderChangePending = true
        Runner.run(executable: URL(fileURLWithPath: "/usr/bin/pluginkit"),
                   arguments: ["-e", on ? "use" : "ignore", "-i", "app.popoli.Popoli.FinderMenu"],
                   input: nil, environment: [:], directory: FileManager.default.temporaryDirectory,
                   timeout: 10) { [weak self] result in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.finderChangePending = false
                self?.refreshStatus()
            }
            if case .failure(let error) = result {
                let alert = NSAlert()
                alert.messageText = "Couldn’t change the Finder menu"
                alert.informativeText = "\(error.message)\n\nYou can switch it in System Settings instead."
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Views

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @AppStorage("enabled") private var enabled = true
    @AppStorage("finderFiles") private var finderFiles = true
    @AppStorage("barStyle") private var barStyle = "dark"
    @AppStorage("terminalApp") private var terminalApp = "com.apple.Terminal"
    @AppStorage("pasteOnEmptyField") private var pasteOnEmptyField = true
    @AppStorage("diagnostics") private var diagnostics = false
    @AppStorage("keepCollections") private var keepCollections = true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Popoli").font(.title2.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Toggle("Show the bar when text is selected", isOn: $enabled)
                Toggle("Show the bar for files selected in Finder", isOn: $finderFiles)
                Toggle(isOn: $pasteOnEmptyField) {
                    Text("Offer Paste in empty text fields")
                    Text("Clicking into an empty text field shows a bar with just Paste.")
                }
                LabeledContent {
                    ShortcutRecorder()
                } label: {
                    Text("Keyboard shortcut")
                    Text("Shows the bar for the current selection, even in the apps below.")
                }
                Picker("Style", selection: $barStyle) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented)
            }
            Section("Finder") {
                Toggle(isOn: Binding(get: { model.finderMenuOn }, set: { model.setFinderMenu($0) })) {
                    Text("Right-click menu")
                    Text("Adds Open in Terminal and Copy Path when you right-click in Finder.")
                }
                Picker("Open in Terminal uses", selection: $terminalApp) {
                    ForEach(TerminalLauncher.installed) { Text($0.name).tag($0.id) }
                }
            }
            OpenInSection()
            Section("Collections") {
                Toggle(isOn: $keepCollections) {
                    Text("Keep collections when Popoli quits")
                    Text("Saved on this Mac only. A collection is deleted 7 days after you last add to it, unless it collects everything. When off, collections are forgotten when Popoli quits or updates.")
                }
                .onChange(of: keepCollections) { Collections.shared.save() }
                Button("Show Collections…") { CollectionsWindow.show() }
            }
            Section {
                ForEach(model.excludedApps, id: \.self) { id in
                    HStack {
                        AppLabel(bundleID: id)
                        Spacer()
                        Button { model.removeExcludedApp(id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Show the bar in this app again")
                    }
                }
                Button("Add App…", action: model.addExcludedApps)
            } header: {
                Text("Don’t show the bar in")
            } footer: {
                Text("You can also use “Don’t Show in …” in the menu bar menu while an app is in front.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            UpdatesSection()
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                LabeledContent("Accessibility access") {
                    if model.accessibilityAllowed {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else {
                        Button("Allow…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Toggle(isOn: $diagnostics) {
                    Text("Diagnostics log")
                    Text("Notes how each selection was read and which buttons showed, to report a problem with an app. It never contains the selected text.")
                }
                if diagnostics {
                    Button("Show Log in Finder") { Diagnostics.reveal() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ButtonsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose which buttons appear on the bar. Drag to change their order, here or with ⌘ held on the bar itself. Drop an extension file here to install it.")
                .foregroundStyle(.secondary)
            List {
                ForEach(model.rows) { row in
                    ButtonRowView(row: row, model: model)
                }
                .onMove(perform: model.move)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            // Drop an extension file on the list to review and install it.
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { ExtensionInstaller.reviewFile(url) } }
                }
                return true
            }
            HStack {
                Button("New Extension…", action: model.newExtension)
                Button("Install…") { InstallPrompt.run() }
                Button("Open Folder") {
                    try? FileManager.default.createDirectory(at: ExtensionStore.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(ExtensionStore.folder)
                }
                .help("Open ~/.config/popoli/extensions in Finder")
                Spacer()
                Button { model.tab = .guide } label: { Label("Guide", systemImage: "book") }
                    .help("How to write extensions")
            }
        }
        .padding(20)
        .sheet(item: $model.editing) { row in
            if let ext = row.ext {
                ExtensionSettingsSheet(ext: ext) { model.editing = nil; model.refresh() }
            }
        }
    }
}

/// Values for an extension's `setting:` lines and its `secret:` keys.
private struct ExtensionSettingsSheet: View {
    let ext: UserExtension
    let done: () -> Void
    @State private var values: [String: String] = [:]
    @State private var newSecrets: [String: String] = [:]
    @State private var savedSecrets: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ext.name).font(.title3.weight(.semibold)).padding(.horizontal, 20).padding(.top, 20)
            Form {
                if !ext.settings.isEmpty {
                    Section("Settings") {
                        ForEach(ext.settings, id: \.name) { setting in
                            TextField(setting.name, text: Binding(get: { values[setting.name] ?? "" },
                                                                  set: { values[setting.name] = $0 }),
                                      prompt: Text(setting.defaultValue))
                        }
                    }
                }
                if !ext.secrets.isEmpty {
                    Section {
                        ForEach(ext.secrets, id: \.self) { name in
                            LabeledContent(name) {
                                HStack {
                                    SecureField("", text: Binding(get: { newSecrets[name] ?? "" }, set: { newSecrets[name] = $0 }),
                                                prompt: Text(savedSecrets.contains(name) ? "Saved in Keychain" : "Paste the key"))
                                        .frame(width: 200)
                                    if savedSecrets.contains(name) {
                                        Button("Remove") { Keychain.delete(name); SecretAccess.forget(name); savedSecrets.remove(name) }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Secrets")
                    } footer: {
                        Text("Stored encrypted in your login keychain, never in the extension file. Every extension that uses the same name shares it. Scripts get it as an environment variable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save") { save(); done() }.keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .onAppear {
            for setting in ext.settings {
                values[setting.name] = Settings.extensionSetting(ext.id, setting.name) ?? setting.defaultValue
            }
            savedSecrets = Set(ext.secrets.filter(Keychain.has))
        }
    }

    private func save() {
        for setting in ext.settings {
            let value = values[setting.name] ?? ""
            Settings.setExtensionSetting(ext.id, setting.name, value == setting.defaultValue ? nil : value)
        }
        for (name, value) in newSecrets where !value.trimmed.isEmpty {
            Keychain.set(value.trimmed, for: name)
            // Typing the key in for this extension is the permission to use it.
            SecretAccess.allow(ext, name)
        }
    }
}

/// An app's icon and name from its bundle ID.
/// Settings ▸ General ▸ Open in: which editors and AI tools Open in › offers.
private struct OpenInSection: View {
    @State private var available = OpenIn.available
    @State private var enabled = Set(Settings.openInEnabled)
    @State private var addingCommand = false
    @State private var command = ""

    var body: some View {
        Section {
            if available.isEmpty {
                Text("Looking for editors and AI tools…").foregroundStyle(.secondary)
            }
            ForEach(available) { target in
                HStack {
                    Toggle(isOn: Binding(get: { enabled.contains(target.id) },
                                         set: { OpenIn.setEnabled(target, $0); reload() })) {
                        OpenInLabel(target: target)
                    }
                    if OpenIn.isAdded(target) {
                        Button { OpenIn.remove(target); reload() } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove from the list")
                    }
                }
            }
            HStack {
                Button("Add App…", action: addApps)
                Button("Add Command…") { command = ""; addingCommand = true }
            }
        } header: {
            Text("Open in")
        } footer: {
            Text("Open in › appears for files and folders selected in Finder, on the bar and in the right-click menu. Commands such as claude start in a new window of the terminal chosen above, in the folder.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            reload()
            OpenIn.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: OpenIn.didChange)) { _ in reload() }
        .alert("Add a Command", isPresented: $addingCommand) {
            TextField("aider --model sonnet", text: $command)
            Button("Add") {
                let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
                if let target = OpenInTarget(id: "command:" + text) { OpenIn.add(target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It runs in a new terminal window in the folder, as if you typed it there.")
        }
    }

    private func reload() {
        available = OpenIn.available
        enabled = Set(Settings.openInEnabled)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            OpenIn.add(OpenInTarget(kind: .app(bundleID), name: OpenIn.displayName(url)))
        }
        reload()
    }
}

private struct OpenInLabel: View {
    let target: OpenInTarget

    var body: some View {
        HStack(spacing: 8) {
            if let url = target.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "terminal").frame(width: 18, height: 18)
            }
            Text(target.name)
            if case .command(let command) = target.kind, command != target.name {
                Text(command).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                .resizable()
                .frame(width: 18, height: 18)
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
        }
    }
}

/// Records the global shortcut: click, then press the keys (with ⌘, ⌥ or ⌃).
private struct ShortcutRecorder: View {
    @State private var shortcut = Settings.hotkey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Press keys…" : (shortcut?.display ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            if shortcut != nil && !recording {
                Button {
                    Settings.hotkey = nil
                    shortcut = nil
                    Hotkey.shared.register()
                } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove the shortcut")
            }
        }
    }

    private func start() {
        recording = true
        Hotkey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if let new = Shortcut(event: event) {
                Settings.hotkey = new
                shortcut = new
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Hotkey.shared.register()
    }
}

/// Sparkle settings, shown when this build has an update feed.
private struct UpdatesSection: View {
    @State private var automaticChecks = Popoli.updater?.automaticallyChecksForUpdates ?? false
    @State private var automaticDownloads = Popoli.updater?.automaticallyDownloadsUpdates ?? false

    var body: some View {
        Section("Updates") {
            if let updater = Popoli.updater {
                Toggle("Check for updates automatically", isOn: Binding(get: { automaticChecks }, set: {
                    automaticChecks = $0
                    updater.automaticallyChecksForUpdates = $0
                }))
                Toggle("Download and install updates automatically", isOn: Binding(get: { automaticDownloads }, set: {
                    automaticDownloads = $0
                    updater.automaticallyDownloadsUpdates = $0
                }))
                .disabled(!automaticChecks)
                Button("Check for Updates Now") { updater.checkForUpdates() }
            } else {
                Text("This build has no update feed. Official releases update themselves.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ButtonRowView: View {
    let row: SettingsModel.Row
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { row.enabled && row.problem == nil },
                                     set: { model.setEnabled(row.id, $0) }))
                .labelsHidden()
                .disabled(row.problem != nil)
            Group {
                if let icon = row.icon {
                    Image(nsImage: icon).renderingMode(icon.isTemplate ? .template : .original)
                } else {
                    Image(systemName: "textformat").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                Text(row.problem ?? row.detail)
                    .font(.caption)
                    .foregroundStyle(row.problem == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                    .help(row.problem ?? row.detail)
            }
            Spacer()
            if row.ext?.hasSettings == true {
                Button("Settings…") { model.editing = row }
                    .buttonStyle(.borderless)
            }
            if let file = row.file {
                Button("Edit") { Editor.open(file) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TranslateTab: View {
    @ObservedObject private var languages = Languages.shared
    @AppStorage("translateSource") private var source = "auto"
    @AppStorage("translateTarget") private var target = Settings.defaultTranslateTarget
    @AppStorage("translateSecondary") private var secondary = Settings.defaultTranslateSecondary

    var body: some View {
        Form {
            Section {
                Picker("Translate from", selection: $source) {
                    Text("Detect automatically").tag("auto")
                    Divider()
                    languageOptions
                }
                Picker("Translate to", selection: $target) { languageOptions }
                Picker("If the text is already in that language", selection: $secondary) { languageOptions }
            } footer: {
                Text("These are the defaults. In the translation card you can change both languages for a single translation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Translation runs on your Mac") {
                    Button("Downloaded Languages…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                    }
                }
            } footer: {
                Text("A language is downloaded the first time you use it. Manage downloads in Language & Region ▸ Translation Languages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var languageOptions: some View {
        ForEach(languages.codes, id: \.self) { Text(Translator.name($0)).tag($0) }
    }
}

// MARK: - Catalog

/// Ready-made extensions from the repository's catalog, like an extension marketplace.
private struct CatalogTab: View {
    @ObservedObject var catalog: CatalogModel
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Search extensions", text: $catalog.search)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $catalog.category) {
                    Text("All").tag("All")
                    ForEach(catalog.categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            switch catalog.state {
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Couldn’t load the catalog").font(.headline)
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") { catalog.load(force: true) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded where catalog.filtered.isEmpty:
                Text("No extensions match “\(catalog.search)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                List(catalog.filtered) { entry in
                    CatalogRow(entry: entry, status: catalog.statuses[entry.file] ?? .notInstalled) { catalog.install(entry) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            default:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text("Every extension shows its code before it installs. Installed ones are in Buttons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Write Your Own") { model.tab = .guide }
            }
        }
        .padding(20)
        .onAppear { catalog.load(); catalog.refreshStatuses() }
    }
}

private struct CatalogRow: View {
    let entry: Catalog.Entry
    let status: CatalogModel.Status
    let install: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let icon = Icons.load(entry.icon, folder: FileManager.default.temporaryDirectory) {
                    Image(nsImage: icon).renderingMode(icon.isTemplate ? .template : .original)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
            }
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name).fontWeight(.semibold)
                    if let group = entry.group {
                        Text(group + " ›")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
                if let description = entry.description {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    if entry.forFiles { Label("Finder files", systemImage: "folder") }
                    if entry.internet { Label("Internet", systemImage: "network") }
                    if !entry.secrets.isEmpty { Label("API key", systemImage: "key") }
                    if !entry.settings.isEmpty { Label("Settings", systemImage: "slider.horizontal.3") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            switch status {
            case .installed:
                Label("Installed", systemImage: "checkmark").foregroundStyle(.secondary).font(.callout)
            case .notInstalled:
                Button("Install", action: install)
            case .update:
                Button("Update", action: install).help("The catalog has a newer version")
            case .changed:
                Button("Replace…", action: install).help("Your copy differs from the catalog; installing replaces it")
            }
        }
        .padding(.vertical, 4)
    }
}
