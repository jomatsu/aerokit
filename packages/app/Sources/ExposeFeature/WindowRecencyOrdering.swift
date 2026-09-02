import AeroKitCore
import CoreGraphics

/// Pure merge of the system's stacking order with AeroSpace's workspace
/// window set: the stacking order is the recency proxy a hold-to-cycle
/// switcher cycles through, but raw CGWindowList over-includes — AeroSpace
/// parks every other workspace's windows off-screen on the same macOS
/// Space, and those must not appear in the strip.
public enum WindowRecencyOrdering {
    /// - Parameters:
    ///   - windows: the focused workspace's windows, in AeroSpace's order.
    ///   - stacking: all on-screen window ids, front to back.
    ///   - focusedID: the focused window, rotated to index 0 — floating and
    ///     panel windows can outrank it in stacking order, and a ⌘Tab-style
    ///     strip treats index 0 as "current", index 1 as "previous".
    /// - Returns: the workspace's windows ordered most-recently-used first;
    ///     windows missing from the stacking list (minimized, off-list)
    ///     keep AeroSpace's order at the back.
    public static func ordered(
        windows: [ExposeWindow],
        stacking: [CGWindowID],
        focusedID: CGWindowID?
    ) -> [ExposeWindow] {
        let byID = Dictionary(windows.map { ($0.id, $0) }) { first, _ in first }
        var ordered: [ExposeWindow] = []
        var seen = Set<CGWindowID>()
        for id in stacking {
            guard !seen.contains(id), let window = byID[id] else {
                continue
            }
            seen.insert(id)
            ordered.append(window)
        }
        let listed = Set(ordered.map(\.id))
        ordered += windows.filter { !listed.contains($0.id) }
        if let focusedID, let index = ordered.firstIndex(where: { $0.id == focusedID }), index > 0 {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return ordered
    }
}
