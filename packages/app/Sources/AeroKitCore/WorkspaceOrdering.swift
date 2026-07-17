import Foundation

/// Shared sort rule for workspace names: names on the priority list come
/// first in that order, everything else follows in natural order. Both the
/// switcher grid and the swipe ring sort with this.
public enum WorkspaceOrdering {
    public static func comparator(priority: [String]) -> @Sendable (String, String) -> Bool {
        let position = Dictionary(priority.enumerated().map { ($1, $0) }) { first, _ in first }
        return { lhs, rhs in
            switch (position[lhs], position[rhs]) {
            case let (.some(left), .some(right)):
                left < right
            case (.some, .none):
                true
            case (.none, .some):
                false
            case (.none, .none):
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }

    public static func sorted(_ names: [String], priority: [String]) -> [String] {
        names.sorted(by: comparator(priority: priority))
    }
}
