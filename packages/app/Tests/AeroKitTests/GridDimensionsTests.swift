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
}
