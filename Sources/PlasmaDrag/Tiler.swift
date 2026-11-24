import AppKit
import ApplicationServices

/// A tiling arrangement. Slots are expressed in a unit square with a
/// top-left origin, and are filled front to back with the visible windows.
enum TileLayout: CaseIterable {
    case halves
    case rows
    case twoThirdsLeft
    case thirds
    case mainAndTwo
    case quarters
    case mainAndStack
    case grid

    var name: String {
        switch self {
        case .halves: "Halves"
        case .rows: "Rows"
        case .twoThirdsLeft: "2/3 + 1/3"
        case .thirds: "Thirds"
        case .mainAndTwo: "Main + 2"
        case .quarters: "Quarters"
        case .mainAndStack: "Main + Stack"
        case .grid: "Grid All"
        }
    }

    /// How many windows the layout takes; nil means every visible window.
    var capacity: Int? {
        switch self {
        case .halves, .rows, .twoThirdsLeft: 2
        case .thirds, .mainAndTwo: 3
        case .quarters: 4
        case .mainAndStack, .grid: nil
        }
    }

    /// Window count used to draw the layout's thumbnail.
    var previewCount: Int { capacity ?? (self == .grid ? 6 : 4) }

    func slots(for count: Int) -> [CGRect] {
        switch self {
        case .halves:
            return [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .rows:
            return [CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]
        case .twoThirdsLeft:
            return [CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1), CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)]
        case .thirds:
            return (0..<3).map { CGRect(x: CGFloat($0) / 3, y: 0, width: 1.0 / 3, height: 1) }
        case .mainAndTwo:
            return [
                CGRect(x: 0, y: 0, width: 0.5, height: 1),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]
        case .quarters:
            return [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]
        case .mainAndStack:
            guard count > 1 else { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
            let stack = count - 1
            return [CGRect(x: 0, y: 0, width: 0.5, height: 1)]
                + (0..<stack).map { CGRect(x: 0.5, y: CGFloat($0) / CGFloat(stack), width: 0.5, height: 1 / CGFloat(stack)) }
        case .grid:
            guard count > 0 else { return [] }
            let columns = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(columns)))
            return (0..<count).map { index in
                let row = index / columns
                // The last row may be short; stretch its windows to fill it.
                let inRow = row == rows - 1 ? count - row * columns : columns
                let column = index % columns
                return CGRect(
                    x: CGFloat(column) / CGFloat(inRow), y: CGFloat(row) / CGFloat(rows),
                    width: 1 / CGFloat(inRow), height: 1 / CGFloat(rows)
                )
            }
        }
    }
}

enum Tiler {
    /// Space around and between tiled windows, in points.
    static let gap: CGFloat = 0

    static let queue = DispatchQueue(label: "com.shaaravg.plasmadrag.tiler", qos: .userInitiated)

    /// Tiles the frontmost visible windows on the display of the frontmost
    /// window. Must be called on the main thread.
    static func apply(_ layout: TileLayout) {
        let screens = ScreenGeometry.visibleBounds()
        let visible = WindowLocator.visibleWindows()
        guard let front = visible.first,
              let screen = ScreenGeometry.bounds(for: front.frame, in: screens) else { return }

        var windows = visible.filter { ScreenGeometry.bounds(for: $0.frame, in: screens) == screen }
        if let capacity = layout.capacity { windows = Array(windows.prefix(capacity)) }

        let area = screen.insetBy(dx: gap / 2, dy: gap / 2)
        let frames = layout.slots(for: windows.count).map { slot in
            // Round each edge, not the size, so neighbouring tiles share an
            // edge exactly instead of overlapping or leaving a 1 pt seam.
            let minX = (area.minX + slot.minX * area.width).rounded()
            let maxX = (area.minX + slot.maxX * area.width).rounded()
            let minY = (area.minY + slot.minY * area.height).rounded()
            let maxY = (area.minY + slot.maxY * area.height).rounded()
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: gap / 2, dy: gap / 2)
        }

        let assignments = zip(windows, frames).map { ($0.window, $1) }
        for (target, _) in zip(windows, frames) {
            TileMemory.shared.beginPlacing(target.window, currentFrame: target.frame)
        }
        queue.async {
            for (window, frame) in assignments {
                place(window, in: frame)
                let actual = window.frame
                DispatchQueue.main.async { TileMemory.shared.finishPlacing(window, frame: actual) }
            }
        }
    }

    static func place(_ window: AXUIElement, in frame: CGRect) {
        // Chromium/Electron animate geometry changes while enhanced UI is on,
        // which makes the second write land on a stale frame.
        var restoreEnhancedUI: AXUIElement?
        if let pid = window.pid {
            let app = AXUIElementCreateApplication(pid)
            if let enhanced: Bool = app.attribute("AXEnhancedUserInterface"), enhanced {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
                restoreEnhancedUI = app
            }
        }

        // Move first so the new size isn't clipped by the display edge, then
        // move again in case the app adjusted its origin while resizing.
        window.setPosition(frame.origin)
        window.setSize(frame.size)
        window.setPosition(frame.origin)

        if let app = restoreEnhancedUI {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}
