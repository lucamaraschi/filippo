import AppKit
import ApplicationServices

/// Manages accessibility permission checking and prompting.
class AccessibilityManager {
    private var pollTimer: Timer?
    private var onGranted: (() -> Void)?

    /// Check if we have accessibility permission.
    var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Ensure accessibility is granted. If not, prompt the user and poll until granted.
    /// Calls `completion` on the main thread once permission is available.
    func ensureAccess(completion: @escaping () -> Void) {
        if isGranted {
            completion()
            return
        }

        onGranted = completion
        promptForAccess()
        startPolling()
    }

    /// Show an alert explaining why we need accessibility, then trigger the system prompt.
    private func promptForAccess() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            MenuBarManager needs Accessibility access to manage menu bar icons. \
            This allows the app to rearrange and hide icons in your menu bar.

            Click "Open System Settings" to grant access, then enable MenuBarManager \
            in the list.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            NSApp.terminate(nil)
            return
        }

        // Trigger the system accessibility prompt / open System Settings
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Poll every 2 seconds until accessibility is granted.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if AXIsProcessTrusted() {
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                print("Accessibility permission granted")
                if let callback = self.onGranted {
                    self.onGranted = nil
                    DispatchQueue.main.async { callback() }
                }
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }
}
