import AppKit
import CoreGraphics
import DesklandCore
import WebKit

// Desktop-level window on the main display with the theme page inside (TASK-002.03).
@MainActor
final class WallpaperController: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let web: WKWebView
    private let reader = IconReader()
    private var iconTimer: Timer?
    private var pauseTimer: Timer?
    private var iconGate = ChangeGate<String>()
    private var pauseGate = ChangeGate<Bool>()
    private var page: String
    private var ready = false
    private var wasTrusted = IconReader.isTrusted

    var manualPause: Bool
    var screenLocked = false { didSet { pollPause() } }
    var displayAsleep = false { didSet { pollPause() } }
    private(set) var lastIcons = ""

    var settingsMessage: () -> String = { "" }
    var onIcons: (String) -> Void = { _ in }
    var onSnapshot: (PageMessage) -> Void = { _ in }
    var onRecord: (PageMessage) -> Void = { _ in }
    var onRecordProgress: (String) -> Void = { _ in }

    init(page: String, manualPause: Bool, scheme: SchemeHandler) {
        self.page = page
        self.manualPause = manualPause
        let screen = NSScreen.screens[0]
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        web = WebViewFactory.make(scheme: scheme, onMessage: { _ in })
        super.init()
        // The factory's handler is replaced so messages reach this controller without a retain cycle.
        web.configuration.userContentController.removeScriptMessageHandler(forName: "deskland")
        web.configuration.userContentController.add(WeakScriptHandler { [weak self] in self?.onPageMessage($0) }, name: "deskland")
        web.navigationDelegate = self
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = NSColor(red: 26 / 255, green: 163 / 255, blue: 196 / 255, alpha: 1)
        window.contentView = web
        window.title = "DesklandWindow"
    }

    func start() {
        window.orderFrontRegardless()
        load()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollIcons() }
        }
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPause() }
        }
        Log.write("已挂载，屏幕 \(screen.frame)")
    }

    func shutdown() {
        iconTimer?.invalidate(); pauseTimer?.invalidate()
        web.navigationDelegate = nil
        window.orderOut(nil)
        window.close()
    }

    func updateFrame() { window.setFrame(screen.frame, display: true) }

    func reload() { web.reload() }

    func loadPage(_ newPage: String) { page = newPage; load() }

    func post(_ json: String) { WebViewFactory.post(json, to: web) }

    private var screen: NSScreen { NSScreen.screens[0] }

    private func load() {
        ready = false
        if let url = URL(string: "deskland://app/\(page)?wallpaper=1") { web.load(URLRequest(url: url)) }
    }

    // MARK: page messages

    private func onPageMessage(_ msg: String) {
        switch PageMessage.parse(msg) {
        case .snapshot, .snapshotError, .snapshotBadData: onSnapshot(PageMessage.parse(msg))
        case .record, .recordError, .recordBadData: onRecord(PageMessage.parse(msg))
        case let .recordProgress(p): onRecordProgress(p)
        case .ready, .unknown:
            // The page is up: settings first (shoreline depends on them), then icons and pause state.
            ready = true
            post(settingsMessage())
            iconGate.reset(); pauseGate.reset()
            pollIcons(); pollPause()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        Log.write("壁纸页面加载失败：\(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.write("壁纸页面进程退出，重新载入")
        load()
    }

    // MARK: icons

    func pollIcons() {
        guard ready else { return }
        let trusted = IconReader.isTrusted
        if trusted != wasTrusted { wasTrusted = trusted; iconGate.reset() }
        let message: HostMessage
        if !trusted || !IconReader.iconsVisible {
            message = .icons(visible: false, rects: [])
        } else {
            guard let icons = reader.read() else { return }
            let f = screen.frame
            let geometry = DisplayGeometry(frame: Rect(x: 0, y: 0, width: f.width, height: f.height), scale: screen.backingScaleFactor)
            message = .icons(visible: true, rects: IconCoordinates.physicalRects(fromIcons: icons, display: geometry))
        }
        let json = message.wireString
        guard iconGate.shouldSend(json) else { return }
        lastIcons = json
        Log.write("图标变化：\(json.prefix(120))")
        onIcons(json)
        post(json)
    }

    // MARK: pause

    func pollPause() {
        guard ready else { return }
        let input = pauseInput()
        let pause = PauseDecision.shouldPause(input)
        guard pauseGate.shouldSend(pause) else { return }
        post(HostMessage.pause(pause).wireString)
        Log.write((pause ? "暂停" : "继续播放") + "：\(input)")
    }

    private func pauseInput() -> PauseInput {
        let f = screen.frame, v = screen.visibleFrame
        // visibleFrame is bottom-left based; the window list and AX are top-left based.
        let screenFrame = Rect(x: 0, y: 0, width: f.width, height: f.height)
        let visibleFrame = Rect(x: v.minX - f.minX, y: f.maxY - v.maxY, width: v.width, height: v.height)
        return PauseInput(manualPause: manualPause, frontWindows: frontWindowBounds(), screenFrame: screenFrame,
                          visibleFrame: visibleFrame, fullscreenSpace: !window.occlusionState.contains(.visible),
                          screenLocked: screenLocked, displayAsleep: displayAsleep)
    }

    // Normal-layer windows of the frontmost app, never our own.
    private func frontWindowBounds() -> [Rect] {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b) else { return nil }
            return Rect(x: r.minX, y: r.minY, width: r.width, height: r.height)
        }
    }
}
