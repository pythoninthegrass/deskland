import Foundation

// AX frames are icon only; the Windows host sends icon plus label, so add the label's upper bound (114x28 pt, 8 pt below).
public enum IconLabel {
    static let width = 114.0, height = 28.0, gap = 8.0

    public static func bounds(forIcon r: Rect) -> Rect {
        Rect(x: r.x + r.width / 2 - width / 2, y: r.y, width: width, height: r.height + gap + height)
    }
}

// Lets a poller send a value only when it differs from the last one sent.
public struct ChangeGate<Value: Equatable> {
    private var last: Value?

    public init() {}

    public mutating func shouldSend(_ v: Value) -> Bool {
        if last == v { return false }
        last = v
        return true
    }

    public mutating func reset() { last = nil }
}

// Neither AX nor the window list changes when icons are hidden (TASK-002.01), so read the preferences.
public enum DesktopIcons {
    public static func isVisible(standardHideDesktopIcons: Bool?, createDesktop: Bool?) -> Bool {
        standardHideDesktopIcons != true && createDesktop != false
    }
}

public enum LaunchCommand: Equatable {
    case run(autostart: Bool)
    case settings, menu, exit

    public static func parse(_ args: [String]) -> LaunchCommand {
        if args.contains("--exit") { return .exit }
        if args.contains("--menu") { return .menu }
        if args.contains("--settings") { return .settings }
        return .run(autostart: args.contains("--autostart"))
    }

    // What a second launch tells the running instance; a login-item launch exits quietly.
    public var forwarded: LaunchCommand? {
        switch self {
        case .run(autostart: true): nil
        case .run(autostart: false): .settings
        default: self
        }
    }

    public var wireName: String {
        switch self {
        case .run: "run"
        case .settings: "settings"
        case .menu: "menu"
        case .exit: "exit"
        }
    }

    public init?(wireName: String) {
        switch wireName {
        case "settings": self = .settings
        case "menu": self = .menu
        case "exit": self = .exit
        default: return nil
        }
    }
}

public enum ShareFile {
    // Pages send data URLs; tolerate a bare base64 payload too.
    public static func decode(_ dataURL: String) -> Data? {
        let payload = dataURL.firstIndex(of: ",").map { String(dataURL[dataURL.index(after: $0)...]) } ?? dataURL
        return Data(base64Encoded: payload)
    }

    public static func fileName(date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return "Deskland \(f.string(from: date)).\(ext)"
    }

    public static func videoExtension(mime: String) -> String {
        mime == "video/webm" ? "webm" : "mp4"
    }
}

public enum ByteRange {
    // Media elements on a custom scheme need 206 responses; only a single range is supported.
    public static func parse(_ header: String, length: Int) -> ClosedRange<Int>? {
        guard header.hasPrefix("bytes="), length > 0 else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let last = length - 1
        switch (Int(parts[0]), Int(parts[1])) {
        case let (start?, end?):
            guard start <= end, start <= last else { return nil }
            return start...min(end, last)
        case let (start?, nil):
            return start <= last ? start...last : nil
        case let (nil, suffix?):
            return suffix > 0 ? max(0, length - suffix)...last : nil
        default:
            return nil
        }
    }
}

// Stands in for WebView2's window.chrome.webview so theme and settings pages run unchanged.
public enum ScriptBridge {
    public static let shim = """
    (function () {
      if (window.chrome && window.chrome.webview) return;
      var listeners = [];
      var webview = {
        postMessage: function (m) {
          window.webkit.messageHandlers.deskland.postMessage(typeof m === 'string' ? m : JSON.stringify(m));
        },
        addEventListener: function (type, fn) { if (type === 'message') listeners.push(fn); },
        removeEventListener: function (type, fn) { listeners = listeners.filter(function (f) { return f !== fn; }); },
        __dispatch: function (data) { listeners.slice().forEach(function (f) { f({ data: data }); }); }
      };
      window.chrome = window.chrome || {};
      window.chrome.webview = webview;
    })();
    """

    public static func dispatch(_ message: String) -> String {
        "window.chrome.webview.__dispatch(\(JSONValue.string(message).serialized))"
    }
}

public struct ResolvedResource: Equatable {
    public let file: URL
    public let mime: String
}

// Maps deskland://app/<path> to the page folder and deskland://share/<name> to the share folder.
public struct ResourceResolver {
    let pageDir: URL
    let shareDir: URL
    let catalog: ThemeCatalog

    public init(pageDir: URL, shareDir: URL, catalog: ThemeCatalog) {
        self.pageDir = pageDir; self.shareDir = shareDir; self.catalog = catalog
    }

    public func resolve(_ url: URL) -> ResolvedResource? {
        let root: URL
        switch url.host {
        case "app": root = pageDir
        case "share": root = shareDir
        default: return nil
        }
        let relative = String(url.path.drop(while: { $0 == "/" }))
        guard !relative.isEmpty else { return nil }
        if url.host == "app", catalog.themes.contains(where: { $0.page == relative && !catalog.isAllowed($0.id) }) { return nil }
        let base = root.resolvingSymlinksInPath()
        let file = base.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(base.path + "/"),
              (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        return ResolvedResource(file: file, mime: Self.mime(forExtension: file.pathExtension.lowercased()))
    }

    static func mime(forExtension ext: String) -> String {
        switch ext {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "svg": "image/svg+xml"
        case "ico": "image/x-icon"
        case "woff2": "font/woff2"
        case "mp4": "video/mp4"
        case "webm": "video/webm"
        default: "application/octet-stream"
        }
    }
}

// Host strings live under "host" in prototype/i18n/<lang>.json; lookup goes current, then English, then Simplified Chinese.
public struct Localizer {
    public static let supported = ["zh-CN", "en"]
    public let code: String
    public let system: String
    private let tables: [[String: String]]

