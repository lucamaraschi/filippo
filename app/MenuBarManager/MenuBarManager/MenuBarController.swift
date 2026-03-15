import AppKit
import CoreGraphics

/// Controls hiding/showing of menu bar items using the CGEvent Cmd+drag technique.
/// This is the same approach used by Ice and Hidden Bar.
class MenuBarController {
    private let discovery = MenuBarItemDiscovery()

    /// Our divider status items that act as section boundaries.
    private var visibleDivider: NSStatusItem?
    private var hiddenDivider: NSStatusItem?

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

    init(config: MenuBarConfig) {
        self.config = config
    }

    func start() {
        setupDividers()
        applyConfig()
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
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
        // Move the divider to expose hidden items
        if let divider = visibleDivider {
            divider.length = 0
        }
    }

    /// Re-hide items according to config.
    func hideAgain() {
        isRevealed = false
        if let divider = visibleDivider {
            divider.length = NSStatusItem.squareLength
        }
        applyConfig()
    }

    // MARK: - Private

    private func setupDividers() {
        // Create a visible divider (the toggle icon users click)
        visibleDivider = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = visibleDivider?.button {
            button.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "MenuBar Manager")
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

    private func startPolling() {
        let interval = TimeInterval(config.defaults.pollInterval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let items = discovery.discoverItems()
        discoveredItems = items

        // Check for new items that need to be managed
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
        for name in knownItems.keys {
            if !currentNames.contains(name) {
                knownItems.removeValue(forKey: name)
            }
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
        case "hidden":
            hideItem(item)
        case "disabled":
            hideItem(item)
        case "visible":
            // Item is already visible, nothing to do unless it was previously hidden
            break
        default:
            break
        }
    }

    /// Hide an item by synthesizing a Cmd+drag event to move it off-screen.
    /// This is the technique used by Ice: we create mouse events with the
    /// Command modifier flag, which macOS interprets as a menu bar item
    /// reorder gesture.
    private func hideItem(_ item: DiscoveredMenuItem) {
        let sourcePoint = CGPoint(
            x: item.frame.origin.x + item.frame.width / 2,
            y: item.frame.origin.y + item.frame.height / 2
        )

        // Move to far off-screen left (past all visible items)
        let destPoint = CGPoint(x: -20000, y: sourcePoint.y)

        // Synthesize Cmd+drag
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: sourcePoint,
            mouseButton: .left
        ) else { return }

        guard let mouseDragged = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: destPoint,
            mouseButton: .left
        ) else { return }

        guard let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: destPoint,
            mouseButton: .left
        ) else { return }

        let cmdFlag = CGEventFlags.maskCommand
        mouseDown.flags = cmdFlag
        mouseDragged.flags = cmdFlag
        mouseUp.flags = cmdFlag

        // Post the events
        mouseDown.post(tap: .cghidEventTap)
        usleep(50000) // 50ms
        mouseDragged.post(tap: .cghidEventTap)
        usleep(50000)
        mouseUp.post(tap: .cghidEventTap)
    }
}

// Make it an NSObject subclass for @objc selector support
extension MenuBarController: NSObjectProtocol {
    var `class`: AnyClass { type(of: self) }
    func isEqual(_ object: Any?) -> Bool { self === object as AnyObject }
    var hash: Int { ObjectIdentifier(self).hashValue }
    var superclass: AnyClass? { nil }
    func `self`() -> Self { self }
    func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }
    func isProxy() -> Bool { false }
    func isKind(of aClass: AnyClass) -> Bool { false }
    func isMember(of aClass: AnyClass) -> Bool { false }
    func conforms(to aProtocol: Protocol) -> Bool { false }
    func responds(to aSelector: Selector!) -> Bool { false }
    var description: String { "MenuBarController" }
}
