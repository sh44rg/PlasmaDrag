import AppKit
import ApplicationServices

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(self, &pid) == .success ? pid : nil
    }

    var frame: CGRect? {
        let values = attributes([kAXPositionAttribute, kAXSizeAttribute])
        guard let position = axValue(values[0], .cgPoint, CGPoint.zero),
              let size = axValue(values[1], .cgSize, CGSize.zero) else { return nil }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    func setPosition(_ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value) == .success
    }

    /// Fetches several attributes in one IPC round-trip. Missing or failed
    /// attributes come back as nil.
    func attributes(_ names: [String]) -> [AnyObject?] {
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(self, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let values = raw as? [AnyObject], values.count == names.count else {
            return Array(repeating: nil, count: names.count)
        }
        return values.map { value in
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { return nil }
            return value
        }
    }
}

private func axElement(_ value: AnyObject?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func axValue<T: BitwiseCopyable>(_ value: AnyObject?, _ type: AXValueType, _ initial: T) -> T? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var result = initial
    return AXValueGetValue(value as! AXValue, type, &result) ? result : nil
}

enum WindowLocator {
    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // On the system-wide element this sets the global timeout, so a hung
        // app can't stall the event tap for the default 6 seconds.
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }()

    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
    ]

    struct Target {
        let window: AXUIElement
        let frame: CGRect
    }

    /// Cached per process so the Launch Services lookup happens once per app.
    private static var ignoredByPID: [pid_t: Bool] = [:]

    /// The movable window under `point` (global, top-left origin), if any.
    static func window(at point: CGPoint) -> Target? {
        guard let window = windowViaHitTest(at: point) ?? windowViaWindowList(at: point) else { return nil }
        return target(for: window)
    }

    /// The focused window of the frontmost app, if it can be moved/resized.
    static func focusedWindow() -> Target? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, !isIgnored(pid) else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let window: AXUIElement = app.attribute(kAXFocusedWindowAttribute) else { return nil }
        return target(for: window)
    }

    /// Reads position, size and fullscreen state in a single AX round-trip.
    private static func target(for window: AXUIElement) -> Target? {
        guard let pid = window.pid, !isIgnored(pid) else { return nil }

        let values = window.attributes([kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen"])
        if (values[2] as? Bool) == true { return nil }
        guard let position = axValue(values[0], .cgPoint, CGPoint.zero),
              let size = axValue(values[1], .cgSize, CGSize.zero) else { return nil }

        return Target(window: window, frame: CGRect(origin: position, size: size))
    }

    private static func isIgnored(_ pid: pid_t) -> Bool {
        if let cached = ignoredByPID[pid] { return cached }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let ignored = pid == ownPID || bundleID.map(ignoredBundleIDs.contains) == true
        ignoredByPID[pid] = ignored
        return ignored
    }

    private static func windowViaHitTest(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              var current = element else { return nil }

        // One round-trip per level; nearly every element answers AXWindow
        // directly, so this usually finishes on the first iteration.
        for _ in 0..<64 {
            let values = current.attributes([kAXRoleAttribute, kAXWindowAttribute, kAXParentAttribute])
            if values[0] as? String == kAXWindowRole as String { return current }
            if let window = axElement(values[1]) { return window }
            guard let parent = axElement(values[2]) else { return nil }
            current = parent
        }
        return nil
    }

    /// Fallback for apps whose AX hit-testing returns nothing useful: find the
    /// topmost normal-layer window from the window server, then match it to
    /// one of its owner's AX windows by frame.
    private static func windowViaWindowList(at point: CGPoint) -> AXUIElement? {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point) else { continue }

            let app = AXUIElementCreateApplication(pid)
            guard let windows: [AXUIElement] = app.attribute(kAXWindowsAttribute) else { return nil }
            return windows.first { window in
                guard let frame = window.frame else { return false }
                return abs(frame.minX - bounds.minX) < 2 && abs(frame.minY - bounds.minY) < 2
                    && abs(frame.width - bounds.width) < 2 && abs(frame.height - bounds.height) < 2
            }
        }
        return nil
    }
}