    public init(pageDir: URL, setting: String, preferred: [String]) {
        system = Self.systemLanguage(preferred: preferred)
        code = Self.supported.contains(setting) ? setting : system
        func table(_ c: String) -> [String: String] {
            let url = pageDir.appendingPathComponent("i18n/\(c).json")
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let root = try? JSONValue.parse(text),
                  let host = root.objectPairs?.first(where: { $0.key == "host" })?.value.objectPairs else { return [:] }
            return Dictionary(host.compactMap { p in p.value.stringValue.map { (p.key, $0) } }, uniquingKeysWith: { $1 })
        }
        tables = [table(code), table("en"), table("zh-CN")]
    }

    public static func systemLanguage(preferred: [String]) -> String {
        preferred.first?.lowercased().hasPrefix("zh") == true ? "zh-CN" : "en"
    }

    public func t(_ key: String, _ vars: [String: String] = [:]) -> String {
        var s = tables.lazy.compactMap { $0[key] }.first ?? key
        for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }
}

// Messages the settings page posts to the host.
public enum SettingsMessage: Equatable {
    case hello
    case set(theme: String, key: String, value: JSONValue)
    case reset(theme: String)
    case theme(id: String?)
    case lang(String)
    case autostart(Bool)
    case autostartWarnSeen
    case share, shareVideo, openShare, revealShare, openWebsite
    case unknown

    public static func parse(_ text: String) -> SettingsMessage {
        guard let pairs = (try? JSONValue.parse(text))?.objectPairs else { return .unknown }
        func field(_ k: String) -> JSONValue? { pairs.first { $0.key == k }?.value }
        switch field("t")?.stringValue {
        case "hello": return .hello
        case "set":
            guard let theme = field("theme")?.stringValue, let key = field("key")?.stringValue, let v = field("value") else { return .unknown }
            return .set(theme: theme, key: key, value: v)
        case "reset": return field("theme")?.stringValue.map { .reset(theme: $0) } ?? .unknown
        case "theme": return .theme(id: field("id")?.stringValue)
        case "lang": return field("v")?.stringValue.map { .lang($0) } ?? .unknown
        case "autostart": return .autostart(field("v")?.boolValue ?? false)
        case "autostartWarnSeen": return .autostartWarnSeen
        case "share": return .share
        case "shareVideo": return .shareVideo
        case "openShare": return .openShare
        case "revealShare": return .revealShare
        case "openWebsite": return .openWebsite
        default: return .unknown
        }
    }
}

// Host to settings page messages, keys in the order DesktopHost.cs writes them.
public enum SettingsReply {
    public static func initial(settings: Settings, screenWidth: Int, screenHeight: Int, autostart: Bool,
                               langEff: String, langSys: String) -> String {
        JSONValue.object([
            ("t", .string("init")), ("theme", .string(settings.theme)), ("params", settings.paramsJSON),
            ("screen", .object([("w", .number(Double(screenWidth))), ("h", .number(Double(screenHeight)))])),
            ("autostart", .bool(autostart)), ("autostartWarn", .bool(false)), ("autostartSw", .string("")),
            ("lang", .string(settings.lang)), ("langEff", .string(langEff)), ("langSys", .string(langSys)),
        ]).serialized
    }

    public static func themeChanged(_ id: String) -> String {
        JSONValue.object([("t", .string("themeChanged")), ("id", .string(id))]).serialized
    }

    public static func lang(_ v: String, effective: String, system: String) -> String {
        JSONValue.object([("t", .string("lang")), ("v", .string(v)), ("eff", .string(effective)), ("sys", .string(system))]).serialized
    }

    public static func autostart(_ on: Bool) -> String {
        JSONValue.object([("t", .string("autostart")), ("v", .bool(on))]).serialized
    }

    // The page already formats progress as a number string.
    public static func recordProgress(_ p: String) -> String { "{\"t\":\"recProgress\",\"p\":\(p)}" }

    public static func shareFailure(_ msg: String) -> String {
        JSONValue.object([("t", .string("shareResult")), ("ok", .bool(false)), ("path", .null), ("msg", .string(msg))]).serialized
    }

    public static func shareImage(thumb: String, path: String) -> String {
        JSONValue.object([("t", .string("shareResult")), ("ok", .bool(true)), ("thumb", .string(thumb)), ("path", .string(path))]).serialized
    }

    public static func shareVideo(poster: String, path: String, url: String) -> String {
        JSONValue.object([("t", .string("shareResult")), ("ok", .bool(true)), ("kind", .string("video")),
                          ("thumb", .string(poster)), ("path", .string(path)), ("url", .string(url))]).serialized
    }
}
