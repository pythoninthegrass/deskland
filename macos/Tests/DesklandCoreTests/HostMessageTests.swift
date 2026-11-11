import Testing
@testable import DesklandCore

// Expected strings are the exact bytes DesktopHost.cs posts to the wallpaper page.
@Suite struct HostMessageTests {
    @Test func iconsWithRects() {
        let m = HostMessage.icons(visible: true, rects: [IconRect(left: 10, top: 20, right: 58, bottom: 68), IconRect(left: 0, top: 0, right: 1, bottom: 2)])
        #expect(m.wireString == #"{"t":"icons","vis":true,"r":[[10,20,58,68],[0,0,1,2]]}"#)
    }

    @Test func iconsEmptyAndHidden() {
        #expect(HostMessage.icons(visible: false, rects: []).wireString == #"{"t":"icons","vis":false,"r":[]}"#)
    }

    @Test func iconsNegativeCoordinates() {
        let m = HostMessage.icons(visible: true, rects: [IconRect(left: -4, top: -1, right: 44, bottom: 47)])
        #expect(m.wireString == #"{"t":"icons","vis":true,"r":[[-4,-1,44,47]]}"#)
    }

    @Test func pause() {
        #expect(HostMessage.pause(true).wireString == #"{"t":"pause","v":true}"#)
        #expect(HostMessage.pause(false).wireString == #"{"t":"pause","v":false}"#)
    }

    @Test func settingsKeepsInsertionOrder() {
        let v = JSONValue.object([("sigma", .number(72)), ("tint", .string("#fff")), ("on", .bool(true))])
        #expect(HostMessage.settings(v).wireString == ##"{"t":"settings","v":{"sigma":72,"tint":"#fff","on":true}}"##)
    }

    @Test func settingsSingleKey() {
        #expect(HostMessage.settings(.object([("sigma", .number(0.5))])).wireString == #"{"t":"settings","v":{"sigma":0.5}}"#)
    }

    @Test func resetSnapshotRecord() {
        #expect(HostMessage.reset.wireString == #"{"t":"reset"}"#)
        #expect(HostMessage.snapshot.wireString == #"{"t":"snapshot"}"#)
        #expect(HostMessage.record.wireString == #"{"t":"record"}"#)
    }
}

// JavaScriptSerializer escaping: quote, backslash, control characters, and the HTML-sensitive trio.
@Suite struct JSONSerializationTests {
    @Test func numbers() {
        #expect(JSONValue.number(1).serialized == "1")
        #expect(JSONValue.number(1.0).serialized == "1")
        #expect(JSONValue.number(-3).serialized == "-3")
        #expect(JSONValue.number(0.35).serialized == "0.35")
    }

    @Test func escapes() {
        #expect(JSONValue.string("a\"b\\c\n\t\r").serialized == #""a\"b\\c\n\t\r""#)
        #expect(JSONValue.string("\u{01}").serialized == #""\u0001""#)
        #expect(JSONValue.string("it's <b>").serialized == #""it\u0027s \u003cb\u003e""#)
    }

    @Test func nonAsciiPassesThrough() {
        #expect(JSONValue.string("云团大小").serialized == "\"云团大小\"")
    }

    @Test func roundTripPreservesOrder() throws {
        let text = #"{"z":1,"a":[true,null,"x"],"m":{"k":2.5}}"#
        #expect(try JSONValue.parse(text).serialized == text)
    }

    @Test func parseRejectsGarbage() {
        #expect(throws: JSONError.self) { try JSONValue.parse("{") }
        #expect(throws: JSONError.self) { try JSONValue.parse("{} x") }
    }

    @Test func parseUnicodeEscapes() throws {
        #expect(try JSONValue.parse(#""云""#) == .string("云"))
    }

    @Test func inset() {
        #expect(HostMessage.inset(bottom: 96).wireString == #"{"t":"inset","b":96}"#)
        #expect(HostMessage.inset(bottom: 0).wireString == #"{"t":"inset","b":0}"#)
    }
}
