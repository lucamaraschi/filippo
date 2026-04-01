import AppKit

extension Notification.Name {
    static let filippoRunSetupWizard = Notification.Name("filippo.runSetupWizard")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchAgentManager = LaunchAgentManager()
    private let didPromptForAutostartKey = "didPromptForAutostart"
    private let didPromptForInitialSetupKey = "didPromptForInitialSetup"
    private var controller: MenuBarController!
    private var ipcServer: IPCServer!
    private var accessibilityManager: AccessibilityManager!
    private var configWatcher: DispatchSourceFileSystemObject?
    private var initialSetupWindowController: InitialSetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibilityManager = AccessibilityManager()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(runSetupWizardFromMenu),
            name: .filippoRunSetupWizard,
            object: nil
        )

        // Check accessibility first — CGEvent posting requires it
        accessibilityManager.ensureAccess { [weak self] in
            self?.startApp()
        }
    }

    private func startApp() {
        let config = MenuBarConfig.load()
        controller = MenuBarController(config: config)
        ipcServer = IPCServer(controller: controller)

        controller.start()
        ipcServer.start()
        watchConfigFile()
        promptForAutostartIfNeeded()
        promptForInitialSetupIfNeeded()

        print("MenuBarManager started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
        ipcServer?.stop()
        configWatcher?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// Watch the config file for changes (supports live reload from nix switch, editor saves, etc.)
    private func watchConfigFile() {
        let path = MenuBarConfig.defaultPath.path
        let dir = (path as NSString).deletingLastPathComponent

        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("Warning: could not watch config file")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            print("Config file changed, reloading...")
            self?.controller.reloadConfig()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        configWatcher = source
    }

    private func promptForAutostartIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        guard !launchAgentManager.isInstalled() else { return }
        guard !UserDefaults.standard.bool(forKey: didPromptForAutostartKey) else { return }

        UserDefaults.standard.set(true, forKey: didPromptForAutostartKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }

            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Start Filippo at login?"
            alert.informativeText = "Filippo can launch automatically when you sign in so your menu bar layout is applied without any extra steps."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Start at Login")
            alert.addButton(withTitle: "Not Now")

            if alert.runModal() == .alertFirstButtonReturn,
               let executablePath = Bundle.main.executableURL?.path ?? CommandLine.arguments.first {
                do {
                    try self.launchAgentManager.install(executablePath: executablePath)
                } catch {
                    print("Warning: failed to install launch agent: \(error.localizedDescription)")
                }
            }
        }
    }

    private func promptForInitialSetupIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        guard !UserDefaults.standard.bool(forKey: didPromptForInitialSetupKey) else { return }
        guard shouldPromptForInitialSetup() else { return }

        UserDefaults.standard.set(true, forKey: didPromptForInitialSetupKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showInitialSetupPrompt()
        }
    }

    private func shouldPromptForInitialSetup() -> Bool {
        let configExists = FileManager.default.fileExists(atPath: MenuBarConfig.defaultPath.path)
        let config = MenuBarConfig.load()
        let hasExplicitIcons = !config.icons.visible.isEmpty || !config.icons.hidden.isEmpty || !config.icons.disabled.isEmpty
        return !configExists || !hasExplicitIcons
    }

    private func showInitialSetupPrompt() {
        let itemNames = currentSetupItemNames()
        guard !itemNames.isEmpty else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Create your first Filippo layout?"
        alert.informativeText = "You can review the icons currently in your menu bar, or start with a minimal setup that hides everything by default."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Review Current Icons")
        alert.addButton(withTitle: "Minimal Experience")
        alert.addButton(withTitle: "Not Now")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openInitialSetupWizard(with: itemNames)
        case .alertSecondButtonReturn:
            applyMinimalExperience(using: itemNames)
        default:
            break
        }
    }

    private func currentSetupItemNames() -> [String] {
        let names = controller.discoveredItems.map { MenuBarItemDiscovery.displayName(for: $0) }
        return Array(Set(names)).sorted()
    }

    private func applyMinimalExperience(using itemNames: [String]) {
        var config = MenuBarConfig.load()
        config.icons.visible = []
        config.icons.hidden = itemNames
        config.icons.disabled = []
        saveAndApply(config)
    }

    private func openInitialSetupWizard(with itemNames: [String]) {
        let config = MenuBarConfig.load()
        let windowController = InitialSetupWindowController(
            itemNames: itemNames,
            config: config
        ) { [weak self] updatedConfig in
            self?.saveAndApply(updatedConfig)
        }

        initialSetupWindowController = windowController
        windowController.runModal()
    }

    private func saveAndApply(_ config: MenuBarConfig) {
        do {
            try config.save()
            controller.updateConfig(config)
        } catch {
            print("Warning: failed to save initial config: \(error.localizedDescription)")
        }
    }

    @objc private func runSetupWizardFromMenu() {
        let itemNames = currentSetupItemNames()
        guard !itemNames.isEmpty else { return }
        openInitialSetupWizard(with: itemNames)
    }
}
