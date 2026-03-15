import Foundation
import TOMLKit

struct MenuBarConfig {
    var defaults: DefaultsConfig
    var icons: IconsConfig

    struct DefaultsConfig {
        var unknown: String
        var pollInterval: Int
    }

    struct IconsConfig {
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

        guard let table = try? TOMLTable(string: content) else {
            print("Warning: failed to parse config TOML, using defaults")
            return MenuBarConfig.defaultConfig
        }

        var config = MenuBarConfig.defaultConfig

        if let defaults = table["defaults"] as? TOMLTable {
            if let unknown = defaults["unknown"] as? String {
                config.defaults.unknown = unknown
            }
            if let poll = defaults["poll_interval"] as? Int {
                config.defaults.pollInterval = poll
            }
        }

        if let icons = table["icons"] as? TOMLTable {
            config.icons.visible = tomlArrayToStrings(icons["visible"])
            config.icons.hidden = tomlArrayToStrings(icons["hidden"])
            config.icons.disabled = tomlArrayToStrings(icons["disabled"])
        }

        return config
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

    private static func tomlArrayToStrings(_ value: TOMLValueConvertible?) -> [String] {
        guard let array = value as? TOMLArray else { return [] }
        var result: [String] = []
        for i in 0..<array.count {
            if let str = array[i] as? String {
                result.append(str)
            }
        }
        return result
    }
}
