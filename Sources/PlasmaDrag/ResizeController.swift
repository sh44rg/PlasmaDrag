import AppKit
import ApplicationServices
import CoreGraphics

/// Option + two-finger trackpad drag resizes the focused window, wherever the
/// cursor is, by moving its bottom-right corner. Option + mouse wheel grows/shrinks it the
/// same way.
final class ResizeController {
    private static let minimumSize = CGSize(width: 120, height: 80)
    private static let wheelScaleStep: CGFloat = 0.05
    private static let wheelSessionTimeout: TimeInterval = 0.6

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
        var fingerDelta: CGPoint = .zero
    }

    private struct WheelSession {
        let window: AXUIElement
        var frame: CGRect
        let maximumSize: CGSize
        var lastEvent: Date
    }

    private let applier: AXApplier
    private var gesture: GestureSession?
    private var swallowingMomentum = false
    private var wheel: WheelSession?

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
        guard let window = WindowLocator.focusedWindow(), let frame = window.frame else { return false }

        gesture = GestureSession(
            window: window,
            startFrame: frame,
            maximumSize: Self.maximumSize(for: frame),
            directionInverted: NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? true
        )
        applier.beginInteraction(with: window)
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
        gesture = session

        let start = session.startFrame
        let size = Self.clamp(
            CGSize(width: start.width + session.fingerDelta.x, height: start.height + session.fingerDelta.y),
            maximum: session.maximumSize
        )
        applier.resize(session.window, to: .init(frame: CGRect(origin: start.origin, size: size), anchor: .zero))
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

    private static func clamp(_ size: CGSize, maximum: CGSize) -> CGSize {
        CGSize(
            width: min(maximum.width, max(minimumSize.width, size.width)),
            height: min(maximum.height, max(minimumSize.height, size.height))
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

        let now = Date()
        if wheel == nil || now.timeIntervalSince(wheel!.lastEvent) > Self.wheelSessionTimeout {
            guard let window = WindowLocator.focusedWindow(), let frame = window.frame else {
                wheel = nil
                return event
            }
            wheel = WheelSession(window: window, frame: frame, maximumSize: Self.maximumSize(for: frame), lastEvent: now)
        }
        guard var session = wheel else { return event }

        let inverted = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        let notchesAway = CGFloat(inverted ? -lines : lines)
        let scale = max(0.1, 1 + Self.wheelScaleStep * notchesAway)

        let old = session.frame
        let size = Self.clamp(CGSize(width: old.width * scale, height: old.height * scale), maximum: session.maximumSize)
        let frame = CGRect(origin: old.origin, size: size)

        session.frame = frame
        session.lastEvent = now
        wheel = session
        applier.resize(session.window, to: .init(frame: frame, anchor: .zero))
        return nil
    }
}
