import AppKit
import ApplicationServices

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var role: String? { attribute(kAXRoleAttribute) }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(self, &pid) == .success ? pid : nil
    }

    var position: CGPoint? {
        guard let value: AXValue = attribute(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        guard let value: AXValue = attribute(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    var frame: CGRect? {
        guard let position, let size else { return nil }
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

    func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, name as CFString, &settable) == .success && settable.boolValue
    }
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

    /// The movable window under `point` (global, top-left origin), if any.
    static func window(at point: CGPoint) -> AXUIElement? {
        if let window = windowViaHitTest(at: point) ?? windowViaWindowList(at: point),
           isEligible(window) {
            return window
        }
        return nil
    }

    private static func windowViaHitTest(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              var current = element else { return nil }

        if current.role == kAXWindowRole as String { return current }
        if let window: AXUIElement = current.attribute(kAXWindowAttribute) { return window }

        for _ in 0..<64 {
            guard let parent: AXUIElement = current.attribute(kAXParentAttribute) else { return nil }
            if parent.role == kAXWindowRole as String { return parent }
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

    private static func isEligible(_ window: AXUIElement) -> Bool {
        guard let pid = window.pid, pid != ownPID else { return false }
        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           ignoredBundleIDs.contains(bundleID) {
            return false
        }
        if let fullScreen: Bool = window.attribute("AXFullScreen"), fullScreen { return false }
        return window.isSettable(kAXPositionAttribute)
    }
}
