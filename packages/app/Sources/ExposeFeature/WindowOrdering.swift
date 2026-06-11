import AeroKitCore
import CoreGraphics

/// Orders windows the way they sit on screen — rows top to bottom, left to
/// right within a row — so the overview grid preserves spatial intuition.
public enum WindowOrdering {
    public static func spatial(_ windows: [ExposeWindow], bounds: [CGWindowID: CGRect]) -> [ExposeWindow] {
        var placed: [(window: ExposeWindow, frame: CGRect)] = []
        var unplaced: [ExposeWindow] = []
        for window in windows {
            if let frame = bounds[window.id] {
                placed.append((window, frame))
            } else {
                unplaced.append(window)
            }
        }

        let ordered = rows(of: placed).flatMap { row in
            row.sorted { $0.frame.midX < $1.frame.midX }.map(\.window)
        }
        return ordered + unplaced
    }

    /// Bands windows into visual rows: a window joins the current row while
    /// its vertical center still falls inside the row's first window.
    /// Anchoring on the first window keeps the banding deterministic, unlike
    /// a pairwise-overlap sort which is not a strict weak ordering.
    private static func rows(
        of placed: [(window: ExposeWindow, frame: CGRect)]
    ) -> [[(window: ExposeWindow, frame: CGRect)]] {
        var rows: [[(window: ExposeWindow, frame: CGRect)]] = []
        for item in placed.sorted(by: { $0.frame.midY < $1.frame.midY }) {
            if let last = rows.indices.last, let anchor = rows[last].first, item.frame.midY < anchor.frame.maxY {
                rows[last].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows
    }
}
