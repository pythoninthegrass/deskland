import Foundation
import Testing
@testable import DesklandCore

@Suite struct SettingsTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deskland-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func defaults() {
        let s = Settings()
        #expect(s.theme == "beach")
        #expect(s.lang == "auto")
        #expect(s.values(for: "beach").isEmpty)
    }

    @Test func serializesVersionThemeLangParams() {
        var s = Settings()
        s.theme = "meadow"
        s.lang = "en"
        s.set(theme: "meadow", key: "sigma", value: .number(80))
        s.set(theme: "meadow", key: "seed", value: .number(7))
        #expect(s.serialized == #"{"version":1,"theme":"meadow","lang":"en","params":{"meadow":{"sigma":80,"seed":7}}}"#)
    }

    @Test func setOverwritesInPlace() {
        var s = Settings()
        s.set(theme: "beach", key: "a", value: .number(1))
        s.set(theme: "beach", key: "b", value: .number(2))
        s.set(theme: "beach", key: "a", value: .number(3))
        #expect(s.serialized == #"{"version":1,"theme":"beach","lang":"auto","params":{"beach":{"a":3,"b":2}}}"#)
    }

    @Test func resetRemovesThemeParams() {
        var s = Settings()
        s.set(theme: "beach", key: "a", value: .number(1))
        s.set(theme: "meadow", key: "b", value: .number(2))
        s.reset(theme: "beach")
        #expect(s.serialized == #"{"version":1,"theme":"beach","lang":"auto","params":{"meadow":{"b":2}}}"#)
    }

    @Test func roundTripThroughFile() throws {
        let dir = try tempDir()
        var s = Settings()
        s.theme = "meadow"
        s.lang = "zh-CN"
        s.set(theme: "meadow", key: "tint", value: .string("#a1b2c3"))
        try s.save(to: dir)
        let loaded = Settings.load(from: dir)
        #expect(loaded == s)
    }

    @Test func saveCreatesDirectory() throws {
        let dir = try tempDir().appendingPathComponent("nested/deeper")
        try Settings().save(to: dir)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path))
    }

    @Test func missingFileGivesDefaults() throws {
        #expect(Settings.load(from: try tempDir()) == Settings())
    }

    @Test func corruptFileGivesDefaults() throws {
        let dir = try tempDir()
        try "not json".write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        #expect(Settings.load(from: dir) == Settings())
    }

    @Test func wrongTypesAreIgnored() throws {
        let dir = try tempDir()
        try #"{"theme":5,"lang":"en","params":{"beach":{"a":1},"bad":3}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let s = Settings.load(from: dir)
        #expect(s.theme == "beach")
        #expect(s.lang == "en")
        #expect(s.values(for: "beach").count == 1)
        #expect(s.values(for: "bad").isEmpty)
    }

    @Test func unknownKeysSurviveRoundTrip() throws {
        let dir = try tempDir()
        try #"{"version":1,"theme":"meadow","future":{"x":[1,2]},"lang":"en","params":{}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        var s = Settings.load(from: dir)
        s.set(theme: "meadow", key: "a", value: .number(1))
        try s.save(to: dir)
        let text = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(text == #"{"version":1,"theme":"meadow","lang":"en","params":{"meadow":{"a":1}},"future":{"x":[1,2]}}"#)
    }

    @Test func profileDirOverride() {
        let dir = ProfileDirectory.resolve(environment: ["DESKLAND_PROFILE_DIR": "/tmp/qa/./profile"], home: URL(fileURLWithPath: "/Users/x"))
        #expect(dir.path == "/tmp/qa/profile")
    }

    @Test func emptyOverrideIsIgnored() {
        let dir = ProfileDirectory.resolve(environment: ["DESKLAND_PROFILE_DIR": ""], home: URL(fileURLWithPath: "/Users/x"))
        #expect(dir.path == "/Users/x/Library/Application Support/DesklandPreview")
    }

    @Test func defaultProfileDir() {
        let dir = ProfileDirectory.resolve(environment: [:], home: URL(fileURLWithPath: "/Users/x"))
        #expect(dir.path == "/Users/x/Library/Application Support/DesklandPreview")
    }
}

@Suite struct SaveDebouncerTests {
    @Test func notDueWithoutRequest() {
        var d = SaveDebouncer()
        let due = d.takeIfDue(at: 100)
        #expect(!due)
    }

    @Test func dueAfter600ms() {
        var d = SaveDebouncer()
        d.request(at: 10)
        let early = d.takeIfDue(at: 10.599)
        let onTime = d.takeIfDue(at: 10.6)
        #expect(!early)
        #expect(onTime)
    }

    @Test func consumedOnce() {
        var d = SaveDebouncer()
        d.request(at: 0)
        let first = d.takeIfDue(at: 1)
        let second = d.takeIfDue(at: 2)
        #expect(first)
        #expect(!second)
    }

    @Test func laterRequestPushesDeadline() {
        var d = SaveDebouncer()
        d.request(at: 0)
        d.request(at: 0.5)
        let early = d.takeIfDue(at: 0.7)
        let late = d.takeIfDue(at: 1.1)
        #expect(!early)
        #expect(late)
    }
}
