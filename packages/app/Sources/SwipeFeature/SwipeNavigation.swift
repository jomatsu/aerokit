import Foundation

/// Pure workspace-ring arithmetic for the swipe switcher: given the focused
/// workspace and the monitor's workspace list, decide where one swipe lands.
public enum SwipeNavigation {
    public enum Step: Sendable {
        case next
        case previous
    }

    /// The resolved ring and the workspace one swipe lands on. `target`
    /// equals `current` when the swipe hits a non-wrapping edge.
    public struct Plan: Equatable, Sendable {
        public var workspaces: [String]
        public var target: String

        public init(workspaces: [String], target: String) {
            self.workspaces = workspaces
            self.target = target
        }
    }

    /// `workspaces` may omit `current` (skipping empty workspaces does when
    /// the focused one is empty); it is inserted in natural sort order so
    /// the ring stays stable while the user passes through.
    public static func plan(
        current: String,
        workspaces: [String],
        step: Step,
        wrapAround: Bool
    ) -> Plan? {
        guard !current.isEmpty else {
            return nil
        }
        var ring = workspaces
        if !ring.contains(current) {
            // Insert at the natural-order position without reordering the
            // existing entries, so the ring AeroSpace reported stays stable
            // while the user passes through.
            let index = ring.firstIndex { current.localizedStandardCompare($0) == .orderedAscending }
            ring.insert(current, at: index ?? ring.count)
        }
        guard let index = ring.firstIndex(of: current) else {
            return nil
        }

        var newIndex = step == .next ? index + 1 : index - 1
        if newIndex >= ring.count {
            newIndex = wrapAround ? 0 : ring.count - 1
        }
        if newIndex < 0 {
            newIndex = wrapAround ? ring.count - 1 : 0
        }
        return Plan(workspaces: ring, target: ring[newIndex])
    }
}
