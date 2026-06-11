import AeroKitCore

/// Selection state for one switcher presentation: the highlighted workspace
/// and whether the user has navigated since the overlay opened.
/// Release-to-commit only fires after navigation, so the flag lives next to
/// the index it guards.
struct SwitcherSelection {
    private(set) var index = 0
    private(set) var hasUserNavigated = false

    /// Resets for a fresh presentation, anchored on the focused workspace.
    mutating func begin(in workspaces: [Workspace]) {
        index = Self.focusedIndex(in: workspaces)
        hasUserNavigated = false
    }

    /// Returns whether the highlighted index actually changed, so callers can
    /// skip redundant overlay updates on no-op moves (empty list, grid edge).
    @discardableResult
    mutating func move(_ move: SelectionMove, count: Int, columns: Int) -> Bool {
        guard count > 0 else {
            return false
        }
        hasUserNavigated = true
        let previous = index
        switch move {
        case .left:
            index = max(0, index - 1)
        case .right:
            index = min(count - 1, index + 1)
        case .up:
            index = max(0, index - columns)
        case .down:
            index = min(count - 1, index + columns)
        case .next:
            index = (index + 1) % count
        case .previous:
            index = (index - 1 + count) % count
        }
        return index != previous
    }

    /// Direct pick (hover); counts as navigation like any other move.
    /// The caller validates that `newIndex` is in bounds.
    mutating func select(_ newIndex: Int) {
        index = newIndex
        hasUserNavigated = true
    }

    /// Re-anchors after the workspace list refreshes: snaps to the focused
    /// workspace until the user navigates, then follows the selection by name.
    mutating func reconcile(previousName: String?, workspaces: [Workspace], overlayVisible: Bool) {
        if !overlayVisible || !hasUserNavigated {
            index = Self.focusedIndex(in: workspaces)
        } else if let previousName,
                  let found = workspaces.firstIndex(where: { $0.name == previousName }) {
            index = found
        } else if index >= workspaces.count {
            index = max(0, workspaces.count - 1)
        }
    }

    private static func focusedIndex(in workspaces: [Workspace]) -> Int {
        workspaces.firstIndex(where: \.isFocused) ?? 0
    }
}
