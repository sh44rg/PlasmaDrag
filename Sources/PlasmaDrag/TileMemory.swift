import AppKit
import ApplicationServices

/// Remembers each tiled window's frame from before it was first tiled, and
/// gives it back its old size as soon as the user drags it out of its tile.
/// Main thread only.
final class TileMemory {
    static let shared = TileMemory()

    private struct Entry {
        let window: AXUIElement
        let original: CGRect
        /// Where tiling left the window; nil while a tiling write is in flight.
        var tiled: CGRect?
    }

    private static let notifications = [
        kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
    ]

    private var entries: [Entry] = []
    private var observers: [pid_t: AXObserver] = [:]

    // MARK: - Tiling

    /// Call before moving `window` into a tile. A window that is still in the
    /// tile it was last given keeps its original pre-tiling frame.
    func beginPlacing(_ window: AXUIElement, currentFrame: CGRect) {
        if let index = index(of: window) {
            let entry = entries[index]
            if entry.tiled.map({ Self.matches($0, currentFrame) }) ?? true {
                entries[index].tiled = nil
                return
            }
            entries.remove(at: index)
        }
        entries.append(Entry(window: window, original: currentFrame, tiled: nil))
    }

    /// Call once the window has been placed, with the frame it actually took.
    func finishPlacing(_ window: AXUIElement, frame: CGRect?) {
        guard let index = index(of: window) else { return }
        guard let frame else {
            forget(window)
            return
        }
        entries[index].tiled = frame
        observe(window)
    }

    // MARK: - Dragging out

    /// For a drag that PlasmaDrag performs itself: if `window` is still in its
    /// tile, stops tracking it and returns the size it had before tiling.
    func claimOriginalSize(of window: AXUIElement, currentFrame: CGRect) -> CGSize? {
        guard let index = index(of: window), let tiled = entries[index].tiled,
              Self.matches(tiled, currentFrame) else { return nil }
        let original = entries[index].original
        forget(window)
        return original.size
    }

    /// The frame a window of `frame` should take when restored to `size`
    /// while grabbed at `cursor`: the grab point keeps its relative position,
    /// so the window stays under the cursor.
    static func restoredFrame(size: CGSize, from frame: CGRect, grabbedAt cursor: CGPoint) -> CGRect {
        let fractionX = frame.width > 0 ? (cursor.x - frame.minX) / frame.width : 0.5
        var offsetY = cursor.y - frame.minY
        if offsetY > size.height, frame.height > 0 {
            offsetY = offsetY / frame.height * size.height
        }
        return CGRect(
            x: (cursor.x - fractionX * size.width).rounded(),
            y: (cursor.y - offsetY).rounded(),
            width: size.width, height: size.height
        )
    }

    // MARK: - AX notifications

    fileprivate func handle(_ notification: String, element: AXUIElement) {
        guard let index = index(of: element) else { return }

        if notification == kAXUIElementDestroyedNotification as String {
            forget(element)
            return
        }
        guard let tiled = entries[index].tiled, let frame = element.frame else { return }

        // Resized by the user: it no longer belongs to its tile.
        if !Self.sizesMatch(tiled.size, frame.size) {
            forget(element)
            return
        }
        guard notification == kAXMovedNotification as String,
              abs(frame.minX - tiled.minX) > 2 || abs(frame.minY - tiled.minY) > 2 else { return }

        let original = entries[index].original
        forget(element)

        // Moved by something other than a mouse drag (a shortcut, another
        // tool): leave the size alone.
        guard NSEvent.pressedMouseButtons & 1 != 0,
              let primaryHeight = NSScreen.screens.first?.frame.height else { return }

        let mouse = NSEvent.mouseLocation
        let cursor = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        let restored = Self.restoredFrame(size: original.size, from: frame, grabbedAt: cursor)
        Tiler.queue.async {
            element.setSize(restored.size)
            element.setPosition(restored.origin)
        }
    }

    private func observe(_ window: AXUIElement) {
        guard let pid = window.pid else { return }
        let observer: AXObserver
        if let existing = observers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            guard AXObserverCreate(pid, tileMemoryCallback, &created) == .success, let created else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            observers[pid] = created
            observer = created
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }

    private func forget(_ window: AXUIElement) {
        guard let index = index(of: window) else { return }
        entries.remove(at: index)

        guard let pid = window.pid, let observer = observers[pid] else { return }
        for name in Self.notifications {
            AXObserverRemoveNotification(observer, window, name as CFString)
        }
        if !entries.contains(where: { $0.window.pid == pid }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = nil
        }
    }

    private func index(of window: AXUIElement) -> Int? {
        entries.firstIndex { CFEqual($0.window, window) }
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && sizesMatch(a.size, b.size)
    }

    private static func sizesMatch(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}

private func tileMemoryCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<TileMemory>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element: element)
}
