import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
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
}
