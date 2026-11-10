import Testing
@testable import DesklandCore

// Mirrors OnSnapshot / OnRecord / the recprogress branch in DesktopHost.cs.
@Suite struct PageMessageTests {
    @Test func ready() {
        #expect(PageMessage.parse("ready") == .ready)
    }

    @Test func snapshotOK() {
        #expect(PageMessage.parse("snapshot|thumbdata|pngdata") == .snapshot(thumb: "thumbdata", png: "pngdata"))
    }

    @Test func snapshotPngKeepsPipes() {
        #expect(PageMessage.parse("snapshot|t|a|b|c") == .snapshot(thumb: "t", png: "a|b|c"))
    }

    @Test func snapshotError() {
        #expect(PageMessage.parse("snapshot|error|boom") == .snapshotError("boom"))
        #expect(PageMessage.parse("snapshot|error|a|b") == .snapshotError("a|b"))
    }

    @Test func snapshotTooShort() {
        #expect(PageMessage.parse("snapshot|only") == .snapshotBadData)
        #expect(PageMessage.parse("snapshot") == .snapshotBadData)
    }

    @Test func recordProgress() {
        #expect(PageMessage.parse("recprogress|0.25") == .recordProgress("0.25"))
    }

    @Test func recordOK() {
        #expect(PageMessage.parse("record|video/mp4|poster|video") == .record(mime: "video/mp4", poster: "poster", video: "video"))
    }

    @Test func recordVideoKeepsPipes() {
        #expect(PageMessage.parse("record|m|p|v|w") == .record(mime: "m", poster: "p", video: "v|w"))
    }

    @Test func recordError() {
        #expect(PageMessage.parse("record|error|no codec") == .recordError("no codec"))
    }

    // C# takes msg.Substring(13) whenever the shape is record|error|... — 13 chars, not 13 minus a pipe.
    @Test func recordErrorSubstring13() {
        #expect(PageMessage.parse("record|error|a|b|c|d") == .recordError("a|b|c|d"))
        #expect(PageMessage.parse("record|error|") == .recordError(""))
    }

    @Test func recordTooShort() {
        #expect(PageMessage.parse("record|m|p") == .recordBadData)
        #expect(PageMessage.parse("record") == .recordBadData)
    }

    @Test func unknown() {
        #expect(PageMessage.parse("nope|x") == .unknown)
        #expect(PageMessage.parse("") == .unknown)
    }
}
