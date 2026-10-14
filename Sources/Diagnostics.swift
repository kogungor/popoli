import AppKit
import CryptoKit

/// The diagnostics log (Settings ▸ General): one line per selection in
/// ~/Library/Logs/Popoli/selection.log, to find out why the bar misbehaves in an app. It never
/// holds the selected text, only its length and the start of its SHA-256, so a log can be
/// attached to a bug report as it is.
enum Diagnostics {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "diagnostics") }

    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Popoli/selection.log")
    private static let queue = DispatchQueue(label: "app.popoli.diagnostics", qos: .utility)
    /// Past this size the log keeps only its newer half.
    private static let limit = 1_000_000

    private struct Line: Encodable {
        let time: String
        let app: String
        let trigger: String
        /// "accessibility", "copy" (⌘C fallback), or "none".
        let readBy: String
        let length: Int
        let files: Int
        let checksum: String
        let cut: Bool
        let copy: Bool
        let paste: Bool
        let buttons: [String]
        /// From the mouse-up (or the shortcut) to the bar.
        let ms: Int?
        let note: String?
    }

    /// The first 8 hex digits of the text's SHA-256: enough to compare it with a known text.
    static func checksum(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func record(_ trigger: String, _ ctx: SelectionContext, buttons: [String] = [],
                       since start: TimeInterval? = nil, note: String? = nil) {
        guard isOn else { return }
        let content = ctx.files.isEmpty ? ctx.fullText : ctx.files.joined(separator: "\n")
        let line = Line(time: ISO8601DateFormatter().string(from: Date()), app: ctx.bundleID, trigger: trigger,
                        readBy: ctx.readBy, length: ctx.fullText.count, files: ctx.files.count,
                        checksum: content.isEmpty ? "" : checksum(content),
                        cut: ctx.canCut, copy: ctx.canCopy, paste: ctx.canPaste, buttons: buttons,
                        ms: start.map { Int((ProcessInfo.processInfo.systemUptime - $0) * 1000) }, note: note)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(line) else { return }
        queue.async { append(data + Data("\n".utf8)) }
    }

    private static func append(_ data: Data) {
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > limit,
           let old = try? Data(contentsOf: file) {
            let half = old.suffix(limit / 2)
            let start = half.firstIndex(of: UInt8(ascii: "\n")).map { half.index(after: $0) } ?? half.startIndex
            try? half[start...].write(to: file)
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }

    static func reveal() {
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(file.deletingLastPathComponent().deletingLastPathComponent())
        }
    }
}
