import Testing
@testable import DesklandCore

@Suite struct CoordinateTests {
    let main1x = DisplayGeometry(frame: Rect(x: 0, y: 0, width: 2560, height: 1440), scale: 1)
    let main2x = DisplayGeometry(frame: Rect(x: 0, y: 0, width: 1512, height: 982), scale: 2)

    @Test func identityAtOneX() {
        let r = IconCoordinates.physicalRects(from: [Rect(x: 20, y: 30, width: 48, height: 48)], display: main1x)
        #expect(r == [IconRect(left: 20, top: 30, right: 68, bottom: 78)])
    }

    @Test func doublesAtTwoX() {
        let r = IconCoordinates.physicalRects(from: [Rect(x: 20, y: 30, width: 48, height: 48)], display: main2x)
        #expect(r == [IconRect(left: 40, top: 60, right: 136, bottom: 156)])
    }

    @Test func fractionalPointsRound() {
        let r = IconCoordinates.physicalRects(from: [Rect(x: 20.25, y: 30.5, width: 48, height: 48)], display: main2x)
        #expect(r == [IconRect(left: 41, top: 61, right: 137, bottom: 157)])
    }

    @Test func dropsIconsOnOtherDisplays() {
        let rects = [
            Rect(x: 100, y: 100, width: 48, height: 48),
            Rect(x: 1512, y: -458, width: 48, height: 48),
            Rect(x: -2560, y: 0, width: 48, height: 48),
            Rect(x: 300, y: 1200, width: 48, height: 48),
        ]
        let r = IconCoordinates.physicalRects(from: rects, display: main2x)
        #expect(r == [IconRect(left: 200, top: 200, right: 296, bottom: 296)])
    }

    @Test func keepsOrderAndIsRelativeToDisplayOrigin() {
        let offset = DisplayGeometry(frame: Rect(x: 100, y: 50, width: 800, height: 600), scale: 1)
        let rects = [Rect(x: 400, y: 300, width: 10, height: 10), Rect(x: 120, y: 60, width: 10, height: 10)]
        let r = IconCoordinates.physicalRects(from: rects, display: offset)
        #expect(r == [IconRect(left: 300, top: 250, right: 310, bottom: 260), IconRect(left: 20, top: 10, right: 30, bottom: 20)])
    }

    @Test func emptyInput() {
        #expect(IconCoordinates.physicalRects(from: [], display: main2x).isEmpty)
    }

    @Test func iconsGrowToIncludeLabelAfterDisplayTest() {
        let icons = [Rect(x: 100, y: 100, width: 48, height: 48), Rect(x: 1600, y: 100, width: 48, height: 48)]
        let r = IconCoordinates.physicalRects(fromIcons: icons, display: main2x)
        #expect(r == [IconRect(left: 134, top: 200, right: 362, bottom: 368)])
    }

    @Test func iconNearBottomEdgeKeepsItsLabel() {
        let r = IconCoordinates.physicalRects(fromIcons: [Rect(x: 100, y: 940, width: 48, height: 48)], display: main2x)
        #expect(r.count == 1)
    }
}

// Frames are AppKit-style: global points, bottom-left origin.
@Suite struct DockInsetTests {
    private let frame = Rect(x: 0, y: 0, width: 1440, height: 900)

    @Test func dockAtBottomScalesToPhysicalPixels() {
        let visible = Rect(x: 0, y: 70, width: 1440, height: 800)
        #expect(DockInset.bottomPixels(frame: frame, visible: visible, scale: 2) == 140)
        #expect(DockInset.bottomPixels(frame: frame, visible: visible, scale: 1) == 70)
    }

    @Test func dockOnSideOrHiddenLeavesNoBottomStrip() {
        let left = Rect(x: 80, y: 0, width: 1360, height: 875)
        #expect(DockInset.bottomPixels(frame: frame, visible: left, scale: 2) == 0)
    }

    @Test func menuBarAloneDoesNotCount() {
        let visible = Rect(x: 0, y: 0, width: 1440, height: 876)
        #expect(DockInset.bottomPixels(frame: frame, visible: visible, scale: 2) == 0)
    }

    @Test func offsetDisplayOriginIsRelative() {
        let f = Rect(x: 0, y: -100, width: 1440, height: 900)
        let visible = Rect(x: 0, y: -30, width: 1440, height: 830)
        #expect(DockInset.bottomPixels(frame: f, visible: visible, scale: 2) == 140)
    }
}
