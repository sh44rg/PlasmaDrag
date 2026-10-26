import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let enabledKey = "enabled"

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var trustPollTimer: Timer?

    private let applier = AXApplier()
    private lazy var moveController = MoveController(applier: applier)
    private lazy var resizeController = ResizeController(applier: applier)
    private lazy var eventTap = EventTap(
        handler: { [unowned self] type, event in self.handle(type: type, event: event) },
        onReset: { [unowned self] in self.resetControllers() }
    )

    private var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if AXIsProcessTrusted() {
            startTapIfNeeded()
        } else {
            requestAccessibility()
        }
    }

    // MARK: - Event routing

    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return moveController.handle(type: type, event: event)
        case .scrollWheel:
            return resizeController.handle(event: event)
        default:
            return event
        }
    }

    private func resetControllers() {
        moveController.reset()
        resizeController.reset()
    }

    private func startTapIfNeeded() {
        guard isEnabled, AXIsProcessTrusted() else { return }
        if !eventTap.start() {
            NSLog("PlasmaDrag: failed to create event tap")
        }
        updateStatusIcon()
    }

    @objc private func systemDidWake() {
        if isEnabled { eventTap.ensureEnabled() }
    }

    // MARK: - Accessibility

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTapIfNeeded()
            return
        }
        trustPollTimer?.invalidate()
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.trustPollTimer = nil
            self?.startTapIfNeeded()
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = isEnabled && eventTap.isRunning ? "macwindow.on.rectangle" : "macwindow"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PlasmaDrag") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.title = "PD"
        }
        button.appearsDisabled = !(isEnabled && eventTap.isRunning)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "PlasmaDrag", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for hint in ["Option + drag: move window", "Option + two-finger drag: resize window"] {
            let item = NSMenuItem(title: hint, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)

        if AXIsProcessTrusted() {
            let item = NSMenuItem(title: "Accessibility: Granted", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Grant Accessibility Access...", action: #selector(grantAccess), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit PlasmaDrag", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            startTapIfNeeded()
            if !AXIsProcessTrusted() { requestAccessibility() }
        } else {
            eventTap.stop()
            resetControllers()
        }
        updateStatusIcon()
    }

    @objc private func grantAccess() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
