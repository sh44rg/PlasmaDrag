import AppKit

/// A grid of layout thumbnails for embedding in the status item menu.
final class LayoutPickerView: NSView {
    private static let columns = 4
    private static let tileSize = NSSize(width: 66, height: 58)
    private static let spacing: CGFloat = 4
    private static let inset = NSEdgeInsets(top: 4, left: 14, bottom: 6, right: 14)

    var onSelect: ((TileLayout) -> Void)?

    init() {
        let layouts = TileLayout.allCases
        let rows = (layouts.count + Self.columns - 1) / Self.columns
        let width = Self.inset.left + Self.inset.right
            + CGFloat(Self.columns) * Self.tileSize.width + CGFloat(Self.columns - 1) * Self.spacing
        let height = Self.inset.top + Self.inset.bottom
            + CGFloat(rows) * Self.tileSize.height + CGFloat(rows - 1) * Self.spacing
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        for (index, layout) in layouts.enumerated() {
            let row = index / Self.columns
            let column = index % Self.columns
            let origin = NSPoint(
                x: Self.inset.left + CGFloat(column) * (Self.tileSize.width + Self.spacing),
                y: height - Self.inset.top - CGFloat(row + 1) * Self.tileSize.height - CGFloat(row) * Self.spacing
            )
            let tile = LayoutTile(layout: layout, frame: NSRect(origin: origin, size: Self.tileSize))
            tile.onClick = { [weak self] in self?.select(layout) }
            addSubview(tile)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func select(_ layout: TileLayout) {
        enclosingMenuItem?.menu?.cancelTracking()
        // Let the menu close and focus settle back on the previous app first.
        DispatchQueue.main.async { self.onSelect?(layout) }
    }
}

private final class LayoutTile: NSView {
    let layout: TileLayout
    var onClick: (() -> Void)?

    private var isHovered = false { didSet { needsDisplay = true } }

    init(layout: TileLayout, frame: NSRect) {
        self.layout = layout
        super.init(frame: frame)
        toolTip = layout.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Tile windows: \(layout.name)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isHovered = false
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isHovered = false
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }

        // Display outline at a 16:10 aspect ratio.
        let screen = NSRect(x: (bounds.width - 48) / 2, y: 6, width: 48, height: 30)
        let outline = NSBezierPath(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        outline.lineWidth = 1
        NSColor.secondaryLabelColor.setStroke()
        outline.stroke()

        let area = screen.insetBy(dx: 2, dy: 2)
        let fill = isHovered ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        fill.setFill()
        for slot in layout.slots(for: layout.previewCount) {
            let rect = NSRect(
                x: area.minX + slot.minX * area.width, y: area.minY + slot.minY * area.height,
                width: slot.width * area.width, height: slot.height * area.height
            ).insetBy(dx: 1, dy: 1)
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let label = layout.name as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor,
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: (bounds.width - labelSize.width) / 2, y: screen.maxY + 4), withAttributes: attributes)
    }
}
