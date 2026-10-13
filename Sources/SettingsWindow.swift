import AppKit
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

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let model = SettingsModel()
    private(set) var window: NSWindow?

    func show(_ tab: SettingsModel.Tab? = nil) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Popoli Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let tab { model.tab = tab }
        model.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Opens the settings sheet of one extension (e.g. when it needs an API key).
    func showSettings(forExtension id: String) {
        show(.buttons)
        model.editing = model.rows.first { $0.id == id }
    }
}

// MARK: - Model

final class SettingsModel: ObservableObject {
    enum Tab: Hashable { case general, buttons, translate, guide }

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

    /// Built-ins that are plain text on the bar get a symbol in this list.
    private static let listIcons = ["builtin.cut": "scissors", "builtin.copy": "doc.on.doc",
                                    "builtin.paste": "doc.on.clipboard", "builtin.path": "folder"]

    /// Re-reads everything that can change outside the window (extension files, system settings).
    func refresh() {
        rows = Popoli.registry.items().map { item in
            Row(id: item.id, title: item.title, icon: item.icon ?? Self.listIcons[item.id].flatMap(Icons.symbol),
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

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsModel.Tab.general)
            ButtonsTab(model: model)
                .tabItem { Label("Buttons", systemImage: "square.grid.3x1.below.line.grid.1x2") }
                .tag(SettingsModel.Tab.buttons)
            TranslateTab()
                .tabItem { Label("Translate", systemImage: "translate") }
                .tag(SettingsModel.Tab.translate)
            GuideTab(model: model)
                .tabItem { Label("Guide", systemImage: "book") }
                .tag(SettingsModel.Tab.guide)
        }
        .frame(width: 560, height: 520)
        // Only for the Settings window itself: other windows (the menu bar menu, the result
        // card) become key all the time, and refreshing then made the menu bar icon laggy.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow) === SettingsWindowController.shared.window { model.refresh() }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if SettingsWindowController.shared.window?.isVisible == true { model.refreshStatus() }
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @AppStorage("enabled") private var enabled = true
    @AppStorage("finderFiles") private var finderFiles = true
    @AppStorage("barStyle") private var barStyle = "dark"
    @AppStorage("terminalApp") private var terminalApp = "com.apple.Terminal"
    @AppStorage("pasteOnEmptyField") private var pasteOnEmptyField = true

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
            }
        }
        .formStyle(.grouped)
    }
}

private struct ButtonsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose which buttons appear on the bar. Drag to change their order.")
                .foregroundStyle(.secondary)
            List {
                ForEach(model.rows) { row in
                    ButtonRowView(row: row, model: model)
                }
                .onMove(perform: model.move)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Button("New Extension…", action: model.newExtension)
                Button("Open Extensions Folder") {
                    try? FileManager.default.createDirectory(at: ExtensionStore.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(ExtensionStore.folder)
                }
                Spacer()
                Button("How to Write Extensions") { model.tab = .guide }
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
                                        Button("Remove") { Keychain.delete(name); savedSecrets.remove(name) }
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
        }
    }
}

/// An app's icon and name from its bundle ID.
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
    @AppStorage("translateTarget") private var target = "tr"
    @AppStorage("translateSecondary") private var secondary = "en"

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
