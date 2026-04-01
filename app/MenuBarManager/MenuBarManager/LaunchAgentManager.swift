import Foundation

final class LaunchAgentManager {
    private let label = "com.filippo.agent"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func install(executablePath: String) throws {
        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if isInstalled() {
            try? runLaunchctl(arguments: ["unload", plistURL.path])
        }

        try plist(executablePath: executablePath).write(to: plistURL, atomically: true, encoding: .utf8)
        try runLaunchctl(arguments: ["load", plistURL.path])
    }

    func uninstall() throws {
        if isInstalled() {
            try? runLaunchctl(arguments: ["unload", plistURL.path])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private func runLaunchctl(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "LaunchAgentManager",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "launchctl \(arguments.joined(separator: " ")) failed"]
            )
        }
    }

    private func plist(executablePath: String) -> String {
        let appPath = appBundlePath(for: executablePath)
        let programArguments: String

        if let appPath {
            programArguments = """
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>-gj</string>
                    <string>\(appPath)</string>
                </array>
            """
        } else {
            programArguments = """
                <key>ProgramArguments</key>
                <array>
                    <string>\(executablePath)</string>
                </array>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            \(programArguments)
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/tmp/filippo.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/filippo.err</string>
        </dict>
        </plist>
        """
    }

    private func appBundlePath(for executablePath: String) -> String? {
        let marker = ".app/Contents/MacOS/"
        guard let range = executablePath.range(of: marker) else {
            return nil
        }

        return String(executablePath[..<range.upperBound]).replacingOccurrences(of: "/Contents/MacOS/", with: "")
    }
}
