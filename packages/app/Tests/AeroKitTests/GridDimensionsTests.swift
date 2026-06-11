import XCTest
@testable import ExposeFeature

final class GridDimensionsTests: XCTestCase {
    private let laptopAspect: CGFloat = 1.6

    func testZeroAndSingleWindowUseSingleCell() {
        XCTAssertEqual(
            GridDimensions.bestFit(count: 0, containerAspect: laptopAspect),
            GridDimensions(columns: 1, rows: 1)
        )
        XCTAssertEqual(
            GridDimensions.bestFit(count: 1, containerAspect: laptopAspect),
            GridDimensions(columns: 1, rows: 1)
        )
    }

    func testTwoWindowsSitSideBySide() {
        XCTAssertEqual(
            GridDimensions.bestFit(count: 2, containerAspect: laptopAspect),
            GridDimensions(columns: 2, rows: 1)
        )
    }

    func testFourWindowsFormASquareGrid() {
        XCTAssertEqual(
            GridDimensions.bestFit(count: 4, containerAspect: laptopAspect),
            GridDimensions(columns: 2, rows: 2)
        )
    }

    func testFiveWindowsPreferThreeColumns() {
        XCTAssertEqual(
            GridDimensions.bestFit(count: 5, containerAspect: laptopAspect),
            GridDimensions(columns: 3, rows: 2)
        )
    }

    func testTwelveWindowsFormFourByThree() {
        XCTAssertEqual(
            GridDimensions.bestFit(count: 12, containerAspect: laptopAspect),
            GridDimensions(columns: 4, rows: 3)
        )
    }

    func testGridAlwaysHoldsEveryWindow() {
        for count in 1 ... 30 {
            let grid = GridDimensions.bestFit(count: count, containerAspect: laptopAspect)
            XCTAssertGreaterThanOrEqual(grid.columns * grid.rows, count, "count \(count)")
            // No fully empty trailing row.
            XCTAssertLessThan(grid.columns * (grid.rows - 1), count, "count \(count)")
        }
    }

    func testUltrawideContainerStillPrefersBalancedGrids() {
        let grid = GridDimensions.bestFit(count: 4, containerAspect: 21.0 / 9.0)
        XCTAssertEqual(grid, GridDimensions(columns: 2, rows: 2))
    }

    func testGroupedFitGivesWideGroupItsOwnRows() {
        let layout = GridDimensions.bestGroupedFit(groupCounts: [3, 1], containerAspect: laptopAspect)
        XCTAssertEqual(layout.grid, GridDimensions(columns: 3, rows: 2))
        XCTAssertEqual(layout.rows, [[0], [1]])
    }

    func testGroupedFitPacksSmallGroupsIntoSharedRows() {
        let layout = GridDimensions.bestGroupedFit(groupCounts: [1, 1, 2], containerAspect: laptopAspect)
        XCTAssertEqual(layout.grid, GridDimensions(columns: 2, rows: 2))
        XCTAssertEqual(layout.rows, [[0, 1], [2]])
    }

    func testGroupedFitWithSingleWindowUsesSingleCell() {
        let layout = GridDimensions.bestGroupedFit(groupCounts: [1], containerAspect: laptopAspect)
        XCTAssertEqual(layout.grid, GridDimensions(columns: 1, rows: 1))
        XCTAssertEqual(layout.rows, [[0]])
        XCTAssertEqual(
            GridDimensions.bestGroupedFit(groupCounts: [], containerAspect: laptopAspect).rows,
            []
        )
    }

    func testGroupedRowsCoverEveryGroupInOrderWithinTheColumnBudget() {
        let groupings: [[Int]] = [[2, 2], [5, 1, 1], [1, 1, 1, 1, 1], [4, 3, 2], [1, 1, 6, 1, 1, 2, 13, 1, 1, 1]]
        for counts in groupings {
            let layout = GridDimensions.bestGroupedFit(groupCounts: counts, containerAspect: laptopAspect)
            XCTAssertEqual(layout.rows.flatMap(\.self), Array(counts.indices), "groups \(counts)")
            for row in layout.rows where row.count > 1 {
                let width = row.reduce(0) { $0 + counts[$1] }
                XCTAssertLessThanOrEqual(width, layout.grid.columns, "groups \(counts)")
            }
        }
    }

    /// Regression: many single-window apps must not degenerate into one
    /// window per row.
    func testManySmallGroupsStayCompact() {
        let counts = [1, 1, 6, 1, 1, 2, 13, 1, 1, 1]
        let layout = GridDimensions.bestGroupedFit(groupCounts: counts, containerAspect: laptopAspect)
        XCTAssertLessThanOrEqual(layout.grid.rows, 7, "28 windows should fit a handful of rows")
        XCTAssertGreaterThanOrEqual(layout.grid.columns, 5)
    }
}
