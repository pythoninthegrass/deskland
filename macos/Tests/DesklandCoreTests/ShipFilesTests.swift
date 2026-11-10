import Foundation
import Testing

// Runs against tools/ship-files.txt, the list shared by build-installer.ps1 and macos/build.sh.
@Suite struct ShipFilesTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    struct Entry {
        let scope: String
        let path: String
    }

    func entries() throws -> [Entry] {
        let text = try String(contentsOf: Self.root.appendingPathComponent("tools/ship-files.txt"), encoding: .utf8)
        return text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { return nil }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            return Entry(scope: parts[0], path: parts.count > 1 ? parts[1] : "")
        }
    }

    func themes() throws -> [[String: Any]] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("prototype/themes.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["themes"] as? [[String: Any]])
    }

    @Test func scopesAreKnownAndPathsAreSafe() throws {
        for e in try entries() {
            #expect(["source", "all"].contains(e.scope), "unknown scope for \(e.path)")
            #expect(!e.path.isEmpty)
            #expect(!e.path.hasPrefix("/") && !e.path.contains("\\") && !e.path.contains(".."), "unsafe path \(e.path)")
            #expect(e.path.rangeOfCharacter(from: CharacterSet(charactersIn: "\"$\r\n")) == nil, "unsafe path \(e.path)")
        }
    }

    @Test func everyListedFileExistsAndIsListedOnce() throws {
        let list = try entries()
        #expect(Set(list.map(\.path)).count == list.count, "duplicate entries")
        for e in list {
            #expect(FileManager.default.fileExists(atPath: Self.root.appendingPathComponent(e.path).path), "missing \(e.path)")
        }
    }

    @Test func sourceListIncludesBothHostSources() throws {
        let paths = Set(try entries().map(\.path))
        #expect(paths.contains("host/DesktopHost.cs"))
        #expect(paths.contains("host/Themes.cs"))
    }

    @Test func buildScriptsAreListedAsSource() throws {
        let sources = Set(try entries().filter { $0.scope == "source" }.map(\.path))
        #expect(sources.contains("tools/ship-files.txt"))
        #expect(sources.contains("tools/build-installer.ps1"))
        #expect(sources.contains("prototype/serve.mjs"))
    }

    @Test func everyThemeThumbnailIsShipped() throws {
        let shipped = Set(try entries().filter { $0.scope == "all" }.map(\.path))
        for theme in try themes() {
            let thumb = try #require(theme["thumb"] as? String)
            let range = try #require(thumb.range(of: #"url\(thumbs/([^)?]+)"#, options: .regularExpression))
            let name = String(thumb[range]).dropFirst("url(thumbs/".count)
            let decoded = try #require(String(name).removingPercentEncoding)
            #expect(shipped.contains("prototype/thumbs/\(decoded)"), "thumbnail not shipped: \(decoded)")
        }
    }

    @Test func onlyReadyThemePagesAreShipped() throws {
        let pages = Set(try themes().filter { ($0["status"] as? String) == "ready" }.compactMap { $0["page"] as? String })
        let shippedPages = Set(try entries().filter { $0.scope == "all" && $0.path.hasPrefix("prototype/") && $0.path.hasSuffix(".html") }
            .map { String($0.path.dropFirst("prototype/".count)) })
        #expect(shippedPages == pages.union(["settings.html"]))
    }
}
