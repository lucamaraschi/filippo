import AppKit
import CoreGraphics
import MenuBarManagerCore

/// Reconciles menu bar items against filippo config using three stable zones:
/// - `visible`: between the toggle icon and the hidden divider
/// - `hidden`: between the hidden divider and the disabled divider
/// - `disabled`: to the left of the disabled divider
///
/// The hidden divider, not per-item dragging, is responsible for collapse/expand.
final class MenuBarController: NSObject, NSMenuDelegate {
    private enum Mode {
        case collapsed
        case expanded
    }

    private struct ItemState {
        var status: String
        var zone: MenuBarItemZone?
        var lastObservedZone: MenuBarItemZone?
    }

    private struct Anchors {
        let primary: CGRect
        let hiddenDivider: CGRect
        let disabledDivider: CGRect
    }

    private struct Layout {
        let targets: [String: CGPoint]
    }

    private let discovery = MenuBarItemDiscovery()
    private let maxRetries = 5
    private let eventDelay: useconds_t = 80_000
    private let itemSpacing: CGFloat = 6
    private let zoneInset: CGFloat = 8
    private let primaryItemLength: CGFloat = 20
    private let hiddenDividerExpandedLength: CGFloat = 22
    private let hiddenDividerCollapsedLength: CGFloat = 10_000
    private let disabledDividerLength: CGFloat = 10_000
    private let debugEnabled = ProcessInfo.processInfo.environment["FILIPPO_DEBUG"] == "1"
    private let launchAgentManager = LaunchAgentManager()

    private var primaryItem: NSStatusItem?
    private var hiddenDividerItem: NSStatusItem?
    private var disabledDividerItem: NSStatusItem?
    private var controlMenu: NSMenu?
    private var config: MenuBarConfig
    private var pollTimer: Timer?
    private var mode: Mode = .collapsed
    private var itemStates: [String: ItemState] = [:]
    private var suppressNextConfigReload = false
    private var prioritizedItemName: String?
    private var settleUntilByItemName: [String: Date] = [:]

    private(set) var knownItems: [String: String] = [:]
    private(set) var discoveredItems: [DiscoveredMenuItem] = []

    init(config: MenuBarConfig) {
        self.config = config
        super.init()
    }

