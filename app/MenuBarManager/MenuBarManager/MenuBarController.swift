import AppKit
import CoreGraphics

/// Controls hiding/showing of menu bar items using the CGEvent Cmd+drag technique.
/// This is the same approach used by Ice and Hidden Bar.
class MenuBarController: NSObject {
    private let discovery = MenuBarItemDiscovery()

    /// Our divider status item (the toggle icon users click).
    private var dividerItem: NSStatusItem?

    /// Currently known menu bar items and their configured states.
    private(set) var knownItems: [String: String] = [:] // name -> status

    /// Current config.
    private var config: MenuBarConfig

    /// Timer for polling.
    private var pollTimer: Timer?

    /// Track discovered items for IPC queries.
    private(set) var discoveredItems: [DiscoveredMenuItem] = []

    /// Whether hidden items are temporarily revealed.
    private(set) var isRevealed = false

    /// Max retries for hiding an item (menu bar can be unresponsive).
    private let maxRetries = 5

    /// Delay between event steps in microseconds.
    private let eventDelay: useconds_t = 80_000 // 80ms

    init(config: MenuBarConfig) {
        self.config = config
        super.init()
    }

    func start() {
        setupDivider()
        applyConfig()
        startPolling()

        // Also re-scan when apps launch or quit
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidChange),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidChange),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func reloadConfig() {
        config = MenuBarConfig.load()
        applyConfig()
    }

    func updateConfig(_ newConfig: MenuBarConfig) {
        config = newConfig
        applyConfig()
    }

    /// Temporarily show all hidden items.
    func showAll() {
        isRevealed = true
        // Collapse the divider so everything is visible
        if let item = dividerItem {
            item.button?.image = NSImage(
                systemSymbolName: "chevron.right",
                accessibilityDescription: "Show hidden icons"
            )
        }
    }

    /// Re-hide items according to config.
    func hideAgain() {
        isRevealed = false
        if let item = dividerItem {
            item.button?.image = NSImage(
                systemSymbolName: "chevron.left",
                accessibilityDescription: "Hide icons"
            )
        }
        applyConfig()
    }

    // MARK: - Private

    private func setupDivider() {
        dividerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = dividerItem?.button {
            button.image = NSImage(
                systemSymbolName: "chevron.left",
                accessibilityDescription: "MenuBar Manager"
            )
            button.action = #selector(toggleReveal)
            button.target = self
        }
    }

    @objc private func toggleReveal() {
        if isRevealed {
            hideAgain()
        } else {
            showAll()
        }
    }

    @objc private func appDidChange(_ notification: Notification) {
        // Short delay to let the new app's status item appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.poll()
        }
    }

    private func startPolling() {
        let interval = TimeInterval(config.defaults.pollInterval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let items = discovery.discoverItems()
        discoveredItems = items

        for item in items {
            let name = MenuBarItemDiscovery.displayName(for: item)
            let status = config.statusOf(name)

            if knownItems[name] != status {
                knownItems[name] = status
                applyStatusToItem(item, status: status)
            }
        }

        // Clean up items that are no longer present
        let currentNames = Set(items.map { MenuBarItemDiscovery.displayName(for: $0) })
        for name in knownItems.keys where !currentNames.contains(name) {
            knownItems.removeValue(forKey: name)
        }
    }

    private func applyConfig() {
        let items = discovery.discoverItems()
        discoveredItems = items

        for item in items {
            let name = MenuBarItemDiscovery.displayName(for: item)
            let status = config.statusOf(name)
            knownItems[name] = status
            applyStatusToItem(item, status: status)
        }
    }

    private func applyStatusToItem(_ item: DiscoveredMenuItem, status: String) {
        guard !isRevealed else { return }

        switch status {
        case "hidden", "disabled":
            hideItemWithRetry(item, attempt: 1)
        case "visible":
            break
        default:
            break
        }
    }

    /// Hide an item with retry logic. After each failed attempt, we send a "wake-up"
    /// click to restore the menu bar's responsiveness (same technique Ice uses).
    private func hideItemWithRetry(_ item: DiscoveredMenuItem, attempt: Int) {
        guard attempt <= maxRetries else {
            print("Warning: failed to hide \(item.ownerName) after \(maxRetries) attempts")
            return
        }

        if attempt > 1 {
            // Wake-up click: tap the menu bar area to reset its state
            sendWakeUpClick(at: item.frame)
            usleep(100_000) // 100ms
        }

        let success = performHide(item)

        if !success {
            // Schedule a retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.hideItemWithRetry(item, attempt: attempt + 1)
            }
        }
    }

    /// Perform the actual hide by synthesizing a Cmd+drag event.
    /// Returns true if the event was successfully created and posted.
    private func performHide(_ item: DiscoveredMenuItem) -> Bool {
        let sourcePoint = CGPoint(
            x: item.frame.origin.x + item.frame.width / 2,
            y: item.frame.origin.y + item.frame.height / 2
        )

        // Move to far off-screen left
        let destPoint = CGPoint(x: -20000, y: sourcePoint.y)

        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: sourcePoint,
            mouseButton: .left
        ),
        let mouseDragged = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: destPoint,
            mouseButton: .left
        ),
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: destPoint,
            mouseButton: .left
        ) else {
            return false
        }

        let cmdFlag = CGEventFlags.maskCommand
        mouseDown.flags = cmdFlag
        mouseDragged.flags = cmdFlag
        mouseUp.flags = cmdFlag

        // Set the target window ID so macOS knows which item to move
        mouseDown.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(item.windowID))

        mouseDown.post(tap: .cghidEventTap)
        usleep(eventDelay)
        mouseDragged.post(tap: .cghidEventTap)
        usleep(eventDelay)
        mouseUp.post(tap: .cghidEventTap)

        return true
    }

    /// Send a simple click to wake up the menu bar after a failed drag.
    private func sendWakeUpClick(at frame: CGRect) {
        let point = CGPoint(
            x: frame.origin.x + frame.width / 2,
            y: frame.origin.y + frame.height / 2
        )

        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        down.post(tap: .cghidEventTap)
        usleep(50_000)
        up.post(tap: .cghidEventTap)
    }
}
