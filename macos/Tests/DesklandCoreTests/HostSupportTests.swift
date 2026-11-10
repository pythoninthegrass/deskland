import Foundation
import Testing
@testable import DesklandCore

@Suite struct IconLabelTests {
    // AX reports the 48x48 icon only; the label sits 8 pt below, centered, at most 114x28 (TASK-002.01 measurements).
    @Test func boundsCoverIconAndLabelUpperBound() {
        let b = IconLabel.bounds(forIcon: Rect(x: 100, y: 200, width: 48, height: 48))
        #expect(b == Rect(x: 67, y: 200, width: 114, height: 84))
    }
}

@Suite struct ChangeGateTests {
    @Test func sendsFirstValueAndChangesOnly() {
        var g = ChangeGate<String>()
        let sent = ["a", "a", "b", "b"].map { g.shouldSend($0) }
        #expect(sent == [true, false, true, false])
    }

    @Test func resetForcesNextSend() {
        var g = ChangeGate<Bool>()
        let first = g.shouldSend(true)
        g.reset()
        let again = g.shouldSend(true)
        #expect(first && again)
    }
}

@Suite struct DesktopIconsTests {
    @Test func visibleByDefault() {
        #expect(DesktopIcons.isVisible(standardHideDesktopIcons: nil, createDesktop: nil))
    }

    @Test func hiddenWhenShowItemsOffOrFinderDesktopDisabled() {
        #expect(!DesktopIcons.isVisible(standardHideDesktopIcons: true, createDesktop: nil))
        #expect(!DesktopIcons.isVisible(standardHideDesktopIcons: nil, createDesktop: false))
        #expect(DesktopIcons.isVisible(standardHideDesktopIcons: false, createDesktop: true))
    }
}

@Suite struct LaunchCommandTests {
    @Test func parsesFlags() {
        #expect(LaunchCommand.parse([]) == .run(autostart: false))
        #expect(LaunchCommand.parse(["--autostart"]) == .run(autostart: true))
        #expect(LaunchCommand.parse(["--settings"]) == .settings)
        #expect(LaunchCommand.parse(["--exit"]) == .exit)
        #expect(LaunchCommand.parse(["--menu"]) == .menu)
    }

    @Test func secondLaunchForwardsToRunningInstance() {
        #expect(LaunchCommand.run(autostart: false).forwarded == .settings)
        #expect(LaunchCommand.run(autostart: true).forwarded == nil)
        #expect(LaunchCommand.exit.forwarded == .exit)
        #expect(LaunchCommand.menu.forwarded == .menu)
    }

    @Test func wireNameRoundTrips() {
        for c in [LaunchCommand.settings, .exit, .menu] {
            #expect(LaunchCommand(wireName: c.wireName) == c)
        }
        #expect(LaunchCommand(wireName: "bogus") == nil)
    }
}

@Suite struct ShareFileTests {
    @Test func decodesDataURLAndBareBase64() {
        #expect(ShareFile.decode("data:image/png;base64,aGk=") == Data("hi".utf8))
        #expect(ShareFile.decode("aGk=") == Data("hi".utf8))
        #expect(ShareFile.decode("data:image/png;base64,***") == nil)
    }

    @Test func fileNameMatchesWindowsHost() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9, minute: 5, second: 3))!
        #expect(ShareFile.fileName(date: date, ext: "png", timeZone: cal.timeZone) == "Deskland 2026-11-07 090503.png")
    }

    @Test func videoExtensionFollowsMime() {
        #expect(ShareFile.videoExtension(mime: "video/webm") == "webm")
        #expect(ShareFile.videoExtension(mime: "video/mp4;codecs=avc1") == "mp4")
    }
}

@Suite struct ByteRangeTests {
    @Test func parsesClosedOpenAndSuffixRanges() {
        #expect(ByteRange.parse("bytes=0-99", length: 1000) == 0...99)
        #expect(ByteRange.parse("bytes=500-", length: 1000) == 500...999)
        #expect(ByteRange.parse("bytes=-100", length: 1000) == 900...999)
        #expect(ByteRange.parse("bytes=0-5000", length: 1000) == 0...999)
    }

    @Test func rejectsUnsatisfiable() {
        #expect(ByteRange.parse("bytes=2000-", length: 1000) == nil)
        #expect(ByteRange.parse("items=0-1", length: 1000) == nil)
        #expect(ByteRange.parse("bytes=9-3", length: 1000) == nil)
    }
}

