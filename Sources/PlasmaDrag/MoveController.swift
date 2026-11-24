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
        var size: CGSize
        let startMouse: CGPoint
        var startOrigin: CGPoint
        let downEvent: CGEvent
        let screenBounds: [CGRect]
        var lastOrigin: CGPoint
    }

    private let applier: AXApplier
    private var state: State = .idle

    var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

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
              let target = WindowLocator.window(at: event.location),
              let downEvent = event.copy() else { return event }

        state = .pending(Session(
            window: target.window,
            size: target.frame.size,
            startMouse: event.location,
            startOrigin: target.frame.origin,
            downEvent: downEvent,
            screenBounds: ScreenGeometry.visibleBounds(),
            lastOrigin: target.frame.origin
        ))
        return nil
    }

    private func mouseDragged(_ event: CGEvent) -> CGEvent? {
        var session: Session
        switch state {
        case .idle:
            return event
        case let .pending(pendingSession):
            let delta = event.location - pendingSession.startMouse
            guard hypot(delta.x, delta.y) >= Self.dragThreshold else { return nil }
            session = pendingSession
            applier.beginInteraction(with: session.window)
            applier.raise(session.window)

            // Dragging a tiled window out of its tile gives it back the size
            // it had before tiling, keeping the grab point under the cursor.
            let frame = CGRect(origin: session.startOrigin, size: session.size)
            if let size = TileMemory.shared.claimOriginalSize(of: session.window, currentFrame: frame) {
                let restored = TileMemory.restoredFrame(size: size, from: frame, grabbedAt: session.startMouse)
                session.size = restored.size
                session.startOrigin = restored.origin
                applier.resizeNow(session.window, to: restored.size)
            }
        case let .dragging(draggingSession):
            session = draggingSession
        }

        let delta = event.location - session.startMouse
        var origin = Self.clamp(session.startOrigin + delta, size: session.size, cursor: event.location, screens: session.screenBounds)
        origin = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())

        if origin != session.lastOrigin {
            session.lastOrigin = origin
            applier.move(session.window, to: origin)
        }
        state = .dragging(session)
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
