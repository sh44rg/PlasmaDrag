import AppKit
import ApplicationServices
import CoreGraphics

/// Option + two-finger trackpad drag resizes the window under the cursor from
/// its nearest corner. Option + mouse wheel scales it around its center.
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
        let movesLeftEdge: Bool
        let movesTopEdge: Bool
        let directionInverted: Bool
        var fingerDelta: CGPoint = .zero
    }

    private struct WheelSession {
        let window: AXUIElement
        var frame: CGRect
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
        let location = event.location
        guard let window = WindowLocator.window(at: location), let frame = window.frame else { return false }

        gesture = GestureSession(
            window: window,
            startFrame: frame,
            movesLeftEdge: location.x < frame.midX,
            movesTopEdge: location.y < frame.midY,
            directionInverted: NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? true
        )
        applier.beginInteraction(with: window)
        applier.raise(window)
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
        let dx = session.fingerDelta.x
        let dy = session.fingerDelta.y

        let width = max(Self.minimumSize.width, session.movesLeftEdge ? start.width - dx : start.width + dx)
        let height = max(Self.minimumSize.height, session.movesTopEdge ? start.height - dy : start.height + dy)
        let frame = CGRect(
            x: session.movesLeftEdge ? start.maxX - width : start.minX,
            y: session.movesTopEdge ? start.maxY - height : start.minY,
            width: width,
            height: height
        )
        let anchor = CGPoint(x: session.movesLeftEdge ? 1 : 0, y: session.movesTopEdge ? 1 : 0)
        applier.resize(session.window, to: .init(frame: frame, anchor: anchor))
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
            guard let window = WindowLocator.window(at: event.location), let frame = window.frame else {
                wheel = nil
                return event
            }
            wheel = WheelSession(window: window, frame: frame, lastEvent: now)
        }
        guard var session = wheel else { return event }

        let inverted = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        let notchesAway = CGFloat(inverted ? -lines : lines)
        let scale = max(0.1, 1 + Self.wheelScaleStep * notchesAway)

        let old = session.frame
        let size = CGSize(
            width: max(Self.minimumSize.width, old.width * scale),
            height: max(Self.minimumSize.height, old.height * scale)
        )
        let frame = CGRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height)

        session.frame = frame
        session.lastEvent = now
        wheel = session
        applier.resize(session.window, to: .init(frame: frame, anchor: CGPoint(x: 0.5, y: 0.5)))
        return nil
    }
}
