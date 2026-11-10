import AppKit
import DesklandCore

enum AppPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let profileDir = ProfileDirectory.resolve(environment: ProcessInfo.processInfo.environment, home: home)
    static let shareDir = home.appendingPathComponent("Pictures/Deskland Preview")
    static let logFile = profileDir.appendingPathComponent("host.log")

    // DESKLAND_PAGE_DIR, then the app bundle's prototype/, then a prototype/ above the executable (swift run).
    static let pageDir: URL = {
        if let o = ProcessInfo.processInfo.environment["DESKLAND_PAGE_DIR"], !o.isEmpty { return URL(fileURLWithPath: o) }
        if let r = Bundle.main.resourceURL?.appendingPathComponent("prototype"),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("themes.json").path) { return r }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("prototype")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("themes.json").path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "prototype")
    }()

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}

enum Log {
    static func write(_ msg: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss "
        let line = f.string(from: Date()) + msg + "\n"
        try? FileManager.default.createDirectory(at: AppPaths.profileDir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: AppPaths.logFile) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: AppPaths.logFile)
        }
    }
}
