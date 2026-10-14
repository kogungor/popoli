import AppKit
import CryptoKit

/// The extension catalog: catalog/ in the repository, listed in catalog/index.json, which
/// Settings ▸ Catalog reads from the main branch (the released state).
enum Catalog {
    struct Entry: Codable, Identifiable, Hashable {
        let file: String
        let name: String
        let description: String?
        let icon: String?
        let group: String?
        let category: String
        /// SHA-256 of the file as Popoli installs it (see `fingerprint`).
        let sha256: String
        /// Installed on first launch.
        let starter: Bool
        let forFiles: Bool
        let internet: Bool
        let secrets: [String]
        let settings: [String]

        var id: String { file }
    }

    struct Index: Codable {
        let version: Int
        let extensions: [Entry]
    }

    /// The order of the categories; a newer catalog can add more, which come after these.
    static let categories = ["Text", "AI", "Developer", "Encode & Decode", "Add to", "Finder"]

    static let base = URL(string: ProcessInfo.processInfo.environment["POPOLI_CATALOG_BASE"]
        ?? "https://raw.githubusercontent.com/kogungor/popoli/main/catalog/")!
    static var indexURL: URL { base.appendingPathComponent("index.json") }
    static func fileURL(_ file: String) -> URL { base.appendingPathComponent(file) }

    /// SHA-256 of an extension's text the way the installer writes it, so a file installed
    /// from the catalog matches its entry. The `description:` line is left out: it is only for
    /// the catalog, and a copy that lacks it (installed before it was written) is still current.
    static func fingerprint(_ text: String) -> String {
        let lines = ExtensionInstaller.normalized(text).components(separatedBy: "\n")
            .filter { $0.range(of: #"^\s*(#|//|--)\s*description\s*:"#, options: .regularExpression) == nil }
        return SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func category(of ext: UserExtension) -> String {
        if ext.target == .files { return "Finder" }
        switch ext.group {
        case "Encode"?, "Decode"?: return "Encode & Decode"
        case "Ask"?: return "AI"
        case "Developer"?: return "Developer"
        case "Add to"?: return "Add to"
        default: return "Text"
        }
    }

    /// The index of a catalog folder: what `--catalog-index` prints and CI compares with
    /// catalog/index.json. Sorted by file name, so the output only changes with the files.
    static func index(of folder: URL) throws -> Index {
        let starters = Set(((try? String(contentsOf: folder.appendingPathComponent("starter.txt"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { !["README.md", "index.json", "starter.txt"].contains($0.lastPathComponent) && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let entries = try files.map { file -> Entry in
            let text = try String(contentsOf: file, encoding: .utf8)
            let ext = try ExtensionStore.parse(text: text, file: file)
            let warnings = ExtensionInstaller.warnings(in: text, for: ext)
            var icon: String?
            if let line = ExtensionStore.header(of: text).first(where: { $0.0 == "icon" }) { icon = line.1 }
            return Entry(file: file.lastPathComponent, name: ext.name, description: ext.description, icon: icon,
                         group: ext.group, category: category(of: ext), sha256: fingerprint(text),
                         starter: starters.contains(file.lastPathComponent), forFiles: ext.target == .files,
                         internet: warnings.contains { $0.symbol == "network" }, secrets: ext.secrets,
                         settings: ext.settings.map(\.name))
        }
        return Index(version: 1, extensions: entries)
    }

    static func json(_ index: Index) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(index), as: UTF8.self) + "\n"
    }

    /// Files installed from the catalog and the fingerprint they had, to tell an update
    /// (the catalog changed) from a file you edited.
    static var installs: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "catalogInstalls") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "catalogInstalls") }
    }

    static func recordInstall(file: String, fingerprint: String) {
        var all = installs
        all[file] = fingerprint
        installs = all
    }
}

/// Settings ▸ Catalog.
final class CatalogModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, failed(String) }
    enum Status { case notInstalled, installed, update, changed }

    @Published var state = State.idle
    @Published var entries: [Catalog.Entry] = []
    @Published var search = ""
    @Published var category = "All"
    @Published private(set) var statuses: [String: Status] = [:]

    init() {
        NotificationCenter.default.addObserver(forName: ExtensionInstaller.didInstall, object: nil, queue: .main) { [weak self] _ in
            self?.refreshStatuses()
        }
    }

    /// The categories in the list, for the picker: the known ones in order, then new ones.
    var categories: [String] {
        let present = Set(entries.map(\.category))
        return Catalog.categories.filter(present.contains) + present.subtracting(Catalog.categories).sorted()
    }

    var filtered: [Catalog.Entry] {
        let words = search.lowercased().split(separator: " ")
        return entries.filter { entry in
            (category == "All" || entry.category == category)
                && words.allSatisfy { word in
                    [entry.name, entry.description ?? "", entry.group ?? "", entry.category]
                        .contains { $0.lowercased().contains(word) }
                }
        }
    }

    func load(force: Bool = false) {
        if !force, state == .loaded || state == .loading { return }
        state = .loading
        let request = URLRequest(url: Catalog.indexURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession(configuration: .ephemeral).dataTask(with: request) { [weak self] data, response, error in
            let result: Result<[Catalog.Entry], ExtensionError>
            if let error {
                result = .failure(ExtensionError(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(ExtensionError("The server answered with HTTP \(http.statusCode)."))
            } else if let data, let index = try? JSONDecoder().decode(Catalog.Index.self, from: data) {
                result = .success(index.extensions)
            } else {
                result = .failure(ExtensionError("The list isn’t in a format this version understands."))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let entries):
                    let order = Dictionary(uniqueKeysWithValues: Catalog.categories.enumerated().map { ($1, $0) })
                    self.entries = entries.sorted {
                        (order[$0.category] ?? 99, $0.group ?? "", $0.name) < (order[$1.category] ?? 99, $1.group ?? "", $1.name)
                    }
                    self.state = .loaded
                    self.refreshStatuses()
                case .failure(let error):
                    self.state = .failed(error.message)
                }
            }
        }.resume()
    }

    func refreshStatuses() {
        let installs = Catalog.installs
        var result: [String: Status] = [:]
        for entry in entries {
            let file = ExtensionStore.folder.appendingPathComponent(entry.file)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { result[entry.file] = .notInstalled; continue }
            let local = Catalog.fingerprint(text)
            if local == entry.sha256 {
                result[entry.file] = .installed
            } else {
                // Unchanged since it came from the catalog: an update. Otherwise you edited it.
                result[entry.file] = installs[entry.file] == local ? .update : .changed
            }
        }
        statuses = result
    }

    func install(_ entry: Catalog.Entry) {
        ExtensionInstaller.reviewCatalog(entry)
    }
}
