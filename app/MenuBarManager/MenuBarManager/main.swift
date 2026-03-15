import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Run as a menu bar only app (no dock icon)
app.setActivationPolicy(.accessory)

app.run()
