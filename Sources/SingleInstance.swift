import AppKit

/// Keeps one Popoli running. macOS starts every copy of the app separately: a development build,
/// a second download, or Popoli opened from the disk image (which macOS runs from a new
/// temporary place each time). Each would add its own menu bar icon and selection bar.
///
/// A new copy hands over to the one already running and asks it to show Settings, unless the new
/// copy is the one in an Applications folder: then the others quit, so trying Popoli from the disk
/// image and then installing it ends with the installed copy running.
enum SingleInstance {
    private static let showSettings = Notification.Name("app.popoli.Popoli.showSettings")
    private static let quit = Notification.Name("app.popoli.Popoli.quit")

    /// False when another copy keeps running and this process should exit.
    static func claim() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        var others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        // A copy that is quitting (a restart, an update) is not one to hand over to: wait a moment.
        let settle = Date().addingTimeInterval(1)
        while others.contains(where: { kill($0.processIdentifier, 0) == 0 }) && Date() < settle {
            if others.allSatisfy(\.isTerminated) { break }
            usleep(100_000)
            others = others.filter { kill($0.processIdentifier, 0) == 0 }
        }
        others = others.filter { kill($0.processIdentifier, 0) == 0 }
        guard !others.isEmpty else { return true }

        if isInstalled(Bundle.main.bundleURL), !others.contains(where: { isInstalled($0.bundleURL) }) {
            post(quit)
            let deadline = Date().addingTimeInterval(3)
            while others.contains(where: { kill($0.processIdentifier, 0) == 0 }) && Date() < deadline {
                usleep(100_000)
            }
            others.filter { kill($0.processIdentifier, 0) == 0 }.forEach { $0.forceTerminate() }
            return true
        }
        post(showSettings)
        return false
    }

    /// Every copy of Popoli that macOS has seen registers its own Finder extension, and Finder
    /// may use any of them. Only the running copy's extension stays registered.
    static func keepOwnFinderExtension() {
        guard let own = Bundle.main.builtInPlugInsURL?.appendingPathComponent("PopoliFinder.appex")
            .resolvingSymlinksInPath().path else { return }
        let pluginkit = URL(fileURLWithPath: "/usr/bin/pluginkit")
        let temp = FileManager.default.temporaryDirectory
        Runner.run(executable: pluginkit, arguments: ["-mAvvv", "-i", "app.popoli.Popoli.FinderMenu"], input: nil,
                   environment: [:], directory: temp, timeout: 10) { result in
            guard case .success(let output) = result else { return }
            let paths = output.split(separator: "\n").compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.count == 2 && parts[0] == "Path" ? parts[1] : nil
            }
            for path in paths where URL(fileURLWithPath: path).resolvingSymlinksInPath().path != own {
                Runner.run(executable: pluginkit, arguments: ["-r", path], input: nil, environment: [:],
                           directory: temp, timeout: 10) { _ in }
            }
        }
    }

    /// Answers copies started later.
    static func listen() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: showSettings, object: nil, queue: .main) { _ in SettingsWindowController.shared.show() }
        center.addObserver(forName: quit, object: nil, queue: .main) { _ in NSApp.terminate(nil) }
    }

    private static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func isInstalled(_ url: URL?) -> Bool {
        guard let path = url?.standardizedFileURL.path else { return false }
        let folders = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/"]
        return folders.contains { path.hasPrefix($0) }
    }
}

/// Popoli opened straight from the disk image offers to move itself to Applications. macOS runs
/// such a copy from a new temporary place on every launch, and it disappears with the disk image,
/// taking the Finder extension with it.
enum MoveToApplications {
    static var isRunningFromDiskImage: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Asks once per launch. Returns true when Popoli is about to quit for the moved copy.
    @discardableResult
    static func offerIfNeeded() -> Bool {
        guard isRunningFromDiskImage else { return false }
        let alert = NSAlert()
        alert.messageText = "Move Popoli to the Applications folder?"
        alert.informativeText = "Popoli is running from the disk image. In Applications it keeps working after you eject the disk image, its Finder menu stays available and it updates itself."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let destination = URL(fileURLWithPath: "/Applications/Popoli.app")
        let files = FileManager.default
        do {
            if files.fileExists(atPath: destination.path) {
                try files.trashItem(at: destination, resultingItemURL: nil)
            }
            try files.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn’t move Popoli"
            failure.informativeText = "\(error.localizedDescription)\n\nDrag Popoli from the disk image to the Applications folder instead."
            failure.runModal()
            return false
        }
        // A copy made by an app (not by Finder) keeps the download's quarantine flag, and macOS
        // would run it from a temporary place again. Popoli already passed Gatekeeper's check.
        Runner.run(executable: URL(fileURLWithPath: "/usr/bin/xattr"),
                   arguments: ["-dr", "com.apple.quarantine", destination.path], input: nil, environment: [:],
                   directory: FileManager.default.temporaryDirectory, timeout: 30) { _ in
            // The installed copy asks this one to quit when it starts (see SingleInstance). Without a new
            // instance, macOS would only bring this running copy forward.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if let error { NSAlert(error: error).runModal() }
                    NSApp.terminate(nil)
                }
            }
        }
        return true
    }
}
