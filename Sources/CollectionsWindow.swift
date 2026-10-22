import AppKit
import SwiftUI

/// The Collections window (menu bar ▸ Collections…, or Collected › ▸ Show Collections on the
/// bar): the collections on the left, the snippets of the selected one on the right, with
/// what can be done with them all.
enum CollectionsWindow {
    private static var window: NSWindow?
    private static let selection = CollectionsSelection()

    static func show(_ id: UUID? = nil) {
        let store = Collections.shared
        store.prune()
        if let id {
            selection.id = id
        } else if selection.id == nil || !store.all.contains(where: { $0.id == selection.id }) {
            selection.id = store.active?.id ?? store.all.first?.id
        }
        if window == nil {
            let hosting = NSHostingController(rootView: CollectionsView(store: store, selection: selection))
            let made = NSWindow(contentViewController: hosting)
            made.title = "Collections"
            made.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            made.isReleasedWhenClosed = false
            made.setContentSize(NSSize(width: 780, height: 520))
            made.contentMinSize = NSSize(width: 600, height: 360)
            made.center()
            made.setFrameAutosaveName("Collections")
            window = made
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // From the bar, macOS may keep the app in use in front; the window comes forward anyway.
        window?.orderFrontRegardless()
        // The name field would take the focus and select itself; it's for clicking into.
        DispatchQueue.main.async { window?.makeFirstResponder(nil) }
    }

    /// Where a result card of an extension run on a collection goes: over the window.
    static var anchor: NSRect {
        guard let frame = window?.frame else { return NSRect(x: 400, y: 400, width: 0, height: 20) }
        return NSRect(x: frame.midX, y: frame.midY, width: 0, height: 20)
    }

    /// Opens the page a snippet came from, scrolled to it and highlighted in browsers.
    /// Apps made of web pages (Claude, Slack…) can't be sent to a page, so they come forward.
    static func open(_ snippet: Snippet) {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: snippet.app)
        if let link = snippet.link, let appURL, BrowserTab.isBrowser(snippet.app) || link.isFileURL {
            NSWorkspace.shared.open([link], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let app = NSRunningApplication.runningApplications(withBundleIdentifier: snippet.app).first {
            app.activate()
        } else if let appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let link = snippet.link {
            NSWorkspace.shared.open(link)
        }
    }
}

final class CollectionsSelection: ObservableObject {
    @Published var id: UUID?
}

/// Snippets are dragged between collections as text with this prefix and their ID.
private let snippetDragPrefix = "popoli-snippet:"

private struct CollectionsView: View {
    @ObservedObject var store: Collections
    @ObservedObject var selection: CollectionsSelection

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.id) {
                ForEach(store.all) { collection in
                    CollectionRow(collection: collection, onBar: collection.id == store.activeID)
                        .tag(collection.id)
                        .contextMenu { CollectionMenu(store: store, collection: collection) }
                        .dropDestination(for: String.self) { items, _ in
                            let ids = items.compactMap { $0.hasPrefix(snippetDragPrefix)
                                ? UUID(uuidString: String($0.dropFirst(snippetDragPrefix.count))) : nil }
                            ids.forEach { store.move(snippet: $0, to: collection.id) }
                            return !ids.isEmpty
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            .overlay {
                if store.all.isEmpty {
                    ContentUnavailableView("Nothing Collected", systemImage: "tray",
                                           description: Text("Select text anywhere and click Collect on the bar."))
                }
            }
        } detail: {
            if let collection = store.all.first(where: { $0.id == selection.id }) {
                CollectionDetail(store: store, collection: collection)
            } else {
                ContentUnavailableView("Collect Text as You Read", systemImage: "rectangle.stack",
                                       description: Text(Self.explanation))
            }
        }
        .onChange(of: store.all.map(\.id)) { _, ids in
            if let id = selection.id, !ids.contains(id) { selection.id = ids.first }
        }
    }

    static let explanation = """
        Select text and click Collect on the bar. Each page, conversation or document gets a \
        collection of its own; ⇧-click Collect to start a new one. Then paste or copy them all at \
        once from Collected › on the bar, or here.
        """
}

private struct CollectionRow: View {
    let collection: SnippetCollection
    let onBar: Bool

    var body: some View {
        HStack(spacing: 9) {
            AppIcon(bundleID: collection.snippets.first?.app ?? "", size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(collection.name).lineLimit(1)
                    if collection.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Text("\(collection.snippets.count) · \(collection.updated.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if onBar {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    .help("On the bar under Collected ›")
            }
        }
        .padding(.vertical, 2)
    }
}

/// Right-click on a collection.
private struct CollectionMenu: View {
    @ObservedObject var store: Collections
    let collection: SnippetCollection

    var body: some View {
        Button("Copy All") { Copied.copy(collection.text) }
        Button("Copy as Markdown with Sources") { Copied.copy(collection.markdown) }
        Divider()
        Button(collection.pinned ? "Stop Collecting Everything Here" : "Collect Everything Here") {
            store.setPinned(collection.id, !collection.pinned)
        }
        Menu("Merge Into") {
            ForEach(store.all.filter { $0.id != collection.id }) { other in
                Button(other.name) { store.merge(collection.id, into: other.id) }
            }
        }
        .disabled(store.all.count < 2)
        Divider()
        Button("Delete", role: .destructive) { store.delete(collection.id) }
    }
}

private struct CollectionDetail: View {
    @ObservedObject var store: Collections
    let collection: SnippetCollection
    @State private var name = ""
    @State private var confirmingDelete = false
    @FocusState private var editingName: Bool

    private var summary: String {
        let count = collection.snippets.count
        let apps = collection.appNames.prefix(3).joined(separator: ", ")
        return "\(count) snippet\(count == 1 ? "" : "s") from \(apps) · started \(collection.created.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($editingName)
                    .onSubmit(commitName)
                    .onChange(of: editingName) { _, editing in
                        if !editing { commitName() }
                    }
                Text(summary).font(.callout).foregroundStyle(.secondary)
                if collection.pinned {
                    Label("Everything you collect goes here, from any app, until you turn this off.", systemImage: "pin.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                actions.padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            Divider()
            List {
                ForEach(collection.snippets) { snippet in
                    SnippetRow(store: store, snippet: snippet, collection: collection)
                }
                .onMove { store.moveSnippets(in: collection.id, from: $0, to: $1) }
            }
        }
        .onChange(of: collection.id, initial: true) { name = collection.name }
        .onChange(of: collection.name) { _, new in if !editingName { name = new } }
        .confirmationDialog("Delete “\(collection.name)”?", isPresented: $confirmingDelete) {
            Button("Delete \(collection.snippets.count) Snippets", role: .destructive) { store.delete(collection.id) }
        }
    }

    /// An empty name puts the old one back.
    private func commitName() {
        store.rename(collection.id, to: name)
        name = store.all.first { $0.id == collection.id }?.name ?? name
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { Copied.copy(collection.text) } label: { Label("Copy All", systemImage: "doc.on.doc") }
                .help("The snippets as one text, a blank line apart")
            Button { Copied.copy(collection.markdown) } label: { Label("Copy as Markdown", systemImage: "quote.opening") }
                .help("Each snippet as a quote, with a link to where it came from")
            RunMenu(collection: collection)
            Spacer()
            Toggle(isOn: Binding(get: { collection.pinned }, set: { store.setPinned(collection.id, $0) })) {
                Image(systemName: collection.pinned ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help(collection.pinned ? "Stop collecting everything here" : "Collect everything here, from any app")
            Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") }
                .help("Delete this collection")
        }
        .controlSize(.regular)
    }
}

/// Copies and says so with a short HUD over the window.
private enum Copied {
    static func copy(_ text: String) {
        Clipboard.copy(text)
        HUD.shared.show(symbol: "checkmark", text: "Copied", near: CollectionsWindow.anchor)
    }
}

/// Run › the extensions that take text, with the whole collection as the selection.
private struct RunMenu: View {
    let collection: SnippetCollection

    private var context: SelectionContext {
        var ctx = SelectionContext()
        ctx.text = collection.text
        ctx.fullText = ctx.text
        ctx.canCopy = true
        ctx.anchor = CollectionsWindow.anchor
        return ctx
    }

    /// Extensions that work on this text; not ones that paste (nothing to paste into here),
    /// press keys in an app, or copy the formatted selection from the app in front (`input:`).
    private var actions: [PopAction] {
        let ctx = context
        return Popoli.registry.extensions.compactMap { info in
            guard let ext = info.ext, let action = info.action, ext.target == .text, ext.input == .text,
                  Settings.isEnabled(info.id), action.prepare(ctx) != nil else { return nil }
            if case .keys = ext.kind { return nil }
            return action
        }
    }

    /// Extensions without a group first, then each group under its name.
    private var sections: [(group: String?, actions: [PopAction])] {
        var sections: [(group: String?, actions: [PopAction])] = []
        for action in actions {
            if let index = sections.firstIndex(where: { $0.group == action.group }) {
                sections[index].actions.append(action)
            } else {
                sections.append((action.group, [action]))
            }
        }
        return sections.sorted { $0.group == nil && $1.group != nil }
    }

    var body: some View {
        Menu {
            ForEach(sections, id: \.group) { section in
                Section(section.group ?? "") {
                    ForEach(section.actions, id: \.id) { action in
                        Button(action.title) { action.perform(context) }
                    }
                }
            }
        } label: {
            Label("Run", systemImage: "play")
        }
        .fixedSize()
        .help("Run an extension on all the snippets")
        .disabled(actions.isEmpty)
    }
}

private struct SnippetRow: View {
    @ObservedObject var store: Collections
    let snippet: Snippet
    let collection: SnippetCollection

    private var source: String {
        let title = snippet.title.isEmpty ? snippet.appName : snippet.title
        guard let host = snippet.url.flatMap(URL.init(string:))?.host(), !title.localizedCaseInsensitiveContains(host)
        else { return title }
        return "\(title) · \(host.replacingOccurrences(of: "www.", with: ""))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snippet.text).lineLimit(10)
            HStack(spacing: 6) {
                AppIcon(bundleID: snippet.app, size: 14)
                Text(source).lineLimit(1).truncationMode(.middle)
                Text("·")
                Text(snippet.added.formatted(.relative(presentation: .named))).fixedSize()
                Spacer(minLength: 8)
                Button { CollectionsWindow.open(snippet) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless)
                    .help(BrowserTab.isBrowser(snippet.app) && snippet.link != nil
                          ? "Open the page at this text" : "Open \(snippet.appName)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .draggable(snippetDragPrefix + snippet.id.uuidString)
        .contextMenu {
            Button("Copy") { Clipboard.copy(snippet.text) }
            Button(BrowserTab.isBrowser(snippet.app) && snippet.link != nil ? "Open Page at This Text" : "Open \(snippet.appName)") {
                CollectionsWindow.open(snippet)
            }
            Menu("Move To") {
                ForEach(store.all.filter { $0.id != collection.id }) { other in
                    Button(other.name) { store.move(snippet: snippet.id, to: other.id) }
                }
                Divider()
                Button("New Collection") { store.move(snippet: snippet.id, to: nil) }
            }
            Divider()
            Button("Delete", role: .destructive) { store.delete(snippet: snippet.id, from: collection.id) }
        }
    }
}

private struct AppIcon: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(named: NSImage.applicationIconName)!)
            .resizable()
            .frame(width: size, height: size)
    }
}
