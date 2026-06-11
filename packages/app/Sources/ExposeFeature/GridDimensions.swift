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
            let candidate = GridDimensions(columns: columns, rows: rows)
            let score = score(
                candidate, count: count, containerAspect: containerAspect, idealCellAspect: idealCellAspect
            )
            if score < bestScore {
                best = candidate
                bestScore = score
            }
        }

        return best
    }

    private static func score(
        _ grid: GridDimensions,
        count: Int,
        containerAspect: CGFloat,
        idealCellAspect: CGFloat,
        emptyCellWeight: CGFloat = 0.35
    ) -> CGFloat {
        let emptyCells = grid.columns * grid.rows - count
        let cellAspect = containerAspect * CGFloat(grid.rows) / CGFloat(grid.columns)
        let shapePenalty = abs(log(cellAspect / idealCellAspect))
        let emptyPenalty = CGFloat(emptyCells) * emptyCellWeight
        let tallGridPenalty: CGFloat = grid.columns >= grid.rows ? 0 : 0.1
        return shapePenalty + emptyPenalty + tallGridPenalty
    }
}

/// Cell grid plus group placement for the app-grouped overview: groups pack
/// left to right into rows of `grid.columns` cells, several groups sharing a
/// row when they fit; a group wider than a row gets its own block of rows.
public struct GroupedGridLayout: Equatable, Sendable {
    public var grid: GridDimensions
    /// Group indexes per shelf row, in display order.
    public var rows: [[Int]]
}

public extension GridDimensions {
    /// Searches the column counts for the packing whose cells stay closest
    /// to a window's aspect ratio. Ragged shelf rows are inherent to
    /// grouping, so empty cells are punished far more lightly than in the
    /// flat fit — weighting them like the flat fit drives many-app
    /// workspaces into tall, skinny grids of near-invisible tiles.
    static func bestGroupedFit(
        groupCounts: [Int],
        containerAspect: CGFloat,
        idealCellAspect: CGFloat = 1.6
    ) -> GroupedGridLayout {
        let count = groupCounts.reduce(0, +)
        var best = groupedCandidate(groupCounts: groupCounts, columns: 1)
        guard count > 1 else {
            return best
        }

        var bestScore = CGFloat.infinity
        for columns in 1 ... count {
            let candidate = groupedCandidate(groupCounts: groupCounts, columns: columns)
            let score = score(
                candidate.grid,
                count: count,
                containerAspect: containerAspect,
                idealCellAspect: idealCellAspect,
                emptyCellWeight: 0.05
            )
            if score < bestScore {
                best = candidate
                bestScore = score
            }
        }

        return best
    }

    private static func groupedCandidate(groupCounts: [Int], columns: Int) -> GroupedGridLayout {
        var rows: [[Int]] = []
        var tileRows = 0
        var remaining = 0
        for (index, count) in groupCounts.enumerated() {
            if count > columns {
                // Too wide to share: a block of full-width rows of its own.
                rows.append([index])
                tileRows += (count + columns - 1) / columns
                remaining = 0
            } else if count <= remaining {
                rows[rows.count - 1].append(index)
                remaining -= count
            } else {
                rows.append([index])
                tileRows += 1
                remaining = columns - count
            }
        }
        return GroupedGridLayout(
            grid: GridDimensions(columns: columns, rows: max(tileRows, 1)),
            rows: rows
        )
    }
}
