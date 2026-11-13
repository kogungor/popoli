import AppKit
import Combine
import EventKit
import SwiftUI

// MARK: - Reminders

/// Adds reminders through EventKit. Reminders has no add-only access (Calendar has), so Popoli
/// asks for full access; it only reads the lists and adds to them.
enum Reminders {
    /// A list in Reminders, as the panel shows it.
    struct List: Identifiable, Hashable {
        let id: String
        let title: String
        let color: NSColor
        /// The account it is in: iCloud, an Exchange account…
        let account: String
    }

    /// When the reminder is due. Each choice but `none` also sets an alert then.
    enum Time: Hashable {
        case none, fromText, laterToday, tomorrow, weekend, nextWeek, custom
    }

    private static var store = EKEventStore()

    /// Asks the first time; calls back on the main thread.
    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            completion(true)
        case .notDetermined:
            store.requestFullAccessToReminders { granted, _ in
                DispatchQueue.main.async {
                    // A store made before access was granted does not see the lists.
                    if granted { store = EKEventStore() }
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    /// The lists that take new reminders, by account and name.
    static func lists() -> [List] {
        store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { List(id: $0.calendarIdentifier, title: $0.title, color: $0.color ?? .systemBlue, account: $0.source?.title ?? "") }
            .sorted { $0.account != $1.account ? $0.account < $1.account : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The list used last time, or the default list for new reminders.
    static func preferredList(in lists: [List]) -> List? {
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return lists.first { $0.id == Settings.reminderList } ?? lists.first { $0.id == defaultID } ?? lists.first
    }

    /// Adds a reminder. A `due` time also sets an alert then, so the reminder notifies.
    static func add(title: String, notes: String?, url: URL?, list: List, due: Date?) throws {
        // Never another list instead: the demo's sample lists end here too.
        guard let calendar = store.calendar(withIdentifier: list.id) else {
            throw NSError(domain: "Popoli", code: 1, userInfo: [NSLocalizedDescriptionKey: "“\(list.title)” is no longer in Reminders"])
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.url = url
        reminder.calendar = calendar
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
        Settings.reminderList = list.id
    }

    /// A date in the text ("tomorrow at 3pm", "next Friday") that is still ahead. A day without
    /// a time gets 9:00. macOS reads dates well in English only: in Turkish, for one, it finds
    /// just the time and puts it on today, so text in another language gets none.
    static func date(in text: String) -> Date? {
        if let language = Translator.detect(text), language.languageCode != .english { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              var date = match.date else { return nil }
        // A day on its own comes back at noon.
        let calendar = Calendar.current
        let phrase = (text as NSString).substring(with: match.range).lowercased()
        if calendar.component(.hour, from: date) == 12, calendar.component(.minute, from: date) == 0,
           !phrase.contains("12"), !phrase.contains("noon") {
            date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        return date > Date() ? date : nil
    }

    /// The time a choice stands for, from now; nil for `none` and `custom`.
    static func date(for time: Time, detected: Date?) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        func next(weekday: Int, after start: Date) -> Date? {
            calendar.nextDate(after: start, matching: DateComponents(hour: 9, minute: 0, weekday: weekday),
                              matchingPolicy: .nextTime)
        }
        switch time {
        case .none, .custom: return nil
        case .fromText: return detected
        case .laterToday:
            // Three hours from now, on the hour.
            let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            return calendar.date(byAdding: .hour, value: 3, to: hour)
        case .tomorrow: return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        case .weekend: return next(weekday: 7, after: now)
        case .nextWeek: return next(weekday: 2, after: tomorrow)
        }
    }

    /// The choices that make sense now: Later Today in the daytime, This Weekend on weekdays.
    static func times(detected: Date?) -> [Time] {
        let calendar = Calendar.current
        var times: [Time] = [.none]
        if detected != nil { times.append(.fromText) }
        if let later = date(for: .laterToday, detected: nil), calendar.isDateInToday(later),
           (8...21).contains(calendar.component(.hour, from: later)) { times.append(.laterToday) }
        times.append(.tomorrow)
        if !calendar.isDateInWeekend(Date()) { times.append(.weekend) }
        times += [.nextWeek, .custom]
        return times
    }

    /// The name of a choice in the menu, with its time: "Tomorrow · 09:00".
    static func label(_ time: Time, detected: Date?) -> String {
        let date = Self.date(for: time, detected: detected)
        let clock = date?.formatted(date: .omitted, time: .shortened) ?? ""
        let day = date?.formatted(.dateTime.weekday(.abbreviated)) ?? ""
        switch time {
        case .none: return "No Time"
        case .fromText: return "From the Text · " + (date.map(describe) ?? "")
        case .laterToday: return "Later Today · " + clock
        case .tomorrow: return "Tomorrow · " + clock
        case .weekend: return "This Weekend · \(day) \(clock)"
        case .nextWeek: return "Next Week · \(day) \(clock)"
        case .custom: return "Custom"
        }
    }

    /// "Today, 18:00", "Tomorrow, 09:00" or "Sat 15 Nov, 09:00".
    static func describe(_ date: Date) -> String {
        let calendar = Calendar.current
        let clock = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today, " + clock }
        if calendar.isDateInTomorrow(date) { return "Tomorrow, " + clock }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + clock
    }

    /// A list's color as a dot for menus, which draw other images as templates.
    static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Model

final class ReminderModel: ObservableObject {
    enum State { case editing, noAccess, noLists }

    @Published var state = State.editing
    @Published var title = ""
    /// The lines after the first, which go in the reminder's notes.
    var notes: String?
    /// The page the text was selected on, which goes in the reminder's URL.
    @Published var page: BrowserTab.Page?
    @Published var lists: [Reminders.List] = []
    @Published var listID = ""
    @Published var times: [Reminders.Time] = []
    @Published var time = Reminders.Time.none {
        didSet {
            guard time != oldValue else { return }
            if time != .custom {
                due = Reminders.date(for: time, detected: detected)
            } else if due == nil {
                // The next full hour.
                let hour = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
                due = Calendar.current.date(byAdding: .hour, value: 1, to: hour)
            }
        }
    }
    @Published var due: Date?
    /// The date found in the text, if any.
    var detected: Date?

    var onAdd: () -> Void = {}
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var list: Reminders.List? { lists.first { $0.id == listID } }
    var accounts: [String] { lists.map(\.account).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } }

    /// Fills the panel for `text`; `lists` is nil without access to Reminders.
    func load(_ text: String, lists: [Reminders.List]?, page: BrowserTab.Page?) {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        title = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        notes = rest.isEmpty ? nil : rest
        self.page = page.flatMap { $0.url.hasPrefix("http") ? $0 : nil }
        self.lists = lists ?? []
        state = lists == nil ? .noAccess : self.lists.isEmpty ? .noLists : .editing
        listID = Reminders.preferredList(in: self.lists)?.id ?? ""
        detected = Reminders.date(in: text)
        times = Reminders.times(detected: detected)
        due = nil
        time = .none
        time = detected == nil ? .none : .fromText
    }
}

// MARK: - View

struct ReminderView: View {
    @ObservedObject var model: ReminderModel
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch model.state {
            case .editing: form
            case .noAccess: message("Popoli needs access to Reminders to add to your lists.", button: "Open Privacy Settings")
            case .noLists: message("Reminders has no list to add to.", button: nil)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        // The panel never makes Popoli the active app; without this its controls look disabled.
        .environment(\.controlActiveState, .key)
        .onAppear { titleFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Add to Reminders").font(.headline)
            Spacer(minLength: 8)
            Button(action: model.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close (Esc)")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $model.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($titleFocused)
                    .onSubmit(model.onAdd)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary))
                if let notes = model.notes {
                    let count = notes.components(separatedBy: .newlines).count
                    Text(count == 1 ? "The next line goes in the notes." : "The other \(count) lines go in the notes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let page = model.page {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                        Text(page.title.isEmpty ? page.url : page.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button { model.page = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .help("Leave out the link")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(page.url)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("List").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    listPicker
                }
                GridRow {
                    Text("Time").foregroundStyle(.secondary)
                    timePicker
                }
                if model.due != nil {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        DatePicker("Due", selection: dueBinding, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.stepperField)
                            .fixedSize()
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: model.onClose)
                    .buttonStyle(.glass)
                Button("Add", action: model.onAdd)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.title.trimmingCharacters(in: .whitespaces).isEmpty || model.list == nil)
            }
        }
    }

    private var listPicker: some View {
        Picker("List", selection: $model.listID) {
            if model.accounts.count > 1 {
                ForEach(model.accounts, id: \.self) { account in
                    Section(account) { listItems(model.lists.filter { $0.account == account }) }
                }
            } else {
                listItems(model.lists)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func listItems(_ lists: [Reminders.List]) -> some View {
        ForEach(lists) { list in
            Label { Text(list.title) } icon: { Image(nsImage: Reminders.dot(list.color)) }
                .tag(list.id)
        }
    }

    private var timePicker: some View {
        Picker("Time", selection: $model.time) {
            ForEach(model.times, id: \.self) { time in
                Text(Reminders.label(time, detected: model.detected)).tag(time)
                if time == .none || time == .nextWeek { Divider() }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    /// Changing the date or time by hand makes it Custom.
    private var dueBinding: Binding<Date> {
        Binding(get: { model.due ?? Date() }, set: { date in
            model.due = date
            if model.time != .custom { model.time = .custom }
        })
    }

    private func message(_ text: String, button: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).fixedSize(horizontal: false, vertical: true)
            if let button {
                HStack {
                    Spacer(minLength: 0)
                    Button(button, action: model.onOpenSettings).buttonStyle(.glass)
                }
            }
        }
    }
}

// MARK: - Controller

/// The glass panel Add to Reminders opens: the title, the list and the time.
final class ReminderController {
    static let shared = ReminderController()

    private let model = ReminderModel()
    private let panel = FloatingPanel(allowsKey: true)
    private var hosting: NSHostingView<ReminderView>?
    private let margin: CGFloat = 18
    private var growsUp = true
    private var context = SelectionContext()
    private var observer: AnyCancellable?

    var isVisible: Bool { panel.isVisible }
    var window: NSWindow { panel }

    init() {
        model.onClose = { [weak self] in self?.hide() }
        model.onAdd = { [weak self] in self?.add() }
        model.onOpenSettings = { [weak self] in
            self?.hide()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                NSWorkspace.shared.open(url)
            }
        }
        observer = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.relayout() }
        }
    }

    /// Asks for access the first time and looks up the page in a browser, then shows the panel.
    /// Both can bring up a macOS prompt, which must come before the panel: a click anywhere
    /// else closes it.
    func show(_ ctx: SelectionContext) {
        Reminders.requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else { return self.present(ctx, lists: nil, page: nil) }
            guard let app = ctx.app, BrowserTab.isBrowser(ctx.bundleID) else {
                return self.present(ctx, lists: Reminders.lists(), page: nil)
            }
            BrowserTab.current(in: app) { page in self.present(ctx, lists: Reminders.lists(), page: page) }
        }
    }

    /// Shows the panel for `ctx`; `lists` is nil without access to Reminders.
    func present(_ ctx: SelectionContext, lists: [Reminders.List]?, page: BrowserTab.Page?) {
        context = ctx
        model.load(ctx.text, lists: lists, page: page)
        // A new view each time, so the title takes the focus again.
        let hosting = NSHostingView(rootView: ReminderView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hosting = hosting
        let surface = GlassSurface(content: hosting, cornerRadius: 24, margin: margin, interactive: false)
        panel.contentView = surface
        let frame = Glass.frame(for: contentSize(), above: ctx.anchor, gap: 10)
        growsUp = frame.minY >= ctx.anchor.maxY
        panel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
        panel.alphaValue = 0
        // Key at once, so typing edits the title and Return adds; the app in front stays active.
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        Popoli.monitor.updateTransient()
    }

    func hide() {
        guard panel.isVisible else { return }
        let wasKey = panel.isKeyWindow
        panel.orderOut(nil)
        if wasKey { context.app?.activate() }
        Popoli.monitor.updateTransient()
    }

    private func contentSize() -> NSSize {
        guard let hosting else { return NSSize(width: 360, height: 60) }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        return NSSize(width: ceil(max(size.width, 360)), height: ceil(max(size.height, 60)))
    }

    /// Keeps the edge next to the selection fixed while the date row comes and goes.
    private func relayout() {
        guard panel.isVisible else { return }
        let size = contentSize()
        let current = panel.frame.insetBy(dx: margin, dy: margin)
        let y = growsUp ? current.minY : current.maxY - size.height
        panel.setFrame(NSRect(x: current.minX, y: y, width: size.width, height: size.height)
            .insetBy(dx: -margin, dy: -margin), display: true)
    }

    private func add() {
        let title = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard panel.isVisible, !title.isEmpty, let list = model.list else { return }
        let due = model.due
        let url = model.page.flatMap { URL(string: $0.url) }
        let anchor = context.anchor
        hide()
        do {
            try Reminders.add(title: title, notes: model.notes, url: url, list: list, due: due)
            HUD.shared.show(symbol: "checkmark", text: "Added to \(list.title)" + (due.map { " · " + Reminders.describe($0) } ?? ""),
                            near: anchor)
        } catch {
            HUD.shared.show(symbol: "xmark", text: "Couldn’t add the reminder: \(error.localizedDescription)", near: anchor)
        }
    }
}
