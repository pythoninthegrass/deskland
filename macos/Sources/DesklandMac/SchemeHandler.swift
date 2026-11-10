import DesklandCore
import Foundation
import WebKit

// Serves deskland://app and deskland://share; a custom scheme is a secure context, which MediaRecorder needs.
@MainActor
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let resolver: ResourceResolver

    init(resolver: ResourceResolver) { self.resolver = resolver }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let res = resolver.resolve(url),
              let data = try? Data(contentsOf: res.file, options: .mappedIfSafe) else {
            respond(task, status: 404, headers: [:], body: Data("not found".utf8))
            return
        }
        var headers = ["Content-Type": res.mime, "Accept-Ranges": "bytes", "Cache-Control": "no-cache"]
        if let h = task.request.value(forHTTPHeaderField: "Range") {
            guard let r = ByteRange.parse(h, length: data.count) else {
                respond(task, status: 416, headers: ["Content-Range": "bytes */\(data.count)"], body: Data())
                return
            }
            headers["Content-Range"] = "bytes \(r.lowerBound)-\(r.upperBound)/\(data.count)"
            respond(task, status: 206, headers: headers, body: data.subdata(in: r.lowerBound..<(r.upperBound + 1)))
        } else {
            respond(task, status: 200, headers: headers, body: data)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func respond(_ task: any WKURLSchemeTask, status: Int, headers: [String: String], body: Data) {
        var h = headers
        h["Content-Length"] = String(body.count)
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: h) else {
            task.didFailWithError(URLError(.badServerResponse)); return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}

// WKUserContentController retains its handlers strongly; this keeps controllers from leaking.
@MainActor
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private let onMessage: (String) -> Void
    init(_ onMessage: @escaping (String) -> Void) { self.onMessage = onMessage }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if let s = message.body as? String { onMessage(s) }
    }
}

enum WebViewFactory {
    @MainActor
    static func make(scheme: SchemeHandler, onMessage: @escaping (String) -> Void) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "deskland")
        config.userContentController.add(WeakScriptHandler(onMessage), name: "deskland")
        config.userContentController.addUserScript(
            WKUserScript(source: ScriptBridge.shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.isInspectable = true
        return web
    }

    @MainActor
    static func post(_ json: String, to web: WKWebView) {
        web.evaluateJavaScript(ScriptBridge.dispatch(json), completionHandler: nil)
    }
}
