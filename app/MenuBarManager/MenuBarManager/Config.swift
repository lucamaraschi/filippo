import Foundation

/// Reads the TOML config file. We use a simple parser since our format is straightforward.
struct MenuBarConfig: Codable {
    var defaults: DefaultsConfig
    var icons: IconsConfig

    struct DefaultsConfig: Codable {
        var unknown: String
        var pollInterval: Int

        enum CodingKeys: String, CodingKey {
            case unknown
            case pollInterval = "poll_interval"
        }
    }

    struct IconsConfig: Codable {
        var visible: [String]
        var hidden: [String]
        var disabled: [String]
    }

    static let defaultPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/menubar/config.toml")
    }()

    static func load(from url: URL? = nil) -> MenuBarConfig {
        let path = url ?? defaultPath
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return MenuBarConfig.defaultConfig
        }
        return parse(toml: content)
    }

    static var defaultConfig: MenuBarConfig {
        MenuBarConfig(
            defaults: DefaultsConfig(unknown: "hidden", pollInterval: 5),
            icons: IconsConfig(visible: [], hidden: [], disabled: [])
        )
    }

    func statusOf(_ name: String) -> String {
        if icons.visible.contains(name) { return "visible" }
        if icons.hidden.contains(name) { return "hidden" }
        if icons.disabled.contains(name) { return "disabled" }
        return defaults.unknown
    }

    /// Simple TOML parser for our specific config format.
    static func parse(toml: String) -> MenuBarConfig {
        var config = MenuBarConfig.defaultConfig
        var currentSection = ""

        for line in toml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Section headers
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }

            // Key-value pairs
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch currentSection {
            case "defaults":
                switch key {
                case "unknown":
                    config.defaults.unknown = value.replacingOccurrences(of: "\"", with: "")
                case "poll_interval":
                    config.defaults.pollInterval = Int(value) ?? 5
                default: break
                }
            case "icons":
                let items = parseTomlArray(value)
                switch key {
                case "visible":
                    config.icons.visible = items
                case "hidden":
                    config.icons.hidden = items
                case "disabled":
                    config.icons.disabled = items
                default: break
                }
            default: break
            }
        }

        return config
    }

    /// Parse a TOML array like ["foo", "bar"] or a multiline array
    private static func parseTomlArray(_ value: String) -> [String] {
        // Handle inline arrays: ["foo", "bar"]
        let stripped = value
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")

        return stripped
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
    }
}
