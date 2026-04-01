import AppKit
import ApplicationServices
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
    private struct AccessibilityMenuItemInfo {
        let frame: CGRect
        let label: String
    }

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
        var accessibilityItemsByPID: [pid_t: [AccessibilityMenuItemInfo]] = [:]

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

            let title = info[kCGWindowName as String] as? String ?? ownerName
            let normalizedTitle = title.isEmpty ? ownerName : title
            let resolvedTitle: String

            if normalizedTitle == ownerName {
                let accessibilityItems = accessibilityItemsByPID[ownerPID] ?? {
                    let discovered = accessibilityItemsForPID(ownerPID)
                    accessibilityItemsByPID[ownerPID] = discovered
                    return discovered
                }()

                resolvedTitle = bestAccessibilityLabel(
                    for: frame,
                    fallback: normalizedTitle,
                    accessibilityItems: accessibilityItems
                )
            } else {
                resolvedTitle = normalizedTitle
            }

            items.append(DiscoveredMenuItem(
                windowID: windowID,
                ownerName: ownerName,
                ownerPID: ownerPID,
                frame: frame,
                title: resolvedTitle
            ))
        }

        // Sort by x position (left to right)
        items.sort { $0.frame.origin.x < $1.frame.origin.x }

        // Deduplicate by display name so one process can still expose multiple
        // distinct menu bar items when the window server gives them unique titles.
        var seen = Set<String>()
        var unique: [DiscoveredMenuItem] = []
        for item in items {
            let key = Self.displayName(for: item)
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(item)
            }
        }

        return unique
    }

    private func accessibilityItemsForPID(_ pid: pid_t) -> [AccessibilityMenuItemInfo] {
        let app = AXUIElementCreateApplication(pid)

        guard let menuBarValue = copyAttributeValue(
            for: app,
            attribute: kAXMenuBarAttribute as String
        ) else {
            return []
        }
        let menuBar = menuBarValue as! AXUIElement

        return collectAccessibilityItems(from: menuBar, depth: 0)
    }

    private func collectAccessibilityItems(
        from element: AXUIElement,
        depth: Int
    ) -> [AccessibilityMenuItemInfo] {
        guard depth <= 2 else { return [] }

        var results: [AccessibilityMenuItemInfo] = []

        if let frame = accessibilityFrame(for: element),
           let label = accessibilityLabel(for: element),
           !label.isEmpty {
            results.append(AccessibilityMenuItemInfo(frame: frame, label: label))
        }

        guard let children = copyAttributeValue(
            for: element,
            attribute: kAXChildrenAttribute as String
        ) as? [AXUIElement] else {
            return results
        }

        for child in children {
            results.append(contentsOf: collectAccessibilityItems(from: child, depth: depth + 1))
        }

        return results
    }

    private func accessibilityLabel(for element: AXUIElement) -> String? {
        let keys = [
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
        ]

        for key in keys {
            if let value = copyAttributeValue(for: element, attribute: key) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }

    private func accessibilityFrame(for element: AXUIElement) -> CGRect? {
        guard
            let positionValue = copyAttributeValue(for: element, attribute: kAXPositionAttribute as String),
            let sizeValue = copyAttributeValue(for: element, attribute: kAXSizeAttribute as String)
        else {
            return nil
        }
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero

        guard
            AXValueGetType(positionAXValue) == .cgPoint,
            AXValueGetType(sizeAXValue) == .cgSize,
            AXValueGetValue(positionAXValue, .cgPoint, &position),
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func copyAttributeValue(
        for element: AXUIElement,
        attribute: String
    ) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private func bestAccessibilityLabel(
        for frame: CGRect,
        fallback: String,
        accessibilityItems: [AccessibilityMenuItemInfo]
    ) -> String {
        let overlapping = accessibilityItems
            .filter { $0.frame.intersects(frame.insetBy(dx: -8, dy: -8)) }
            .sorted { lhs, rhs in
                abs(lhs.frame.midX - frame.midX) < abs(rhs.frame.midX - frame.midX)
            }

        return overlapping.first?.label ?? fallback
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

        let baseName = nameMap[item.ownerName] ?? item.ownerName
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            return baseName
        }

        if title == item.ownerName || title == baseName {
            return baseName
        }

        return title
    }
}
