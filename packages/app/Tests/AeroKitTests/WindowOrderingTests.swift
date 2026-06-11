import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

final class WindowOrderingTests: XCTestCase {
    private func window(_ id: CGWindowID) -> ExposeWindow {
        ExposeWindow(id: id, bundleIdentifier: "test", appName: "App \(id)", title: "")
    }

    func testOrdersTiledLayoutInReadingOrder() {
        let windows = [window(3), window(1), window(4), window(2)]
        let bounds: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 800, height: 500),
            2: CGRect(x: 810, y: 0, width: 800, height: 500),
            3: CGRect(x: 0, y: 510, width: 800, height: 500),
            4: CGRect(x: 810, y: 510, width: 800, height: 500)
        ]

        let ordered = WindowOrdering.spatial(windows, bounds: bounds)

        XCTAssertEqual(ordered.map(\.id), [1, 2, 3, 4])
    }

    func testSlightVerticalOffsetsStayInTheSameRow() {
        let windows = [window(2), window(1)]
        let bounds: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 800, height: 500),
            2: CGRect(x: 810, y: 60, width: 800, height: 500)
        ]

        let ordered = WindowOrdering.spatial(windows, bounds: bounds)

        XCTAssertEqual(ordered.map(\.id), [1, 2])
    }

    func testWindowsWithoutBoundsComeLastInOriginalOrder() {
        let windows = [window(9), window(1), window(8)]
        let bounds: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 800, height: 500)
        ]

        let ordered = WindowOrdering.spatial(windows, bounds: bounds)

        XCTAssertEqual(ordered.map(\.id), [1, 9, 8])
    }
}
