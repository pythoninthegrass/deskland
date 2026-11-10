// Host to wallpaper page messages. Strings must match what DesktopHost.cs posts.
public struct IconRect: Equatable, Sendable {
    public var left, top, right, bottom: Int
    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

public enum HostMessage: Equatable {
    case icons(visible: Bool, rects: [IconRect])
    case pause(Bool)
    case settings(JSONValue)
    case reset
    case snapshot
    case record

    public var wireString: String {
        switch self {
        case let .icons(visible, rects):
            let r = rects.map { "[\($0.left),\($0.top),\($0.right),\($0.bottom)]" }.joined(separator: ",")
            return "{\"t\":\"icons\",\"vis\":\(visible),\"r\":[\(r)]}"
        case let .pause(v): return "{\"t\":\"pause\",\"v\":\(v)}"
        case let .settings(v): return "{\"t\":\"settings\",\"v\":\(v.serialized)}"
        case .reset: return "{\"t\":\"reset\"}"
        case .snapshot: return "{\"t\":\"snapshot\"}"
        case .record: return "{\"t\":\"record\"}"
        }
    }
}
