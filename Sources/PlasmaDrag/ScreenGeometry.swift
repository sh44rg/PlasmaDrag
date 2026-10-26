import AppKit

enum ScreenGeometry {
    /// Usable area (excluding menu bar and Dock) of each display, in the
    /// top-left-origin global coordinates used by CGEvent and AX.
    static func visibleBounds() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            return CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
        }
    }

    /// The display containing `point`, or the closest one.
    static func bounds(containing point: CGPoint, in screens: [CGRect]) -> CGRect? {
        screens.first { $0.contains(point) } ?? screens.min { distance(from: point, to: $0) < distance(from: point, to: $1) }
    }

    /// The display showing most of `frame`, or the one closest to its origin.
    static func bounds(for frame: CGRect, in screens: [CGRect]) -> CGRect? {
        let best = screens.max { overlap($0, frame) < overlap($1, frame) }
        if let best, overlap(best, frame) > 0 { return best }
        return bounds(containing: frame.origin, in: screens)
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
