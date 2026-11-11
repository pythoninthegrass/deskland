import AppKit
import DesklandCore

// App lifecycle: status item, hotkey, wallpaper window, settings window and the settings message protocol.
@MainActor
final class HostController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let showSettingsOnLaunch: Bool
    private var settings = Settings.load(from: AppPaths.profileDir)
    private var localizer: Localizer
    private let catalog: ThemeCatalog
    private let scheme: SchemeHandler
    private var wallpaper: WallpaperController?
    private var settingsWindow: SettingsWindow?
    private var statusItem: NSStatusItem?
    private var menu = NSMenu()
    private var hotkey: Hotkey?
    private var commandObserver: NSObjectProtocol?
    private var watchTimer: Timer?
    private var saveDebouncer = SaveDebouncer()
    private var nextStart: Date? = Date()
    private var manualPause = false
    private var exiting = false
    private var lastShare: URL?
    private var snapshotTimeout: DispatchWorkItem?
    private var recordTimeout: DispatchWorkItem?
    private var pauseItem, settingsItem, reloadItem, autostartItem, accessibilityItem, exitItem: NSMenuItem!

    init(showSettings: Bool) {
        showSettingsOnLaunch = showSettings
        localizer = Localizer(pageDir: AppPaths.pageDir, setting: settings.lang, preferred: Locale.preferredLanguages)
        let data = (try? Data(contentsOf: AppPaths.pageDir.appendingPathComponent("themes.json"))) ?? Data("{\"themes\":[]}".utf8)
        catalog = (try? ThemeCatalog(data: data)) ?? (try! ThemeCatalog(data: Data("{\"themes\":[]}".utf8)))
        scheme = SchemeHandler(resolver: ResourceResolver(pageDir: AppPaths.pageDir, shareDir: AppPaths.shareDir, catalog: catalog))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("启动，页面目录：\(AppPaths.pageDir.path)")
        installMainMenu()
        installStatusItem()
        hotkey = Hotkey { [weak self] in self?.showMenu() }
        Log.write(hotkey != nil ? "快捷键 Ctrl+Option+H 已注册" : "快捷键 Ctrl+Option+H 注册失败")
        commandObserver = SingleInstance.listen { [weak self] in self?.handle($0) }
        observeSystemState()
        requestAccessibilityOnFirstLaunch()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch() }
        }
        startWallpaper()
        let loginLaunch = Autostart.launchedAsLoginItem()
        if loginLaunch { Log.write("由登录项启动") }
        if showSettingsOnLaunch && !loginLaunch { openSettings() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func handle(_ command: LaunchCommand) {
        switch command {
        case .settings: openSettings()
        case .menu: showMenu()
        case .exit: quit()
        case .run: break
        }
    }

    // MARK: status item and menus

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Deskland Preview")
        item.button?.toolTip = "Deskland Preview"
        settingsItem = NSMenuItem(title: "", action: #selector(menuSettings), keyEquivalent: "")
        pauseItem = NSMenuItem(title: "", action: #selector(menuPause), keyEquivalent: "")
        reloadItem = NSMenuItem(title: "", action: #selector(menuReload), keyEquivalent: "")
        autostartItem = NSMenuItem(title: "", action: #selector(menuAutostart), keyEquivalent: "")
        accessibilityItem = NSMenuItem(title: "", action: #selector(menuAccessibility), keyEquivalent: "")
        exitItem = NSMenuItem(title: "", action: #selector(menuExit), keyEquivalent: "")
        for i in [settingsItem, pauseItem, reloadItem, autostartItem, accessibilityItem, exitItem] { i?.target = self }
        for i in [settingsItem!, pauseItem!, reloadItem!, autostartItem!, NSMenuItem.separator(), accessibilityItem!,
                  NSMenuItem.separator(), exitItem!] { menu.addItem(i) }
        menu.delegate = self
        item.menu = menu
        statusItem = item
        applyMenuTexts()
    }

    private func applyMenuTexts() {
        settingsItem.title = localizer.t("traySettings")
        pauseItem.title = localizer.t("trayPause")
        reloadItem.title = localizer.t("trayReload")
        autostartItem.title = localizer.t("trayAutostartMac")
        accessibilityItem.title = localizer.t("trayAccessibility")
        exitItem.title = localizer.t("trayExit")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseItem.state = manualPause ? .on : .off
        autostartItem.state = Autostart.isEnabled ? .on : .off
        accessibilityItem.state = IconReader.isTrusted ? .on : .off
    }

    // Pops the menu at the pointer, like the Windows tray menu opened by the hotkey.
    private func showMenu() {
        guard !exiting else { return }
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func menuSettings() { openSettings() }
    @objc private func menuPause() {
        manualPause.toggle()
        wallpaper?.manualPause = manualPause
        wallpaper?.pollPause()
    }
    @objc private func menuReload() { wallpaper?.reload() }
    @objc private func menuAutostart() { Autostart.set(!Autostart.isEnabled) }
    @objc private func menuAccessibility() {
        IconReader.requestAccess()
        IconReader.openAccessibilitySettings()
    }
    @objc private func menuExit() { quit() }

    // Edit menu so copy/paste work in the settings window; an accessory app has no menu bar otherwise.
    private func installMainMenu() {
        let main = NSMenu()
        let edit = NSMenuItem(), editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    // MARK: accessibility

    // Prompt once on first launch; afterwards the menu entry is the way back. Icons start flowing once trust appears.
    private func requestAccessibilityOnFirstLaunch() {
        let marker = AppPaths.profileDir.appendingPathComponent("accessibility.prompted")
        guard !IconReader.isTrusted, !FileManager.default.fileExists(atPath: marker.path) else { return }
        IconReader.requestAccess()
        try? FileManager.default.createDirectory(at: AppPaths.profileDir, withIntermediateDirectories: true)
        try? Data().write(to: marker)
    }

    // MARK: system state for pause

    private func observeSystemState() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (HostController) -> Void) {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            }
        }
        on(ws, NSWorkspace.screensDidSleepNotification) { $0.wallpaper?.displayAsleep = true }
        on(ws, NSWorkspace.screensDidWakeNotification) { $0.wallpaper?.displayAsleep = false }
        on(dc, Notification.Name("com.apple.screenIsLocked")) { $0.wallpaper?.screenLocked = true }
        on(dc, Notification.Name("com.apple.screenIsUnlocked")) { $0.wallpaper?.screenLocked = false }
        on(ws, NSWorkspace.activeSpaceDidChangeNotification) { $0.wallpaper?.pollPause() }
        on(ws, NSWorkspace.didActivateApplicationNotification) { $0.wallpaper?.pollPause() }
        on(.default, NSApplication.didChangeScreenParametersNotification) { $0.wallpaper?.updateFrame(); $0.wallpaper?.pollInset() }
    }

    // MARK: wallpaper

    private func watch() {
        if saveDebouncer.takeIfDue(at: Date.timeIntervalSinceReferenceDate) { save() }
        if wallpaper == nil, !exiting, let due = nextStart, Date() >= due { startWallpaper() }
    }

    private func save() {
        do { try settings.save(to: AppPaths.profileDir) } catch { Log.write("保存设置失败：\(error.localizedDescription)") }
    }

    private func saveSoon() { saveDebouncer.request(at: Date.timeIntervalSinceReferenceDate) }

    private func startWallpaper() {
        nextStart = nil
        if !catalog.isAllowed(settings.theme) { settings.theme = catalog.isAllowed("beach") ? "beach" : "meadow" }
        guard let page = catalog.isAllowed(settings.theme) ? catalog.page(for: settings.theme) : nil else {
            Log.write("没有可加载的免费主题，5 秒后重试")
            nextStart = Date().addingTimeInterval(5)
            return
        }
        guard FileManager.default.fileExists(atPath: AppPaths.pageDir.appendingPathComponent(page).path) else {
            fail(localizer.t("errNoPage", ["path": AppPaths.pageDir.appendingPathComponent(page).path]))
            return
        }
        let w = WallpaperController(page: page, manualPause: manualPause, scheme: scheme)
        w.settingsMessage = { [weak self] in
            guard let self else { return "" }
            return HostMessage.settings(.object(self.settings.values(for: self.settings.theme))).wireString
        }
        w.onIcons = { [weak self] in self?.settingsWindow?.post($0) }
        w.onSnapshot = { [weak self] in self?.finishSnapshot($0) }
        w.onRecord = { [weak self] in self?.finishRecord($0) }
        w.onRecordProgress = { [weak self] in self?.settingsWindow?.post(SettingsReply.recordProgress($0)) }
        wallpaper = w
        w.start()
    }

    private func fail(_ message: String) {
        Log.write(message)
        let alert = NSAlert()
        alert.messageText = "Deskland Preview"
        alert.informativeText = message + "\n\n" + localizer.t("errSeeLog", ["path": AppPaths.logFile.path])
        alert.runModal()
        quit()
    }

    // MARK: settings window

    func openSettings() {
        guard !exiting else { return }
        if settingsWindow == nil {
            let w = SettingsWindow(scheme: scheme)
            w.onMessage = { [weak self] in self?.onSettingsMessage($0) }
            w.onClose = { [weak self] in self?.settingsWindow = nil }
            settingsWindow = w
            Log.write("打开设置窗口")
        }
        settingsWindow?.show()
    }

    private func onSettingsMessage(_ text: String) {
        guard let win = settingsWindow else { return }
        switch SettingsMessage.parse(text) {
        case .hello:
            let f = NSScreen.screens[0].frame, s = NSScreen.screens[0].backingScaleFactor
            win.post(SettingsReply.initial(settings: settings, screenWidth: Int(f.width * s), screenHeight: Int(f.height * s),
                                           autostart: Autostart.isEnabled, langEff: localizer.code, langSys: localizer.system))
            if let icons = wallpaper?.lastIcons, !icons.isEmpty { win.post(icons) }
        case let .set(theme, key, value):
            settings.set(theme: theme, key: key, value: value)
            if theme == settings.theme { wallpaper?.post(HostMessage.settings(.object([(key, value)])).wireString) }
            saveSoon()
        case let .reset(theme):
            settings.reset(theme: theme)
            if theme == settings.theme { wallpaper?.post(HostMessage.reset.wireString) }
            saveSoon()
            Log.write("恢复默认设置：\(theme)")
        case let .theme(id):
            switch catalog.switchRequest(to: id, current: settings.theme) {
            case let .rejected(keep):
                win.post(SettingsReply.themeChanged(keep))
                Log.write("拒绝未授权或未知主题切换：\(id ?? "null")")
            case .unchanged: break
            case let .load(theme, page):
                settings.theme = theme
                saveSoon()
                wallpaper?.loadPage(page)
                Log.write("切换主题：\(theme)")
            }
        case let .lang(v):
            settings.lang = v
            saveSoon()
            localizer = Localizer(pageDir: AppPaths.pageDir, setting: v, preferred: Locale.preferredLanguages)
            applyMenuTexts()
            win.post(SettingsReply.lang(v, effective: localizer.code, system: localizer.system))
        case let .autostart(on):
            Autostart.set(on)
            win.post(SettingsReply.autostart(Autostart.isEnabled))
        case .autostartWarnSeen: break
        case .share: requestSnapshot()
        case .shareVideo: requestRecording()
        case .openShare: if let f = lastShare, FileManager.default.fileExists(atPath: f.path) { NSWorkspace.shared.open(f) }
        case .revealShare:
            if let f = lastShare, FileManager.default.fileExists(atPath: f.path) { NSWorkspace.shared.activateFileViewerSelecting([f]) }
        case .openWebsite: NSWorkspace.shared.open(URL(string: "https://deskland.app/")!)
        case .unknown: break
        }
    }

    // MARK: share

    private func shareFailure(_ message: String) { settingsWindow?.post(SettingsReply.shareFailure(message)) }

    private func requestSnapshot() {
        guard let w = wallpaper else { return shareFailure(localizer.t("errNotReady")) }
        guard snapshotTimeout == nil else { return shareFailure(localizer.t("errBusyImage")) }
        let t = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finishSnapshot(.snapshotError(self?.localizer.t("errImageTimeout") ?? "")) }
        }
        snapshotTimeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: t)
        w.post(HostMessage.snapshot.wireString)
    }

    private func finishSnapshot(_ result: PageMessage) {
        guard snapshotTimeout != nil else { return }
        snapshotTimeout?.cancel(); snapshotTimeout = nil
        switch result {
        case let .snapshot(thumb, png):
            guard let data = ShareFile.decode(png) else { return shareFailure(localizer.t("errNoImage")) }
            do {
                let file = try writeShare(data, ext: "png")
                lastShare = file
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .png)
                if let image = NSImage(data: data) { pb.writeObjects([image]) }
                Log.write("已生成分享图：\(file.path)")
                settingsWindow?.post(SettingsReply.shareImage(thumb: thumb, path: file.path))
            } catch { shareFailure(error.localizedDescription) }
        case let .snapshotError(msg): Log.write("生成分享图失败：\(msg)"); shareFailure(msg)
        default: shareFailure(localizer.t("errBadData"))
        }
    }

    private func requestRecording() {
        guard let w = wallpaper else { return shareFailure(localizer.t("errNotReady")) }
        guard recordTimeout == nil else { return shareFailure(localizer.t("errBusyVideo")) }
        let t = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finishRecord(.recordError(self?.localizer.t("errVideoTimeout") ?? "")) }
        }
        recordTimeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: t)
        w.post(HostMessage.record.wireString)
    }

    private func finishRecord(_ result: PageMessage) {
        guard recordTimeout != nil else { return }
        recordTimeout?.cancel(); recordTimeout = nil
        switch result {
        case let .record(mime, poster, video):
            guard let data = ShareFile.decode(video) else { return shareFailure(localizer.t("errNoVideo")) }
            do {
                let file = try writeShare(data, ext: ShareFile.videoExtension(mime: mime))
                lastShare = file
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([file as NSURL])
                let escaped = file.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
                Log.write("已录好分享动画：\(file.path)（\(data.count / 1024) KB）")
                settingsWindow?.post(SettingsReply.shareVideo(poster: poster, path: file.path, url: "deskland://share/\(escaped)"))
            } catch { shareFailure(error.localizedDescription) }
        case let .recordError(msg): Log.write("录分享动画失败：\(msg)"); shareFailure(msg)
        default: shareFailure(localizer.t("errBadData"))
        }
    }

    private func writeShare(_ data: Data, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: AppPaths.shareDir, withIntermediateDirectories: true)
        let file = AppPaths.shareDir.appendingPathComponent(ShareFile.fileName(date: Date(), ext: ext))
        try data.write(to: file)
        return file
    }

    // MARK: exit

    func quit() {
        guard !exiting else { return }
        exiting = true
        watchTimer?.invalidate()
        save()
        settingsWindow?.close()
        hotkey?.unregister()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        wallpaper?.shutdown()
        Log.write("退出")
        NSApp.terminate(nil)
    }
}
