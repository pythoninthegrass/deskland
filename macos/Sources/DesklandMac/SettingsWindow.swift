import AppKit
import DesklandCore
import WebKit

@MainActor
final class SettingsWindow: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private let window: NSWindow
    private let web: WKWebView
    var onClose: () -> Void = {}
    var onMessage: (String) -> Void = { _ in }

    init(scheme: SchemeHandler) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        web = WebViewFactory.make(scheme: scheme, onMessage: { _ in })
        super.init()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "deskland")
        web.configuration.userContentController.add(WeakScriptHandler { [weak self] in self?.onMessage($0) }, name: "deskland")
        web.navigationDelegate = self
        web.uiDelegate = self
        window.title = "Deskland Preview"
        window.minSize = NSSize(width: 940, height: 680)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = web
        window.center()
        let v = AppPaths.version.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "deskland://app/settings.html?v=\(v)") { web.load(URLRequest(url: url)) }
    }

    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() { window.close() }

    func post(_ json: String) { WebViewFactory.post(json, to: web) }

    func windowWillClose(_ notification: Notification) { onClose() }

    // Only the app's own pages load in this view; links go to the default browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, url.scheme != "deskland", url.scheme != "about" else { return .allow }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { web.reload() }
}
