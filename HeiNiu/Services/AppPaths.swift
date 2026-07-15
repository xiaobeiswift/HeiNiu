import Foundation

enum AppPaths {
    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("HeiNiu", isDirectory: true)
    }

    static var settingsFileURL: URL {
        applicationSupportRoot.appendingPathComponent("settings.json", isDirectory: false)
    }

    static func ensureDirectories() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: applicationSupportRoot.path) {
            try? fm.createDirectory(at: applicationSupportRoot, withIntermediateDirectories: true)
        }
    }
}
