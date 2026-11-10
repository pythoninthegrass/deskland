public struct PauseInput: Equatable, Sendable {
    public var manualPause: Bool
    public var frontWindows: [Rect]
    public var screenFrame: Rect
    public var visibleFrame: Rect
    public var fullscreenSpace: Bool
    public var screenLocked: Bool
    public var displayAsleep: Bool

    public init(manualPause: Bool, frontWindows: [Rect], screenFrame: Rect, visibleFrame: Rect,
                fullscreenSpace: Bool, screenLocked: Bool, displayAsleep: Bool) {
        self.manualPause = manualPause; self.frontWindows = frontWindows
        self.screenFrame = screenFrame; self.visibleFrame = visibleFrame
        self.fullscreenSpace = fullscreenSpace; self.screenLocked = screenLocked; self.displayAsleep = displayAsleep
    }
}

public enum PauseDecision {
    public static func shouldPause(_ i: PauseInput) -> Bool {
        if i.manualPause || i.fullscreenSpace || i.screenLocked || i.displayAsleep { return true }
        return i.frontWindows.contains { $0.contains(i.screenFrame) || $0.contains(i.visibleFrame) }
    }
}
