// Draws the PlasmaDrag app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (from the repository root)
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Draws the icon on a 1024 x 1024 canvas (bottom-left origin).
func drawIcon() {
    // macOS icon grid: an 824 pt rounded square centred on the canvas.
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0x241056).setFill()
    platePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    NSGradient(colors: [color(0x8B5CF6), color(0x5B21B6), color(0x1E1B4B)])!
        .draw(in: plate, angle: -90)
    // Plasma glow from the upper left.
    NSGradient(colors: [color(0xF0ABFC, 0.55), color(0xC026D3, 0.18), color(0xC026D3, 0)])!
        .draw(fromCenter: NSPoint(x: 330, y: 760), radius: 0, toCenter: NSPoint(x: 330, y: 760), radius: 620, options: [])
    NSGradient(colors: [color(0x22D3EE, 0.35), color(0x22D3EE, 0)])!
        .draw(fromCenter: NSPoint(x: 820, y: 180), radius: 0, toCenter: NSPoint(x: 820, y: 180), radius: 460, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Three tiled windows: a main window and two stacked on the right.
    let area = NSRect(x: 214, y: 236, width: 596, height: 552)
    let gap: CGFloat = 28
    let mainWidth = (area.width - gap) * 0.56
    let sideWidth = area.width - gap - mainWidth
    let sideHeight = (area.height - gap) / 2
    let windows = [
        NSRect(x: area.minX, y: area.minY, width: mainWidth, height: area.height),
        NSRect(x: area.maxX - sideWidth, y: area.maxY - sideHeight, width: sideWidth, height: sideHeight),
        NSRect(x: area.maxX - sideWidth, y: area.minY, width: sideWidth, height: sideHeight),
    ]
    let accents: [UInt32] = [0xF472B6, 0x67E8F9, 0xC4B5FD]

    for (rect, accent) in zip(windows, accents) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34)

        NSGraphicsContext.saveGraphicsState()
        let windowShadow = NSShadow()
        windowShadow.shadowColor = color(0x0B0420, 0.45)
        windowShadow.shadowOffset = NSSize(width: 0, height: -10)
        windowShadow.shadowBlurRadius = 24
        windowShadow.set()
        color(0xFFFFFF, 0.94).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Title bar in the window's accent colour.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let titleBar = NSRect(x: rect.minX, y: rect.maxY - 64, width: rect.width, height: 64)
        NSGradient(colors: [color(accent), color(accent, 0.8)])!.draw(in: titleBar, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        for index in 0..<3 {
            let dot = NSRect(x: rect.minX + 30 + CGFloat(index) * 30, y: rect.maxY - 42, width: 20, height: 20)
            color(0xFFFFFF, 0.85).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

try fileManager.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try png(pixels: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
print("Wrote Resources/AppIcon.icns")
