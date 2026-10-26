import ApplicationServices
import Foundation

/// Applies window geometry changes off the event-tap thread. Only the most
/// recent pending change is kept, so a burst of drag events collapses into as
/// many AX writes as the target app can actually keep up with.
final class AXApplier {
    private enum Operation {
        case move(AXUIElement, CGPoint)
        case resize(AXUIElement, CGSize)
    }

    private let queue = DispatchQueue(label: "com.shaaravg.plasmadrag.ax", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: Operation?
    private var drainScheduled = false

    private var enhancedUIRestorePIDs: Set<pid_t> = []

    func move(_ window: AXUIElement, to origin: CGPoint) {
        submit(.move(window, origin))
    }

    func resize(_ window: AXUIElement, to size: CGSize) {
        submit(.resize(window, size))
    }

    func raise(_ window: AXUIElement) {
        queue.async {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            if let pid = window.pid {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            }
        }
    }

    /// Some apps (notably Chromium/Electron) animate AX geometry changes while
    /// AXEnhancedUserInterface is on, which makes dragging laggy. Turn it off
    /// for the duration of an interaction.
    func beginInteraction(with window: AXUIElement) {
        guard let pid = window.pid else { return }
        queue.async {
            let app = AXUIElementCreateApplication(pid)
            if let enhanced: Bool = app.attribute("AXEnhancedUserInterface"), enhanced {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
                self.enhancedUIRestorePIDs.insert(pid)
            }
        }
    }

    func endInteraction(with window: AXUIElement) {
        guard let pid = window.pid else { return }
        queue.async {
            guard self.enhancedUIRestorePIDs.remove(pid) != nil else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    private func submit(_ operation: Operation) {
        lock.lock()
        pending = operation
        let shouldSchedule = !drainScheduled
        drainScheduled = true
        lock.unlock()

        if shouldSchedule {
            queue.async { self.drain() }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let operation = pending else {
                drainScheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()

            perform(operation)
        }
    }

    private func perform(_ operation: Operation) {
        switch operation {
        case let .move(window, origin):
            window.setPosition(origin)

        case let .resize(window, size):
            window.setSize(size)
        }
    }
}
