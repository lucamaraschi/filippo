import AppKit
import CoreGraphics

/// Represents a discovered menu bar item.
struct DiscoveredMenuItem {
    let windowID: UInt32
    let ownerName: String
    let ownerPID: pid_t
    let frame: CGRect
    let title: String
}

/// Discovers menu bar items using CGWindowListCopyWindowInfo.
class MenuBarItemDiscovery {

    /// The menu bar window level constant.
    private static let menuBarLevel: Int32 = 25 // kCGStatusWindowLevel

    /// Discover all current menu bar items by querying the window server.
    func discoverItems() -> [DiscoveredMenuItem] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var items: [DiscoveredMenuItem] = []

        for info in windowInfoList {
            guard let windowLevel = info[kCGWindowLayer as String] as? Int32,
                  windowLevel == Self.menuBarLevel,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }

            // Skip our own items
            if ownerPID == ProcessInfo.processInfo.processIdentifier {
                continue
            }

            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Menu bar items have very small height (typically the menu bar height ~24-37px)
            // and are positioned at y=0 (top of screen)
            guard frame.height <= 50 && frame.origin.y <= 5 else {
                continue
            }

            // Use owner name as the item identifier
            // Some owners have multiple items, but for config purposes the owner name works
            let title = info[kCGWindowName as String] as? String ?? ownerName

            items.append(DiscoveredMenuItem(
                windowID: windowID,
                ownerName: ownerName,
                ownerPID: ownerPID,
                frame: frame,
                title: title.isEmpty ? ownerName : title
            ))
        }

        // Sort by x position (left to right)
        items.sort { $0.frame.origin.x < $1.frame.origin.x }

        // Deduplicate by owner name (keep first occurrence)
        var seen = Set<String>()
        var unique: [DiscoveredMenuItem] = []
        for item in items {
            let key = item.ownerName
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(item)
            }
        }

        return unique
    }

    /// Get a display name for the menu bar item.
    static func displayName(for item: DiscoveredMenuItem) -> String {
        // Clean up common system process names
        let nameMap: [String: String] = [
            "SystemUIServer": "SystemUIServer",
            "ControlCenter": "Control Center",
            "TextInputMenuAgent": "Input Sources",
            "Spotlight": "Spotlight",
        ]

        return nameMap[item.ownerName] ?? item.ownerName
    }
}
