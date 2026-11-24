import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let enabledKey = "enabled"
    private static let greenButtonFillsWindowKey = "greenButtonFillsWindow"

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var trustPollTimer: Timer?
    private let engine = GestureEngine()
    private lazy var greenButton = GreenButtonController()
    private var appNapActivity: NSObjectProtocol?

    private lazy var layoutPicker: LayoutPickerView = {
        let picker = LayoutPickerView()
        picker.onSelect = { [weak self] layout in
            guard AXIsProcessTrusted() else {
                self?.requestAccessibility()
                return
            }
            Tiler.apply(layout)
        }
        return picker
    }()

    private var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    private var greenButtonFillsWindow: Bool {
        get { UserDefaults.standard.bool(forKey: Self.greenButtonFillsWindowKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.greenButtonFillsWindowKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App Nap would delay delivery of the Option key-down that arms the
        // pointer tap. The process is blocked in the run loop when idle, so
        // opting out costs no CPU.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Responding to window move/resize gestures"
        )

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

    // MARK: - Engine

    private func startTapIfNeeded() {
        guard isEnabled, AXIsProcessTrusted() else { return }
        if !engine.start() {
            NSLog("PlasmaDrag: failed to create event taps")
        }
        updateGreenButton()
        updateStatusIcon()
    }

    private func updateGreenButton() {
        guard isEnabled, greenButtonFillsWindow, AXIsProcessTrusted() else {
            greenButton.stop()
            return
        }
        if !greenButton.start() {
            NSLog("PlasmaDrag: failed to create the green button event tap")
        }
    }

    @objc private func systemDidWake() {
        engine.systemDidWake()
        if isEnabled, greenButtonFillsWindow {
            greenButton.systemDidWake()
            updateGreenButton()
        }
    }

    // MARK: - Accessibility

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTapIfNeeded()
            return
        }
        trustPollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.trustPollTimer = nil
            self?.startTapIfNeeded()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        trustPollTimer = timer
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
        let symbol = isEnabled && engine.isRunning ? "macwindow.on.rectangle" : "macwindow"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PlasmaDrag") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.title = "PD"
        }
        button.appearsDisabled = !(isEnabled && engine.isRunning)
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

        let tileHeader = NSMenuItem(title: "Tile Windows", action: nil, keyEquivalent: "")
        tileHeader.isEnabled = false
        menu.addItem(tileHeader)

        let pickerItem = NSMenuItem()
        pickerItem.view = layoutPicker
        menu.addItem(pickerItem)

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)

        let greenButtonItem = NSMenuItem(
            title: "Green Button Fills Window", action: #selector(toggleGreenButton), keyEquivalent: ""
        )
        greenButtonItem.target = self
        greenButtonItem.state = greenButtonFillsWindow ? .on : .off
        menu.addItem(greenButtonItem)

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

        let about = NSMenuItem(title: "About PlasmaDrag", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit PlasmaDrag", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            startTapIfNeeded()
            if !AXIsProcessTrusted() { requestAccessibility() }
        } else {
            engine.stop()
            greenButton.stop()
        }
        updateStatusIcon()
    }

    @objc private func toggleGreenButton() {
        greenButtonFillsWindow.toggle()
        if isEnabled, greenButtonFillsWindow, !AXIsProcessTrusted() {
            requestAccessibility()
        } else {
            updateGreenButton()
        }
    }

    @objc private func showAbout() {
        // A menu bar app isn't active by default, so the panel would open
        // behind other windows.
        NSApp.activate()
        let credits = NSAttributedString(
            string: "KDE Plasma-style window moving, resizing and tiling for macOS.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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
