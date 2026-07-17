import AeroKitCore
import Foundation

/// Pure workspace-ring arithmetic for the swipe switcher: given the focused
/// workspace and the monitor's workspace list, decide where one swipe lands.
public enum SwipeNavigation {
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

    /// Ring ordered by the user's priority list: listed names come first in
    /// that order, everything else follows in natural order. An empty
    /// priority keeps the order AeroSpace reported.
    public static func ring(current: String, workspaces: [String], priority: [String]) -> [String] {
        guard !priority.isEmpty else {
            return ring(current: current, workspaces: workspaces)
        }
        var ring = workspaces
        if !ring.contains(current) {
            ring.append(current)
        }
        return WorkspaceOrdering.sorted(ring, priority: priority)
    }

    /// `workspaces` may omit `current` (skipping empty workspaces does when
    /// the focused one is empty); it is inserted in natural sort order so
    /// the ring stays stable while the user passes through.
    public static func ring(current: String, workspaces: [String]) -> [String] {
        var ring = workspaces
        if !ring.contains(current) {
            // Insert at the natural-order position without reordering the
            // existing entries, so the ring AeroSpace reported stays stable
            // while the user passes through.
            let index = ring.firstIndex { current.localizedStandardCompare($0) == .orderedAscending }
            ring.insert(current, at: index ?? ring.count)
        }
        return ring
    }

    /// A multi-workspace move: one long swipe can land several entries away.
    /// Without wrap-around the move clamps at the ring's ends.
    public static func plan(
        current: String,
        workspaces: [String],
        offset: Int,
        wrapAround: Bool
    ) -> Plan? {
        guard !current.isEmpty else {
            return nil
        }
        let ring = ring(current: current, workspaces: workspaces)
        guard let index = ring.firstIndex(of: current) else {
            return nil
        }

        var newIndex = index + offset
        if wrapAround {
            newIndex = ((newIndex % ring.count) + ring.count) % ring.count
        } else {
            newIndex = max(0, min(ring.count - 1, newIndex))
        }
        return Plan(workspaces: ring, target: ring[newIndex])
    }
}
