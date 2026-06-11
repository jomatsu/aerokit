import XCTest
@testable import ExposeFeature

final class TileGeometryTests: XCTestCase {
    // MARK: - displaySize

    func testLargeWindowIsScaledDownToFit() {
        let size = TileGeometry.displaySize(
            windowPoints: CGSize(width: 1600, height: 1000),
            available: CGSize(width: 400, height: 400)
        )

        XCTAssertEqual(size.width, 400, accuracy: 0.001)
        XCTAssertEqual(size.height, 250, accuracy: 0.001)
    }

    func testSmallWindowIsNeverShownLargerThanLife() {
        let size = TileGeometry.displaySize(
            windowPoints: CGSize(width: 300, height: 200),
            available: CGSize(width: 400, height: 400)
        )

        XCTAssertEqual(size, CGSize(width: 300, height: 200))
    }

    func testUnknownWindowSizeFillsTheCell() {
        let available = CGSize(width: 400, height: 300)

        XCTAssertEqual(TileGeometry.displaySize(windowPoints: nil, available: available), available)
        XCTAssertEqual(TileGeometry.displaySize(windowPoints: .zero, available: available), available)
    }

    // MARK: - cellSize

    func testCellSizeAccountsForMarginsAndGaps() {
        let cell = TileGeometry.cellSize(
            container: CGSize(width: 1000, height: 800),
            grid: GridDimensions(columns: 3, rows: 2),
            gap: 10,
            margin: 50
        )

        XCTAssertEqual(cell.width, (1000 - 100 - 20) / 3, accuracy: 0.001)
        XCTAssertEqual(cell.height, (800 - 100 - 10) / 2, accuracy: 0.001)
    }

    func testCellSizeNeverCollapsesToZero() {
        let cell = TileGeometry.cellSize(
            container: CGSize(width: 10, height: 10),
            grid: GridDimensions(columns: 5, rows: 5),
            gap: 10,
            margin: 50
        )

        XCTAssertGreaterThanOrEqual(cell.width, 1)
        XCTAssertGreaterThanOrEqual(cell.height, 1)
    }
}
