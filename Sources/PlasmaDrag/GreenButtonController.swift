import AppKit
import ApplicationServices

/// Remaps unmodified clicks on standard window traffic lights.
final class GreenButtonController {
    private struct Press {
        let button: WindowLocator.GreenButton
        let windowID: CGWindowID
    }

    private final class FilledWindow {
        let pid: pid_t
        let original: CGRect
        let requested: CGRect
        let observed: CGRect?

        init(pid: pid_t, original: CGRect, requested: CGRect, observed: CGRect?) {
            self.pid = pid
            self.original = original
            self.requested = requested
            self.observed = observed
        }
    }

    // Accessed on Tiler.queue. Keep recent frames without observing every
    // filled window for moves, resizes or destruction.
    private lazy var filledWindows: NSCache<NSNumber, FilledWindow> = {
        let cache = NSCache<NSNumber, FilledWindow>()
        cache.countLimit = 128
        return cache
    }()

    private var press: Press?
    private lazy var tap = EventTap(
        events: [.leftMouseDown, .leftMouseUp],
        options: .defaultTap,
        handler: { [unowned self] type, event in handle(type, event) },
        onDisabledBySystem: { [unowned self] in systemDidWake() }
    )

    func start() -> Bool {
        tap.create(enabled: true)
    }

    func stop() {
        press = nil
        tap.destroy()
    }

    func systemDidWake() {
        press = nil
        tap.setEnabled(true, force: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .leftMouseUp {
            guard let press else { return event }
            self.press = nil
            // The press already confirmed the button. The window ID on release
            // can name window chrome or a hover menu instead of the window.
            if press.button.frame.contains(event.location) {
                DispatchQueue.main.async { self.toggleFill(for: press) }
            }
            return nil
        }

        press = nil
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        guard event.flags.intersection(modifiers).isEmpty else { return event }

        guard let candidate = Self.candidateWindow(for: event),
              let button = WindowLocator.greenButton(at: event.location, pid: candidate.pid) else { return event }

        press = Press(button: button, windowID: candidate.id)
        return nil
    }

    private static func windowID(for event: CGEvent) -> CGWindowID {
        let receiving = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        if let id = CGWindowID(exactly: receiving), id != kCGNullWindowID { return id }
        return CGWindowID(exactly: event.getIntegerValueField(.mouseEventWindowUnderMousePointer)) ?? kCGNullWindowID
    }

    private static func candidateWindow(for event: CGEvent) -> (id: CGWindowID, pid: pid_t)? {
        let id = windowID(for: event)
        if id != kCGNullWindowID {
            guard let info = windowInfo(for: id), (info[kCGWindowLayer] as? Int) == 0,
                  let frame = windowFrame(from: info),
                  isNearTrafficLights(in: frame, at: event.location),
                  let pid = info[kCGWindowOwnerPID] as? pid_t else { return nil }
            return (id, pid)
        }

        // Session taps may receive the event before a window ID is attached.
        let recipient = pid_t(exactly: event.getIntegerValueField(.eventTargetUnixProcessID)) ?? 0
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [NSDictionary] else { return nil }
        for info in windows {
            guard let pid = info[kCGWindowOwnerPID] as? pid_t, recipient <= 0 || recipient == pid,
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0,
                  let frame = windowFrame(from: info), frame.contains(event.location) else { continue }
            guard (info[kCGWindowLayer] as? Int) == 0, isNearTrafficLights(in: frame, at: event.location),
                  let id = info[kCGWindowNumber] as? CGWindowID else { return nil }
            return (id, pid)
        }
        return nil
    }

    private static func windowInfo(for windowID: CGWindowID) -> NSDictionary? {
        // Quartz window lists store IDs as pointer-sized integers, without CF callbacks.
        var id = UnsafeRawPointer(bitPattern: UInt(windowID))
        guard let ids = CFArrayCreate(nil, &id, 1, nil),
              let descriptions = CGWindowListCreateDescriptionFromArray(ids) as? [NSDictionary] else { return nil }
        return descriptions.first
    }

    private static func windowFrame(from info: NSDictionary) -> CGRect? {
        guard let bounds = info[kCGWindowBounds] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }

    private static func isNearTrafficLights(in frame: CGRect, at point: CGPoint) -> Bool {
        // A generous title-bar region includes inset and vertically centered
        // traffic lights. AX confirmation below makes this only a prefilter.
        let offset = point - frame.origin
        return offset.x >= 24 && offset.x <= 120 && offset.y >= 0 && offset.y <= 76
    }

    private func toggleFill(for press: Press) {
        let button = press.button
        let screens = ScreenGeometry.visibleBounds()
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == button.pid
        Tiler.queue.async {
            let window = button.window
            guard let state = window.stateForFill() else { return }
            if state.isFullScreen {
                AXUIElementPerformAction(button.element, kAXPressAction as CFString)
                return
            }
            self.fillOrRestore(press, current: state.frame, screens: screens)

            // The original mouse press was suppressed, so give the clicked
            // window the activation it would normally have received.
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            if !isFrontmost {
                let app = AXUIElementCreateApplication(button.pid)
                AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            }
        }
    }

    private func fillOrRestore(_ press: Press, current: CGRect, screens: [CGRect]) {
        let window = press.button.window
        let key = NSNumber(value: press.windowID)
        if let saved = filledWindows.object(forKey: key), saved.pid == press.button.pid,
           Self.framesMatch(saved.requested, current) || saved.observed.map({ Self.framesMatch($0, current) }) == true {
            Tiler.place(window, in: saved.original)
            if let actual = window.frame, Self.framesMatch(actual, saved.original) {
                filledWindows.removeObject(forKey: key)
            }
            return
        }

        // A window moved or resized after filling starts a new fill/restore pair.
        filledWindows.removeObject(forKey: key)
        guard let area = ScreenGeometry.bounds(for: current, in: screens), !Self.framesMatch(current, area) else { return }
        var canResize = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canResize) == .success,
              canResize.boolValue else { return }
        Tiler.place(window, in: area)
        // Some apps report their old frame while the resize is being applied.
        // Keep the requested frame as well as any observed app-constrained size.
        let actual = window.frame.flatMap { Self.framesMatch($0, current) ? nil : $0 }
        filledWindows.setObject(
            FilledWindow(pid: press.button.pid, original: current, requested: area, observed: actual), forKey: key
        )
    }

    private static func framesMatch(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 2 && abs(first.minY - second.minY) <= 2
            && abs(first.maxX - second.maxX) <= 2 && abs(first.maxY - second.maxY) <= 2
    }
}
