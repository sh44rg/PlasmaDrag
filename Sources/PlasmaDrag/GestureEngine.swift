import CoreGraphics

/// Owns the event taps and routes events to the gesture controllers.
///
/// Only a listen-only tap for modifier changes is always on, and it sees just
/// a handful of events per keypress. The active tap that intercepts every
/// mouse and scroll event is switched on only while Option is held or a
/// gesture is still finishing, so normal pointer input never round-trips
/// through this process.
final class GestureEngine {
    private let applier = AXApplier()
    private lazy var moveController = MoveController(applier: applier)
    private lazy var resizeController = ResizeController(applier: applier)

    private lazy var modifierTap: EventTap = EventTap(
        events: [.flagsChanged],
        options: .listenOnly,
        handler: { [unowned self] _, event in
            updatePointerTap(optionHeld: event.flags.contains(.maskAlternate))
            return event
        },
        onDisabledBySystem: { [unowned self] in
            modifierTap.setEnabled(true)
        }
    )

    private lazy var pointerTap: EventTap = EventTap(
        events: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel],
        options: .defaultTap,
        handler: { [unowned self] type, event in handlePointer(type: type, event: event) },
        onDisabledBySystem: { [unowned self] in
            resetControllers()
            updatePointerTap(optionHeld: Self.optionHeldNow())
        }
    )

    var isRunning: Bool { modifierTap.isCreated && pointerTap.isCreated }

    @discardableResult
    func start() -> Bool {
        guard modifierTap.create(enabled: true), pointerTap.create(enabled: false) else {
            stop()
            return false
        }
        updatePointerTap(optionHeld: Self.optionHeldNow())
        return true
    }

    func stop() {
        modifierTap.destroy()
        pointerTap.destroy()
        resetControllers()
    }

    func systemDidWake() {
        guard isRunning else { return }
        modifierTap.setEnabled(true, force: true)
        resetControllers()
        pointerTap.setEnabled(Self.optionHeldNow(), force: true)
    }

    private func handlePointer(type: CGEventType, event: CGEvent) -> CGEvent? {
        let result: CGEvent?
        switch type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            result = moveController.handle(type: type, event: event)
        case .scrollWheel:
            result = resizeController.handle(event: event)
        default:
            result = event
        }

        // Self-heals a missed Option key-up (e.g. released during secure input).
        if !event.flags.contains(.maskAlternate) {
            updatePointerTap(optionHeld: false)
        }
        return result
    }

    private func updatePointerTap(optionHeld: Bool) {
        pointerTap.setEnabled(optionHeld || moveController.isActive || resizeController.isActive)
    }

    private func resetControllers() {
        moveController.reset()
        resizeController.reset()
    }

    private static func optionHeldNow() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }
}
