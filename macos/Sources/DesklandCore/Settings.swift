import Foundation

// settings.json: {version:1, theme, lang, params}. Only values the user changed are stored.
public struct Settings: Equatable {
    public var theme = "beach"
    public var lang = "auto"
    var params: [(theme: String, values: [(key: String, value: JSONValue)])] = []
    var extras: [(key: String, value: JSONValue)] = []

    public init() {}

    public static func == (a: Settings, b: Settings) -> Bool {
        a.theme == b.theme && a.lang == b.lang && a.paramsJSON == b.paramsJSON
            && JSONValue.object(a.extras) == JSONValue.object(b.extras)
    }

    public func values(for theme: String) -> [(key: String, value: JSONValue)] {
        params.first { $0.theme == theme }?.values ?? []
    }

    public mutating func set(theme: String, key: String, value: JSONValue) {
        let t = params.firstIndex { $0.theme == theme } ?? { params.append((theme, [])); return params.count - 1 }()
        if let k = params[t].values.firstIndex(where: { $0.key == key }) {
            params[t].values[k].value = value
        } else {
            params[t].values.append((key, value))
        }
    }

    public mutating func reset(theme: String) {
        params.removeAll { $0.theme == theme }
    }

    var paramsJSON: JSONValue {
        .object(params.map { ($0.theme, .object($0.values)) })
    }

    public var serialized: String {
        let known: [(key: String, value: JSONValue)] = [
            ("version", .number(1)), ("theme", .string(theme)), ("lang", .string(lang)), ("params", paramsJSON),
        ]
        return JSONValue.object(known + extras).serialized
    }

    static let fileName = "settings.json"

    // Unreadable or malformed files fall back to defaults, as the Windows host does.
    public static func load(from dir: URL) -> Settings {
        var s = Settings()
        guard let text = try? String(contentsOf: dir.appendingPathComponent(fileName), encoding: .utf8),
              let pairs = (try? JSONValue.parse(text))?.objectPairs else { return s }
        for (key, value) in pairs {
            switch key {
            case "version": break
            case "theme": if let v = value.stringValue { s.theme = v }
            case "lang": if let v = value.stringValue { s.lang = v }
            case "params":
                for (theme, vals) in value.objectPairs ?? [] {
                    if let inner = vals.objectPairs { s.params.append((theme, inner)) }
                }
            default: s.extras.append((key, value))
            }
        }
        return s
    }

    public func save(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try serialized.write(to: dir.appendingPathComponent(Self.fileName), atomically: true, encoding: .utf8)
    }
}

public enum ProfileDirectory {
    public static func resolve(environment: [String: String], home: URL) -> URL {
        if let o = environment["DESKLAND_PROFILE_DIR"], !o.isEmpty {
            return URL(fileURLWithPath: o).standardizedFileURL
        }
        return home.appendingPathComponent("Library/Application Support/DesklandPreview")
    }
}

// Same 600 ms window as SaveSoon in DesktopHost.cs; every request pushes the deadline out.
public struct SaveDebouncer {
    public static let delay = 0.6
    private var due: Double?

    public init() {}

    public mutating func request(at now: Double) {
        due = now + Self.delay
    }

    public mutating func takeIfDue(at now: Double) -> Bool {
        guard let d = due, now >= d else { return false }
        due = nil
        return true
    }
}
