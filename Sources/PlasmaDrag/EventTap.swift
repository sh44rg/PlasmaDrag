import CoreGraphics
import Foundation

/// Marker written into `eventSourceUserData` of events we post ourselves.
let syntheticEventTag: Int64 = 0x504C_4153_4D41  // "PLASMA"

extension CGEvent {
    /// True when Option is the only "real" modifier held. Caps Lock, fn and
    /// numeric-pad bits are ignored so they don't block the gesture.
    var hasExactlyOptionModifier: Bool {
        let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        return flags.intersection(relevant) == .maskAlternate
    }

    var isSynthetic: Bool {
        getIntegerValueField(.eventSourceUserData) == syntheticEventTag
    }

    func markSynthetic() {
        setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
    }
}

/// Active (event-modifying) session tap. The handler returns the event to let
/// it through, or nil to swallow it.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private let handler: Handler
    private let onReset: () -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    init(handler: @escaping Handler, onReset: @escaping () -> Void) {
        self.handler = handler
        self.onReset = onReset
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil {
            ensureEnabled()
            return true
        }

        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    func ensureEnabled() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            onReset()
            ensureEnabled()
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        if event.isSynthetic {
            return Unmanaged.passUnretained(event)
        }

        guard let result = handler(type, event) else { return nil }
        return Unmanaged.passUnretained(result)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.process(type: type, event: event)
}