@Suite struct ScriptBridgeTests {
    @Test func dispatchWrapsMessageAsJSStringLiteral() {
        #expect(ScriptBridge.dispatch(#"{"t":"pause","v":true}"#)
            == #"window.chrome.webview.__dispatch("{\"t\":\"pause\",\"v\":true}")"#)
    }

    @Test func shimDefinesWebviewApi() {
        for needle in ["postMessage", "addEventListener", "removeEventListener", "__dispatch", "messageHandlers.deskland"] {
            #expect(ScriptBridge.shim.contains(needle))
        }
    }
}

@Suite struct ResourceResolverTests {
    func fixture() throws -> (ResourceResolver, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deskland-\(UUID().uuidString)")
        let page = root.appendingPathComponent("page"), share = root.appendingPathComponent("share")
        try FileManager.default.createDirectory(at: page.appendingPathComponent("i18n"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        for f in ["settings.html", "flat.html", "paid.html", "i18n/en.json"] {
            try Data(f.utf8).write(to: page.appendingPathComponent(f))
        }
        try Data("secret".utf8).write(to: root.appendingPathComponent("secret.txt"))
        try Data("mp4".utf8).write(to: share.appendingPathComponent("a b.mp4"))
        let catalog = try ThemeCatalog(data: Data(#"""
        {"themes":[{"id":"beach","status":"ready","product":"free","page":"flat.html"},
                   {"id":"paid","status":"ready","product":"pro","page":"paid.html"}]}
        """#.utf8))
        return (ResourceResolver(pageDir: page, shareDir: share, catalog: catalog), root)
    }

    @Test func servesPageFilesWithMime() throws {
        let (r, _) = try fixture()
        let h = try #require(r.resolve(URL(string: "deskland://app/settings.html?v=1")!))
        #expect(h.file.lastPathComponent == "settings.html")
        #expect(h.mime == "text/html; charset=utf-8")
        #expect(r.resolve(URL(string: "deskland://app/i18n/en.json")!)?.mime == "application/json; charset=utf-8")
    }

    @Test func servesShareFolderWithEscapedNames() throws {
        let (r, _) = try fixture()
        #expect(r.resolve(URL(string: "deskland://share/a%20b.mp4")!)?.mime == "video/mp4")
    }

    @Test func rejectsTraversalUnknownHostAndMissingFiles() throws {
        let (r, _) = try fixture()
        #expect(r.resolve(URL(string: "deskland://app/../secret.txt")!) == nil)
        #expect(r.resolve(URL(string: "deskland://app/%2e%2e/secret.txt")!) == nil)
        #expect(r.resolve(URL(string: "deskland://share/..%2Fsecret.txt")!) == nil)
        #expect(r.resolve(URL(string: "deskland://other/settings.html")!) == nil)
        #expect(r.resolve(URL(string: "deskland://app/missing.html")!) == nil)
    }

    @Test func refusesPagesOfThemesThatAreNotFree() throws {
        let (r, _) = try fixture()
        #expect(r.resolve(URL(string: "deskland://app/flat.html")!) != nil)
        #expect(r.resolve(URL(string: "deskland://app/paid.html")!) == nil)
    }
}

@Suite struct LocalizerTests {
    func pageDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deskland-\(UUID().uuidString)/i18n")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"host":{"traySettings":"设置…","onlyZh":"仅中文","hi":"你好 {name}"}}"#.utf8)
            .write(to: dir.appendingPathComponent("zh-CN.json"))
        try Data(#"{"host":{"traySettings":"Settings…","trayExit":"Exit"}}"#.utf8)
            .write(to: dir.appendingPathComponent("en.json"))
        return dir.deletingLastPathComponent()
    }

    @Test func systemLanguageIsChineseOrEnglish() {
        #expect(Localizer.systemLanguage(preferred: ["zh-Hans-CN", "en"]) == "zh-CN")
        #expect(Localizer.systemLanguage(preferred: ["zh-Hant-TW"]) == "zh-CN")
        #expect(Localizer.systemLanguage(preferred: ["fr-FR"]) == "en")
        #expect(Localizer.systemLanguage(preferred: []) == "en")
    }

    @Test func settingOverridesSystem() throws {
        let dir = try pageDir()
        #expect(Localizer(pageDir: dir, setting: "en", preferred: ["zh-Hans"]).code == "en")
        #expect(Localizer(pageDir: dir, setting: "auto", preferred: ["zh-Hans"]).code == "zh-CN")
        #expect(Localizer(pageDir: dir, setting: "de", preferred: ["en-US"]).code == "en")
    }

    @Test func fallsBackCurrentThenEnglishThenChineseThenKey() throws {
        let l = Localizer(pageDir: try pageDir(), setting: "en", preferred: [])
        #expect(l.t("traySettings") == "Settings…")
        #expect(l.t("onlyZh") == "仅中文")
        #expect(l.t("nope") == "nope")
        #expect(l.t("hi", ["name": "Lance"]) == "你好 Lance")
    }
}

@Suite struct SettingsMessageTests {
    @Test func parsesEveryPageMessage() {
        #expect(SettingsMessage.parse(#"{"t":"hello"}"#) == .hello)
        #expect(SettingsMessage.parse(#"{"t":"set","theme":"beach","key":"palms","value":4}"#)
            == .set(theme: "beach", key: "palms", value: .number(4)))
        #expect(SettingsMessage.parse(#"{"t":"reset","theme":"beach"}"#) == .reset(theme: "beach"))
        #expect(SettingsMessage.parse(#"{"t":"theme","id":"meadow"}"#) == .theme(id: "meadow"))
        #expect(SettingsMessage.parse(#"{"t":"theme"}"#) == .theme(id: nil))
        #expect(SettingsMessage.parse(#"{"t":"lang","v":"en"}"#) == .lang("en"))
        #expect(SettingsMessage.parse(#"{"t":"autostart","v":true}"#) == .autostart(true))
        #expect(SettingsMessage.parse(#"{"t":"autostart","v":"yes"}"#) == .autostart(false))
        #expect(SettingsMessage.parse(#"{"t":"share"}"#) == .share)
        #expect(SettingsMessage.parse(#"{"t":"shareVideo"}"#) == .shareVideo)
        #expect(SettingsMessage.parse(#"{"t":"openShare"}"#) == .openShare)
        #expect(SettingsMessage.parse(#"{"t":"revealShare"}"#) == .revealShare)
        #expect(SettingsMessage.parse(#"{"t":"openWebsite"}"#) == .openWebsite)
        #expect(SettingsMessage.parse(#"{"t":"autostartWarnSeen"}"#) == .autostartWarnSeen)
    }

    @Test func ignoresMalformedAndUpdateMessages() {
        #expect(SettingsMessage.parse("not json") == .unknown)
        #expect(SettingsMessage.parse(#"{"t":"updateProgram"}"#) == .unknown)
        #expect(SettingsMessage.parse(#"{"t":"set","theme":"beach"}"#) == .unknown)
        #expect(SettingsMessage.parse(#"{"t":"lang"}"#) == .unknown)
    }
}

@Suite struct SettingsReplyTests {
    @Test func initMatchesWindowsKeyOrder() {
        var s = Settings()
        s.set(theme: "beach", key: "palms", value: .number(4))
        let json = SettingsReply.initial(settings: s, screenWidth: 3024, screenHeight: 1964, autostart: true,
                                         langEff: "en", langSys: "zh-CN")
        #expect(json == #"{"t":"init","theme":"beach","params":{"beach":{"palms":4}},"screen":{"w":3024,"h":1964},"autostart":true,"autostartWarn":false,"autostartSw":"","lang":"auto","langEff":"en","langSys":"zh-CN"}"#)
    }

    @Test func smallReplies() {
        #expect(SettingsReply.themeChanged("beach") == #"{"t":"themeChanged","id":"beach"}"#)
        #expect(SettingsReply.lang("en", effective: "en", system: "zh-CN") == #"{"t":"lang","v":"en","eff":"en","sys":"zh-CN"}"#)
        #expect(SettingsReply.autostart(false) == #"{"t":"autostart","v":false}"#)
        #expect(SettingsReply.recordProgress("0.5") == #"{"t":"recProgress","p":0.5}"#)
    }

    @Test func shareResults() {
        #expect(SettingsReply.shareFailure("boom") == #"{"t":"shareResult","ok":false,"path":null,"msg":"boom"}"#)
        #expect(SettingsReply.shareImage(thumb: "T", path: "/p.png") == #"{"t":"shareResult","ok":true,"thumb":"T","path":"/p.png"}"#)
        #expect(SettingsReply.shareVideo(poster: "P", path: "/p.mp4", url: "deskland://share/p.mp4")
            == #"{"t":"shareResult","ok":true,"kind":"video","thumb":"P","path":"/p.mp4","url":"deskland://share/p.mp4"}"#)
    }
}
