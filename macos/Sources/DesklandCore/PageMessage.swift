// Wallpaper page to host messages: plain pipe-delimited strings, parsed like OnSnapshot / OnRecord in DesktopHost.cs.
public enum PageMessage: Equatable {
    case ready
    case snapshot(thumb: String, png: String)
    case snapshotError(String)
    case snapshotBadData
    case recordProgress(String)
    case record(mime: String, poster: String, video: String)
    case recordError(String)
    case recordBadData
    case unknown

    public static func parse(_ msg: String) -> PageMessage {
        if msg == "ready" { return .ready }
        if msg.hasPrefix("recprogress|") { return .recordProgress(String(msg.dropFirst(12))) }
        if msg.hasPrefix("snapshot") { return parseSnapshot(msg) }
        if msg.hasPrefix("record") { return parseRecord(msg) }
        return .unknown
    }

    private static func parseSnapshot(_ msg: String) -> PageMessage {
        let p = msg.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard p[0] == "snapshot" else { return .unknown }
        if p.count < 3 { return .snapshotBadData }
        if p[1] == "error" { return .snapshotError(p[2]) }
        return .snapshot(thumb: p[1], png: p[2])
    }

    private static func parseRecord(_ msg: String) -> PageMessage {
        let p = msg.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard p[0] == "record" else { return .unknown }
        if p.count >= 3, p[1] == "error" { return .recordError(String(msg.dropFirst(13))) }
        if p.count < 4 { return .recordBadData }
        return .record(mime: p[1], poster: p[2], video: p[3])
    }
}
