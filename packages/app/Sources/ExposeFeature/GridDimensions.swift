import CoreGraphics
import Foundation

/// A columns-by-rows grid sized to hold a number of equally sized tiles.
public struct GridDimensions: Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    /// Picks the grid whose cells stay closest to a typical window's aspect
    /// ratio while wasting few cells, with a slight preference for wide
    /// grids over tall ones (landscape rows read better than columns).
    public static func bestFit(
        count: Int,
        containerAspect: CGFloat,
        idealCellAspect: CGFloat = 1.6
    ) -> GridDimensions {
        guard count > 1 else {
            return GridDimensions(columns: 1, rows: 1)
        }

        var best = GridDimensions(columns: count, rows: 1)
        var bestScore = CGFloat.infinity

        for rows in 1 ... count {
            let columns = Int((Double(count) / Double(rows)).rounded(.up))
            let emptyCells = columns * rows - count
            let cellAspect = containerAspect * CGFloat(rows) / CGFloat(columns)
            let shapePenalty = abs(log(cellAspect / idealCellAspect))
            let emptyPenalty = CGFloat(emptyCells) * 0.35
            let tallGridPenalty: CGFloat = columns >= rows ? 0 : 0.1
            let score = shapePenalty + emptyPenalty + tallGridPenalty

            if score < bestScore {
                best = GridDimensions(columns: columns, rows: rows)
                bestScore = score
            }
        }

        return best
    }
}
