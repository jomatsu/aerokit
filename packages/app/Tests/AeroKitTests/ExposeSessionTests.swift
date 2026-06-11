import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

@MainActor
final class ExposeSessionTests: XCTestCase {
    private func makeSession(count: Int, focusedWindowID: CGWindowID? = nil) -> ExposeSession {
        let windows = (1 ... count).map {
            ExposeWindow(id: CGWindowID($0), bundleIdentifier: "test", appName: "App \($0)", title: "")
        }
        return ExposeSession(windows: windows, containerAspect: 1.6, focusedWindowID: focusedWindowID)
    }

    func testSelectionStartsOnFocusedWindow() {
        XCTAssertEqual(makeSession(count: 4, focusedWindowID: 3).selectedIndex, 2)
    }

    func testSelectionFallsBackToFirstTile() {
        XCTAssertEqual(makeSession(count: 4, focusedWindowID: 99).selectedIndex, 0)
    }

    func testNextAndPreviousWrapAround() {
        let session = makeSession(count: 3)

        session.move(.previous)
        XCTAssertEqual(session.selectedIndex, 2)

        session.move(.next)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testVerticalMovesStopAtGridEdges() {
        // 5 windows on a 1.6 container form a 3x2 grid.
        let session = makeSession(count: 5)
        XCTAssertEqual(session.grid, GridDimensions(columns: 3, rows: 2))

        session.move(.up)
        XCTAssertEqual(session.selectedIndex, 0, "Up from the first row is a no-op")

        session.move(.down)
        XCTAssertEqual(session.selectedIndex, 3)

        session.move(.down)
        XCTAssertEqual(session.selectedIndex, 3, "Down from the last row is a no-op")
    }

    func testSelectIgnoresOutOfRangeIndices() {
        let session = makeSession(count: 2)

        session.select(5)
        XCTAssertEqual(session.selectedIndex, 0)

        session.select(1)
        XCTAssertEqual(session.selectedIndex, 1)
    }

    func testSetImageTargetsTheMatchingTile() {
        let session = makeSession(count: 2)
        guard let context = WindowImageCapturer.makeContext(width: 4, height: 4),
              let image = context.makeImage()
        else {
            return XCTFail("Could not create a test image")
        }

        session.setImage(image, forWindow: 2)

        XCTAssertNil(session.tiles[0].image)
        XCTAssertNotNil(session.tiles[1].image)
    }
}

@MainActor
final class ExposeDigitInterceptorTests: XCTestCase {
    func testNumberRowKeyCodesMapToDigits() {
        let expected: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        for (keyCode, digit) in expected {
            XCTAssertEqual(ExposeDigitInterceptor.digit(for: keyCode), digit)
        }
    }

    func testNonDigitKeyCodesMapToNil() {
        XCTAssertNil(ExposeDigitInterceptor.digit(for: 29), "0 is not a selection key")
        XCTAssertNil(ExposeDigitInterceptor.digit(for: 46), "M")
        XCTAssertNil(ExposeDigitInterceptor.digit(for: 53), "Escape")
    }
}
