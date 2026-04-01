import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchAgentManager = LaunchAgentManager()
    private let didPromptForAutostartKey = "didPromptForAutostart"
    private var controller: MenuBarController!
    private var ipcServer: IPCServer!
    private var accessibilityManager: AccessibilityManager!
    private var configWatcher: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibilityManager = AccessibilityManager()

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

        print("MenuBarManager started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
        ipcServer?.stop()
        configWatcher?.cancel()
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
}
