import Foundation
import Testing
@testable import DesklandCore

// Runs against the shared prototype/themes.json, not a copy.
@Suite struct ThemeCatalogTests {
    static let themesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("prototype/themes.json")

    func catalog() throws -> ThemeCatalog {
        try ThemeCatalog(data: Data(contentsOf: Self.themesURL))
    }

    @Test func counts() throws {
        let c = try catalog()
        #expect(c.themes.count == 13)
        #expect(c.themes.filter { $0.status == "ready" }.count == 2)
    }

    @Test func freeThemesServePages() throws {
        let c = try catalog()
        #expect(c.page(for: "beach") == "flat.html")
        #expect(c.page(for: "meadow") == "meadow.html")
        #expect(c.isAllowed("beach"))
        #expect(c.isAllowed("meadow"))
    }

    @Test func lockedThemesHaveNoPageAndAreNotAllowed() throws {
        let c = try catalog()
        let locked = c.themes.filter { $0.status != "ready" }
        #expect(locked.count == 11)
        for t in locked {
            #expect(t.page == nil)
            #expect(c.page(for: t.id) == nil)
            #expect(!c.isAllowed(t.id))
        }
    }

    @Test func lockedThemesNeverSwitch() throws {
        let c = try catalog()
        for t in c.themes where t.status != "ready" {
            #expect(c.switchRequest(to: t.id, current: "beach") == .rejected(keep: "beach"))
        }
    }

    @Test func unknownOrNilThemeRejected() throws {
        let c = try catalog()
        #expect(c.switchRequest(to: "nope", current: "meadow") == .rejected(keep: "meadow"))
        #expect(c.switchRequest(to: nil, current: "meadow") == .rejected(keep: "meadow"))
    }

    @Test func switchToOtherFreeThemeLoadsPage() throws {
        #expect(try catalog().switchRequest(to: "meadow", current: "beach") == .load(theme: "meadow", page: "meadow.html"))
    }

    @Test func switchToCurrentThemeIsNoOp() throws {
        #expect(try catalog().switchRequest(to: "beach", current: "beach") == .unchanged)
    }

    // A ready theme with no product tag is refused so a new paid theme can't go free by accident.
    @Test func readyWithoutProductIsDenied() throws {
        let json = #"{"version":1,"themes":[{"id":"x","status":"ready","page":"x.html"},{"id":"y","status":"ready","product":"free","page":"y.html"}]}"#
        let c = try ThemeCatalog(data: Data(json.utf8))
        #expect(c.page(for: "x") == "x.html")
        #expect(!c.isAllowed("x"))
        #expect(c.isAllowed("y"))
    }
}
