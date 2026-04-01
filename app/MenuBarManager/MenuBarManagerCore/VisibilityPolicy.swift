public enum MenuBarVisibilityAction: Equatable {
    case none
    case hide
    case reveal
}

public enum MenuBarItemZone: Equatable {
    case visible
    case hidden
    case disabled
}

public enum MenuBarVisibilityPolicy {
    public static func shouldProcess(
        previousStatus: String?,
        previousVisibility: Bool?,
        currentStatus: String,
        currentVisibility: Bool,
        force: Bool
    ) -> Bool {
        if force {
            return true
        }

        return previousStatus != currentStatus || previousVisibility != currentVisibility
    }

    public static func action(
        status: String,
        isRevealed: Bool,
        isCurrentlyVisible: Bool
    ) -> MenuBarVisibilityAction {
        switch status {
        case "disabled":
            return isCurrentlyVisible ? .hide : .none
        case "hidden":
            if isRevealed { return .none }
            return isCurrentlyVisible ? .hide : .none
        case "visible":
            return .none
        default:
            return .none
        }
    }

    public static func desiredPlacement(
        status: String,
        isExpanded: Bool
    ) -> MenuBarItemZone {
        switch status {
        case "disabled":
            return .disabled
        case "hidden":
            return .hidden
        case "visible":
            return .visible
        default:
            return .hidden
        }
    }

    public static func shouldRetainMissingItem(
        status: String,
        processIsRunning: Bool
    ) -> Bool {
        guard processIsRunning else { return false }
        return status == "hidden" || status == "disabled"
    }
}