    func start() {
        setupStatusItems()
        applyModeLayout()
        startPolling()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.reconcile(force: false)
        }

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
        if suppressNextConfigReload {
            suppressNextConfigReload = false
            return
        }
        config = MenuBarConfig.load()
        reconcile(force: true)
    }

    func updateConfig(_ newConfig: MenuBarConfig) {
        config = newConfig
        reconcile(force: true)
    }

    func showAll() {
        mode = .expanded
        applyModeLayout()
        debug("toggle -> expanded")
    }

    func hideAgain() {
        mode = .collapsed
        applyModeLayout()
        debug("toggle -> collapsed")
    }

    // MARK: - Setup

    private func setupStatusItems() {
        primaryItem = NSStatusBar.system.statusItem(withLength: primaryItemLength)
        if let button = primaryItem?.button {
            button.action = #selector(toggleReveal)
            button.target = self
        }

        hiddenDividerItem = NSStatusBar.system.statusItem(withLength: hiddenDividerCollapsedLength)
        if let button = hiddenDividerItem?.button {
            button.title = ""
            button.image = nil
            button.isEnabled = true
            button.isHidden = true
        }
        let menu = NSMenu()
        menu.delegate = self
        hiddenDividerItem?.menu = menu
        controlMenu = menu

        disabledDividerItem = NSStatusBar.system.statusItem(withLength: disabledDividerLength)
        if let button = disabledDividerItem?.button {
            button.title = ""
            button.image = nil
            button.isEnabled = false
            button.isHidden = true
        }

        updatePrimarySymbol()
    }

    private func applyModeLayout() {
        switch mode {
        case .collapsed:
            hiddenDividerItem?.length = hiddenDividerCollapsedLength
        case .expanded:
            hiddenDividerItem?.length = hiddenDividerExpandedLength
        }
        disabledDividerItem?.length = disabledDividerLength
        updatePrimarySymbol()
        updateHiddenDividerAppearance()
        debug(
            "divider lengths hidden=\(Int(hiddenDividerItem?.length ?? 0)) " +
            "disabled=\(Int(disabledDividerItem?.length ?? 0))"
        )
    }

    private func updatePrimarySymbol() {
        let symbolName = mode == .collapsed ? "chevron.left" : "chevron.right"
        let description = mode == .collapsed ? "Show hidden icons" : "Hide hidden icons"
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        )
        primaryItem?.button?.image = image
    }

    private func updateHiddenDividerAppearance() {
        guard let button = hiddenDividerItem?.button else { return }

        switch mode {
        case .collapsed:
            button.title = ""
            button.image = nil
            button.isHidden = true
        case .expanded:
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "line.3.horizontal.decrease.circle",
                accessibilityDescription: "Filippo menu"
            )
            button.image?.isTemplate = true
            button.isHidden = false
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildControlMenu(menu)
    }

    private func rebuildControlMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusItem = NSMenuItem(
            title: "Filippo",
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let daemonItem = NSMenuItem(
            title: "Daemon: running",
            action: nil,
            keyEquivalent: ""
        )
        daemonItem.isEnabled = false
        menu.addItem(daemonItem)

        let autostartItem = NSMenuItem(
            title: "Start at login",
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        autostartItem.target = self
        autostartItem.state = launchAgentManager.isInstalled() ? .on : .off
        menu.addItem(autostartItem)

        let toggleItem = NSMenuItem(
            title: mode == .collapsed ? "Show hidden icons" : "Hide hidden icons",
            action: #selector(toggleReveal),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let reloadItem = NSMenuItem(
            title: "Reload config",
            action: #selector(reloadConfigFromMenu),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(.separator())

        let names = itemNamesForMenu()
        if names.isEmpty {
            let emptyItem = NSMenuItem(title: "No menu bar items discovered", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for name in names {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.submenu = submenu(for: name)
            menu.addItem(item)
        }
    }

    private func itemNamesForMenu() -> [String] {
        var names = Set(discoveredItems.map { MenuBarItemDiscovery.displayName(for: $0) })
        names.formUnion(knownItems.keys)
        return names.sorted()
    }

    private func submenu(for name: String) -> NSMenu {
        let menu = NSMenu(title: name)
        for status in ["visible", "hidden", "disabled"] {
            let item = NSMenuItem(
                title: status.capitalized,
                action: #selector(setStatusFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = "\(name)\u{1F}| \(status)"
            item.state = config.statusOf(name) == status ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func reloadConfigFromMenu() {
        reloadConfig()
    }

    @objc private func toggleStartAtLogin() {
        do {
            if launchAgentManager.isInstalled() {
                try launchAgentManager.uninstall()
            } else if let executablePath = Bundle.main.executableURL?.path ?? CommandLine.arguments.first {
                try launchAgentManager.install(executablePath: executablePath)
            }
        } catch {
            print("Warning: failed to update launch agent: \(error.localizedDescription)")
        }

        if let menu = controlMenu {
            rebuildControlMenu(menu)
        }
    }

    @objc private func setStatusFromMenu(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        let parts = payload.components(separatedBy: "\u{1F}| ")
        guard parts.count == 2 else { return }

        let name = parts[0]
        let status = parts[1]

        config.setStatus(name, status: status)
        do {
            suppressNextConfigReload = true
            prioritizedItemName = name
            settleUntilByItemName.removeValue(forKey: name)
            try config.save()
            reconcile(force: false)
        } catch {
            suppressNextConfigReload = false
            prioritizedItemName = nil
            print("Warning: failed to save config: \(error.localizedDescription)")
        }
    }

    @objc private func toggleReveal() {
        switch mode {
        case .collapsed:
            showAll()
        case .expanded:
            hideAgain()
        }
    }

    @objc private func appDidChange(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reconcile(force: true)
        }
    }

    private func startPolling() {
        let interval = TimeInterval(config.defaults.pollInterval)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.reconcile(force: false)
        }
    }

    // MARK: - Reconciliation

    private func reconcile(force: Bool) {
        let items = discovery.discoverItems()
        discoveredItems = items
        applyModeLayout()
        debug("reconcile mode=\(modeLabel) force=\(force) discovered=\(items.count)")

        for item in items {
            let name = MenuBarItemDiscovery.displayName(for: item)
            let status = config.statusOf(name)
            knownItems[name] = status

            var state = itemStates[name] ?? ItemState(status: status, zone: nil, lastObservedZone: nil)
            state.status = status
            itemStates[name] = state
        }

        let currentNames = Set(items.map { MenuBarItemDiscovery.displayName(for: $0) })
        for name in itemStates.keys where !currentNames.contains(name) {
            itemStates.removeValue(forKey: name)
            knownItems.removeValue(forKey: name)
        }

        guard let anchors = currentAnchors(for: items) else {
            debug("anchors unavailable")
            return
        }

        debugAnchors(anchors)

        let ordered = orderedItems(items)
        let layout = layout(for: ordered, anchors: anchors)

        for item in ordered {
            let itemName = MenuBarItemDiscovery.displayName(for: item)
            let itemForce = force || prioritizedItemName == itemName
            applyZone(for: item, anchors: anchors, layout: layout, force: itemForce)
        }
    }

    private func orderedItems(_ items: [DiscoveredMenuItem]) -> [DiscoveredMenuItem] {
        items.sorted { lhs, rhs in
            let lhsName = MenuBarItemDiscovery.displayName(for: lhs)
            let rhsName = MenuBarItemDiscovery.displayName(for: rhs)
            let lhsZone = MenuBarVisibilityPolicy.desiredPlacement(
                status: config.statusOf(lhsName),
                isExpanded: mode == .expanded
            )
            let rhsZone = MenuBarVisibilityPolicy.desiredPlacement(
                status: config.statusOf(rhsName),
                isExpanded: mode == .expanded
            )

            let rankCompare = rank(for: lhsZone) == rank(for: rhsZone)
            if rankCompare {
                return lhs.frame.maxX > rhs.frame.maxX
            }

            return rank(for: lhsZone) < rank(for: rhsZone)
        }
    }

    private func rank(for zone: MenuBarItemZone) -> Int {
        switch zone {
        case .visible:
            return 0
        case .hidden:
            return 1
        case .disabled:
            return 2
        }
    }

    private func applyZone(
        for item: DiscoveredMenuItem,
        anchors: Anchors,
        layout: Layout,
        force: Bool
    ) {
        let name = MenuBarItemDiscovery.displayName(for: item)
        let status = config.statusOf(name)
        let desiredZone = MenuBarVisibilityPolicy.desiredPlacement(
            status: status,
            isExpanded: mode == .expanded
        )
        let actualZone = zone(for: item, anchors: anchors)
        guard var state = itemStates[name] else { return }
        state.lastObservedZone = actualZone

        debugItem(item, status: status, actualZone: actualZone, desiredZone: desiredZone)

        if shouldIgnoreCorrections(for: item, desiredZone: desiredZone, force: force) {
            state.zone = desiredZone
            itemStates[name] = state
            if prioritizedItemName == name {
                prioritizedItemName = nil
            }
            return
        }

        if !force, !needsCorrection(actualZone: actualZone, desiredZone: desiredZone) {
            state.zone = desiredZone
            itemStates[name] = state
            if prioritizedItemName == name {
                prioritizedItemName = nil
            }
            return
        }

        guard let destination = layout.targets[name] else {
            itemStates[name] = state
            return
        }
        let label: String
        switch desiredZone {
        case .visible:
            label = "show"
        case .hidden:
            label = "hide"
        case .disabled:
            label = "disable"
        }

        if moveItemWithRetry(item, to: destination, label: label, attempt: 1) {
            state.zone = desiredZone
            itemStates[name] = state
            settleUntilByItemName[name] = Date().addingTimeInterval(0.75)
            if prioritizedItemName == name {
                prioritizedItemName = nil
            }
            return
        }

        itemStates[name] = state
    }

    private func shouldIgnoreCorrections(
        for item: DiscoveredMenuItem,
        desiredZone: MenuBarItemZone,
        force: Bool
    ) -> Bool {
        let name = MenuBarItemDiscovery.displayName(for: item)

        if !force, let settleUntil = settleUntilByItemName[name], settleUntil > Date() {
            return true
        }

        // Input Sources is managed by a system agent that frequently snaps back to x=0.
        // Treat it as best-effort so it does not cause endless correction churn.
        if name == "Input Sources", item.frame.minX <= 1 {
            return !force || desiredZone == .hidden
        }

        return false
    }

    private func needsCorrection(
        actualZone: MenuBarItemZone,
        desiredZone: MenuBarItemZone
    ) -> Bool {
        switch desiredZone {
        case .visible:
            return actualZone != .visible
        case .hidden:
            switch mode {
            case .collapsed:
                return actualZone == .visible
            case .expanded:
                return actualZone == .disabled
            }
        case .disabled:
            return actualZone != .disabled
        }
    }

    // MARK: - Movement

    private func moveItemWithRetry(
        _ item: DiscoveredMenuItem,
        to destinationPoint: CGPoint,
        label: String,
        attempt: Int
    ) -> Bool {
        guard attempt <= maxRetries else {
            print("Warning: failed to \(label) \(item.ownerName) after \(maxRetries) attempts")
            return false
        }

        let sourcePoint = centerPoint(for: item.frame)
        let success = performMove(
            windowID: item.windowID,
            sourcePoint: sourcePoint,
            destinationPoint: destinationPoint
        )

        debug(
            "move \(label) \(MenuBarItemDiscovery.displayName(for: item)) success=\(success) " +
            "src=\(pointDescription(sourcePoint)) dst=\(pointDescription(destinationPoint)) " +
            "frame=\(frameDescription(item.frame))"
        )

        if success {
            return true
        }

        if attempt > 1 {
            sendWakeUpClick(at: item.frame)
            usleep(100_000)
        }

        return moveItemWithRetry(item, to: destinationPoint, label: label, attempt: attempt + 1)
    }

    private func performMove(
        windowID: UInt32,
        sourcePoint: CGPoint,
        destinationPoint: CGPoint
    ) -> Bool {
        let originalCursorLocation = CGEvent(source: nil)?.location

        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: sourcePoint,
            mouseButton: .left
        ),
        let mouseDragged = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: destinationPoint,
            mouseButton: .left
        ),
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: destinationPoint,
            mouseButton: .left
        ) else {
            return false
        }

        let flags = CGEventFlags.maskCommand
        mouseDown.flags = flags
        mouseDragged.flags = flags
        mouseUp.flags = flags

        mouseDown.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        mouseDragged.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        mouseUp.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))

        mouseDown.post(tap: .cghidEventTap)
        usleep(eventDelay)
        mouseDragged.post(tap: .cghidEventTap)
        usleep(eventDelay)
        mouseUp.post(tap: .cghidEventTap)

        if let originalCursorLocation {
            CGWarpMouseCursorPosition(originalCursorLocation)
        }

        return true
    }

    private func sendWakeUpClick(at frame: CGRect) {
        let point = centerPoint(for: frame)

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

    // MARK: - Geometry

    private func currentAnchors(for items: [DiscoveredMenuItem]) -> Anchors? {
        guard let primary = primaryFrame(),
              let hiddenDivider = hiddenDividerFrame(),
              let disabledDivider = disabledDividerFrame() else {
            return nil
        }

        return Anchors(
            primary: primary,
            hiddenDivider: hiddenDivider,
            disabledDivider: disabledDivider
        )
    }

    private func zone(for item: DiscoveredMenuItem, anchors: Anchors) -> MenuBarItemZone {
        let x = item.frame.midX
        if x < anchors.disabledDivider.minX {
            return .disabled
        }
        if x < anchors.hiddenDivider.minX {
            return .hidden
        }
        return .visible
    }

    private func destinationPoint(
        for item: DiscoveredMenuItem,
        rightBoundaryX: CGFloat,
        y: CGFloat,
        cursor: inout CGFloat
    ) -> CGPoint {
        let target = CGPoint(
            x: cursor - (item.frame.width / 2),
            y: y
        )
        cursor -= item.frame.width + itemSpacing
        return target
    }

    private func layout(for items: [DiscoveredMenuItem], anchors: Anchors) -> Layout {
        var targets: [String: CGPoint] = [:]

        let visibleItems = items.filter { desiredZone(for: $0) == .visible }
        let hiddenItems = items.filter { desiredZone(for: $0) == .hidden }
        let disabledItems = items.filter { desiredZone(for: $0) == .disabled }

        populateTargets(
            for: visibleItems,
            rightBoundaryX: anchors.primary.maxX + 160,
            targets: &targets
        )
        populateTargets(
            for: hiddenItems,
            rightBoundaryX: anchors.hiddenDivider.minX - zoneInset,
            targets: &targets
        )
        populateTargets(
            for: disabledItems,
            rightBoundaryX: anchors.disabledDivider.minX - zoneInset,
            targets: &targets
        )

        return Layout(targets: targets)
    }

    private func populateTargets(
        for items: [DiscoveredMenuItem],
        rightBoundaryX: CGFloat,
        targets: inout [String: CGPoint]
    ) {
        var cursor = rightBoundaryX - itemSpacing
        for item in items {
            let name = MenuBarItemDiscovery.displayName(for: item)
            targets[name] = destinationPoint(
                for: item,
                rightBoundaryX: rightBoundaryX,
                y: item.frame.midY,
                cursor: &cursor
            )
        }
    }

    private func desiredZone(for item: DiscoveredMenuItem) -> MenuBarItemZone {
        let name = MenuBarItemDiscovery.displayName(for: item)
        return MenuBarVisibilityPolicy.desiredPlacement(
            status: config.statusOf(name),
            isExpanded: mode == .expanded
        )
    }

    private func primaryFrame() -> CGRect? {
        primaryItem?.button?.window?.frame
    }

    private func disabledDividerFrame() -> CGRect? {
        disabledDividerItem?.button?.window?.frame
    }

    private func hiddenDividerFrame() -> CGRect? {
        hiddenDividerItem?.button?.window?.frame
    }

    private func centerPoint(for frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - Debug

    private var modeLabel: String {
        switch mode {
        case .collapsed:
            return "collapsed"
        case .expanded:
            return "expanded"
        }
    }

    private func debug(_ message: String) {
        guard debugEnabled else { return }
        print("[filippo-debug] \(message)")
    }

    private func debugAnchors(_ anchors: Anchors) {
        debug(
            "anchors primary=\(frameDescription(anchors.primary)) " +
            "hiddenDivider=\(frameDescription(anchors.hiddenDivider)) " +
            "disabledDivider=\(frameDescription(anchors.disabledDivider))"
        )
    }

    private func debugItem(
        _ item: DiscoveredMenuItem,
        status: String,
        actualZone: MenuBarItemZone,
        desiredZone: MenuBarItemZone
    ) {
        guard debugEnabled else { return }
        let name = MenuBarItemDiscovery.displayName(for: item)
        print(
            "[filippo-debug] item \(name) owner=\(item.ownerName) status=\(status) " +
            "actualZone=\(zoneLabel(actualZone)) desiredZone=\(zoneLabel(desiredZone)) " +
            "frame=\(frameDescription(item.frame)) window=\(item.windowID)"
        )
    }

    private func zoneLabel(_ zone: MenuBarItemZone) -> String {
        switch zone {
        case .visible:
            return "visible"
        case .hidden:
            return "hidden"
        case .disabled:
            return "disabled"
        }
    }

    private func frameDescription(_ frame: CGRect) -> String {
        "x=\(Int(frame.origin.x)),y=\(Int(frame.origin.y)),w=\(Int(frame.width)),h=\(Int(frame.height))"
    }

    private func pointDescription(_ point: CGPoint) -> String {
        "x=\(Int(point.x)),y=\(Int(point.y))"
    }
}
