public struct Rect: Equatable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func contains(_ other: Rect) -> Bool {
        x <= other.x && y <= other.y && maxX >= other.maxX && maxY >= other.maxY
    }

    func contains(pointX px: Double, y py: Double) -> Bool {
        px >= x && px < maxX && py >= y && py < maxY
    }
}

// Main display in AX space: global points, top-left origin; scale is backingScaleFactor.
public struct DisplayGeometry: Equatable, Sendable {
    public var frame: Rect
    public var scale: Double
    public init(frame: Rect, scale: Double) {
        self.frame = frame; self.scale = scale
    }
}

public enum IconCoordinates {
    // The page divides by devicePixelRatio, so rects go out in physical pixels relative to the display.
    // An icon belongs to the display holding its center; the rest are dropped.
    public static func physicalRects(from rects: [Rect], display: DisplayGeometry, clipToDisplay: Bool = true) -> [IconRect] {
        rects.compactMap { r in
            guard !clipToDisplay || display.frame.contains(pointX: r.x + r.width / 2, y: r.y + r.height / 2) else { return nil }
            let s = display.scale
            return IconRect(
                left: Int(((r.x - display.frame.x) * s).rounded()),
                top: Int(((r.y - display.frame.y) * s).rounded()),
                right: Int(((r.maxX - display.frame.x) * s).rounded()),
                bottom: Int(((r.maxY - display.frame.y) * s).rounded()))
        }
    }

    // Display membership is decided by the icon's center; the sent rect also covers the estimated label.
    public static func physicalRects(fromIcons icons: [Rect], display: DisplayGeometry) -> [IconRect] {
        let onDisplay = icons.filter { display.frame.contains(pointX: $0.x + $0.width / 2, y: $0.y + $0.height / 2) }
        return physicalRects(from: onDisplay.map(IconLabel.bounds(forIcon:)), display: display, clipToDisplay: false)
    }
}
