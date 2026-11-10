import AppKit
import ApplicationServices
import DesklandCore

// Reads desktop icon frames from Finder through Accessibility (TASK-002.01): global points, top-left origin.
@MainActor
final class IconReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    // AXTrustedCheckOptionPrompt, spelled out because the CFString global is not concurrency-safe.
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // nil when Finder or its desktop is unreachable; cached elements go stale, so everything is found again per poll.
    func read() -> [Rect]? {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let areas = Self.elements(app, kAXChildrenAttribute),
              let desktop = areas.first(where: { Self.string($0, kAXRoleAttribute) == "AXScrollArea" }),
              let group = Self.elements(desktop, kAXChildrenAttribute)?.first,
              let items = Self.elements(group, kAXChildrenAttribute) else { return nil }
        return items.compactMap { item in
            guard let p = Self.point(item, kAXPositionAttribute), let s = Self.size(item, kAXSizeAttribute) else { return nil }
            return Rect(x: p.x, y: p.y, width: s.width, height: s.height)
        }
    }

    private static func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    private static func elements(_ e: AXUIElement, _ name: String) -> [AXUIElement]? { attribute(e, name) as? [AXUIElement] }
    private static func string(_ e: AXUIElement, _ name: String) -> String? { attribute(e, name) as? String }

    private static func point(_ e: AXUIElement, _ name: String) -> CGPoint? {
        guard let v = attribute(e, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(_ e: AXUIElement, _ name: String) -> CGSize? {
        guard let v = attribute(e, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    static var iconsVisible: Bool {
        func flag(_ domain: String, _ key: String) -> Bool? {
            UserDefaults(suiteName: domain)?.object(forKey: key) as? Bool
        }
        return DesktopIcons.isVisible(standardHideDesktopIcons: flag("com.apple.WindowManager", "StandardHideDesktopIcons"),
                                      createDesktop: flag("com.apple.finder", "CreateDesktop"))
    }
}
