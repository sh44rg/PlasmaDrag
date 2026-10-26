import ApplicationServices
import CoreGraphics

/// Option + left-drag moves the window under the cursor, keeping it on screen.
final class MoveController {
    private static let dragThreshold: CGFloat = 3

    private enum State {
        case idle
        /// Mouse is down but hasn't moved far enough to count as a drag yet.
        case pending(Session)
        case dragging(Session)
    }

    private struct Session {
        let window: AXUIElement
        let size: CGSize
        let startMouse: CGPoint
        let startOrigin: CGPoint
        let downEvent: CGEvent
        let screenBounds: [CGRect]
    }

    private let applier: AXApplier
    private var state: State = .idle

    init(applier: AXApplier) {
        self.applier = applier
    }

    func reset() {
        if case let .dragging(session) = state {
            applier.endInteraction(with: session.window)
        }
        state = .idle
    }

    func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .leftMouseDown:
            return mouseDown(event)
        case .leftMouseDragged:
            return mouseDragged(event)
        case .leftMouseUp:
            return mouseUp(event)
        default:
            return event
        }
    }

    private func mouseDown(_ event: CGEvent) -> CGEvent? {
        reset()
        guard event.hasExactlyOptionModifier,
              let window = WindowLocator.window(at: event.location),
              let frame = window.frame,
              let downEvent = event.copy() else { return event }

        state = .pending(Session(
            window: window,
            size: frame.size,
            startMouse: event.location,
            startOrigin: frame.origin,
            downEvent: downEvent,
            screenBounds: ScreenGeometry.visibleBounds()
        ))
        return nil
    }

    private func mouseDragged(_ event: CGEvent) -> CGEvent? {
        let session: Session
        switch state {
        case .idle:
            return event
        case let .pending(pendingSession):
            let delta = event.location - pendingSession.startMouse
            guard hypot(delta.x, delta.y) >= Self.dragThreshold else { return nil }
            session = pendingSession
            state = .dragging(session)
            applier.beginInteraction(with: session.window)
            applier.raise(session.window)
        case let .dragging(draggingSession):
            session = draggingSession
        }

        let delta = event.location - session.startMouse
        let origin = Self.clamp(session.startOrigin + delta, size: session.size, cursor: event.location, screens: session.screenBounds)
        applier.move(session.window, to: origin)
        return nil
    }

    /// Keeps the window inside the display under the cursor. Windows larger
    /// than the display stick to its top-left corner.
    private static func clamp(_ origin: CGPoint, size: CGSize, cursor: CGPoint, screens: [CGRect]) -> CGPoint {
        guard let bounds = ScreenGeometry.bounds(containing: cursor, in: screens) else { return origin }
        return CGPoint(
            x: max(bounds.minX, min(origin.x, bounds.maxX - size.width)),
            y: max(bounds.minY, min(origin.y, bounds.maxY - size.height))
        )
    }

    private func mouseUp(_ event: CGEvent) -> CGEvent? {
        switch state {
        case .idle:
            return event
        case let .pending(session):
            state = .idle
            replayClick(down: session.downEvent, up: event)
            return nil
        case let .dragging(session):
            state = .idle
            applier.endInteraction(with: session.window)
            return nil
        }
    }

    /// The mouse-down was held back to see whether a drag would follow. It
    /// didn't, so deliver the click as it originally happened.
    private func replayClick(down: CGEvent, up: CGEvent) {
        guard let up = up.copy() else { return }
        down.markSynthetic()
        up.markSynthetic()
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}

extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}
