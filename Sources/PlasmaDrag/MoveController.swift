import ApplicationServices
import CoreGraphics

/// Option + left-drag moves the window under the cursor.
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
        let startMouse: CGPoint
        let startOrigin: CGPoint
        let downEvent: CGEvent
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
              let origin = window.position,
              let downEvent = event.copy() else { return event }

        state = .pending(Session(window: window, startMouse: event.location, startOrigin: origin, downEvent: downEvent))
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
        applier.move(session.window, to: session.startOrigin + delta)
        return nil
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
