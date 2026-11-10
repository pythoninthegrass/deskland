import Testing
@testable import DesklandCore

@Suite struct PauseDecisionTests {
    static let frame = Rect(x: 0, y: 0, width: 1512, height: 982)
    static let visible = Rect(x: 0, y: 38, width: 1512, height: 944)

    func input(manual: Bool = false, windows: [Rect] = [], fullscreenSpace: Bool = false, locked: Bool = false, asleep: Bool = false) -> PauseInput {
        PauseInput(manualPause: manual, frontWindows: windows, screenFrame: Self.frame, visibleFrame: Self.visible,
                   fullscreenSpace: fullscreenSpace, screenLocked: locked, displayAsleep: asleep)
    }

    @Test func playsWhenNothingApplies() {
        #expect(!PauseDecision.shouldPause(input()))
    }

    @Test func smallWindowDoesNotPause() {
        #expect(!PauseDecision.shouldPause(input(windows: [Rect(x: 200, y: 200, width: 800, height: 600)])))
    }

    @Test func manualPause() {
        #expect(PauseDecision.shouldPause(input(manual: true)))
    }

    @Test func windowCoveringFrame() {
        #expect(PauseDecision.shouldPause(input(windows: [Self.frame])))
    }

    @Test func windowCoveringVisibleFrame() {
        #expect(PauseDecision.shouldPause(input(windows: [Self.visible])))
    }

    @Test func windowBiggerThanFrame() {
        #expect(PauseDecision.shouldPause(input(windows: [Rect(x: -10, y: -10, width: 1600, height: 1000)])))
    }

    @Test func windowOneUnitShortDoesNotPause() {
        #expect(!PauseDecision.shouldPause(input(windows: [Rect(x: 0, y: 38, width: 1512, height: 943)])))
    }

    @Test func anyOfSeveralWindows() {
        #expect(PauseDecision.shouldPause(input(windows: [Rect(x: 0, y: 0, width: 10, height: 10), Self.frame])))
    }

    @Test func fullscreenSpace() {
        #expect(PauseDecision.shouldPause(input(fullscreenSpace: true)))
    }

    @Test func lockedAndAsleep() {
        #expect(PauseDecision.shouldPause(input(locked: true)))
        #expect(PauseDecision.shouldPause(input(asleep: true)))
    }
}
