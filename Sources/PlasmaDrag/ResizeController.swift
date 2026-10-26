import AppKit
import ApplicationServices
import CoreGraphics

/// Option + two-finger trackpad drag resizes the focused window, wherever the
/// cursor is, by moving its bottom-right corner. Option + mouse wheel
/// grows/shrinks it the same way.
final class ResizeController {
    private static let minimumSize = CGSize(width: 120, height: 80)
    private static let wheelScaleStep: CGFloat = 0.05
    /// In CGEventTimestamp units (nanoseconds).
    private static let wheelSessionTimeout: CGEventTimestamp = 600_000_000

    // CGScrollPhase / CGMomentumScrollPhase raw values.
    private enum Phase {
        static let began: Int64 = 1
        static let changed: Int64 = 2
        static let ended: Int64 = 4
        static let cancelled: Int64 = 8
        static let mayBegin: Int64 = 128
    }
    private enum Momentum {
        static let none: Int64 = 0
        static let end: Int64 = 3
    }

    private struct GestureSession {
        let window: AXUIElement
        let startFrame: CGRect
        let maximumSize: CGSize
        let directionInverted: Bool
        var lastSize: CGSize
        var fingerDelta: CGPoint = .zero
    }

    private struct WheelSession {
        let window: AXUIElement
        var frame: CGRect
        let maximumSize: CGSize
        let directionInverted: Bool
        var lastEvent: CGEventTimestamp
    }

    private let applier: AXApplier
    private var gesture: GestureSession?
    private var swallowingMomentum = false
    private var wheel: WheelSession?

    /// True while scroll events must keep flowing here even without Option.
    var isActive: Bool { gesture != nil || swallowingMomentum }

    init(applier: AXApplier) {
        self.applier = applier
    }

    func reset() {
        if let gesture { applier.endInteraction(with: gesture.window) }
        gesture = nil
        swallowingMomentum = false
        wheel = nil
    }

    func handle(event: CGEvent) -> CGEvent? {
        if !isActive && !event.hasExactlyOptionModifier { return event }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        if momentum != Momentum.none {
            guard swallowingMomentum else { return event }
            if momentum == Momentum.end { swallowingMomentum = false }
            return nil
        }
        swallowingMomentum = false

        if gesture != nil {
            switch phase {
            case Phase.changed:
                updateGesture(with: event)
                return nil
            case Phase.ended, Phase.cancelled:
                endGesture()
                swallowingMomentum = true
                return nil
            case Phase.began:
                endGesture()
            default:
                return nil
            }
        }

        guard event.hasExactlyOptionModifier else { return event }

        guard isContinuous, phase != 0 else { return handleWheel(event) }

        switch phase {
        case Phase.began:
            return beginGesture(with: event) ? nil : event
        case Phase.mayBegin, Phase.cancelled:
            return nil
        default:
            // Option was pressed mid-scroll; the app already saw the start of
            // this gesture, so let it finish normally.
            return event
        }
    }

    // MARK: - Trackpad gesture

    private func beginGesture(with event: CGEvent) -> Bool {
        guard let target = WindowLocator.focusedWindow() else { return false }

        gesture = GestureSession(
            window: target.window,
            startFrame: target.frame,
            maximumSize: Self.maximumSize(for: target.frame),
            directionInverted: NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? true,
            lastSize: target.frame.size
        )
        applier.beginInteraction(with: target.window)
        updateGesture(with: event)
        return true
    }

    private func updateGesture(with event: CGEvent) {
        guard var session = gesture else { return }

        // Positive scroll deltas mean "content moves down/right". With natural
        // scrolling that matches the fingers; otherwise it's the opposite.
        let sign: CGFloat = session.directionInverted ? 1 : -1
        session.fingerDelta.x += sign * CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        session.fingerDelta.y += sign * CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))

        let start = session.startFrame
        let size = Self.clamp(
            CGSize(width: start.width + session.fingerDelta.x, height: start.height + session.fingerDelta.y),
            maximum: session.maximumSize
        )
        if size != session.lastSize {
            session.lastSize = size
            applier.resize(session.window, to: size)
        }
        gesture = session
    }

    /// Largest size that keeps the bottom-right corner on the window's
    /// display. A window already hanging off-screen may keep its current size.
    private static func maximumSize(for frame: CGRect) -> CGSize {
        guard let bounds = ScreenGeometry.bounds(for: frame, in: ScreenGeometry.visibleBounds()) else {
            return CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        return CGSize(
            width: max(bounds.maxX - frame.minX, frame.width),
            height: max(bounds.maxY - frame.minY, frame.height)
        )
    }

    /// Applies the size limits and rounds to whole points, so sub-point
    /// finger movement doesn't trigger redundant AX writes.
    private static func clamp(_ size: CGSize, maximum: CGSize) -> CGSize {
        CGSize(
            width: min(maximum.width, max(minimumSize.width, size.width)).rounded(),
            height: min(maximum.height, max(minimumSize.height, size.height)).rounded()
        )
    }

    private func endGesture() {
        if let gesture { applier.endInteraction(with: gesture.window) }
        gesture = nil
    }

    // MARK: - Mouse wheel

    private func handleWheel(_ event: CGEvent) -> CGEvent? {
        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        guard lines != 0 else { return nil }

        let now = event.timestamp
        if wheel == nil || now &- wheel!.lastEvent > Self.wheelSessionTimeout {
            guard let target = WindowLocator.focusedWindow() else {
                wheel = nil
                return event
            }
            wheel = WheelSession(
                window: target.window,
                frame: target.frame,
                maximumSize: Self.maximumSize(for: target.frame),
                directionInverted: NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false,
                lastEvent: now
            )
        }
        guard var session = wheel else { return event }

        let notchesAway = CGFloat(session.directionInverted ? -lines : lines)
        let scale = max(0.1, 1 + Self.wheelScaleStep * notchesAway)

        let old = session.frame
        let size = Self.clamp(CGSize(width: old.width * scale, height: old.height * scale), maximum: session.maximumSize)
        let frame = CGRect(origin: old.origin, size: size)

        session.lastEvent = now
        if frame != old {
            session.frame = frame
            applier.resize(session.window, to: size)
        }
        wheel = session
        return nil
    }
}
