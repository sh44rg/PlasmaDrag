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

/// A session-level event tap on the main run loop. For active taps the
/// handler returns the event to let it through, or nil to swallow it.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private let mask: CGEventMask
    private let options: CGEventTapOptions
    private let handler: Handler
    private let onDisabledBySystem: () -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Tracked locally so toggling per event never needs a window server
    /// round-trip to query the current state.
    private(set) var isEnabled = false

    var isCreated: Bool { tap != nil }

    init(
        events: [CGEventType],
        options: CGEventTapOptions,
        handler: @escaping Handler,
        onDisabledBySystem: @escaping () -> Void
    ) {
        self.mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        self.options = options
        self.handler = handler
        self.onDisabledBySystem = onDisabledBySystem
    }

    func create(enabled: Bool) -> Bool {
        if tap != nil { return true }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.runLoopSource = source

        // A new tap starts enabled.
        isEnabled = true
        setEnabled(enabled)
        return true
    }

    func destroy() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isEnabled = false
    }

    func setEnabled(_ enabled: Bool, force: Bool = false) {
        guard let tap, enabled != isEnabled || force else { return }
        CGEvent.tapEnable(tap: tap, enable: enabled)
        isEnabled = enabled
    }

    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            isEnabled = false
            onDisabledBySystem()
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
