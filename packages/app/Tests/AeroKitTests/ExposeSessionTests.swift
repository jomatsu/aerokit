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

    /// Windows interleaved across two apps: A, B, A, B (ids 1...4).
    private func makeInterleavedSession(groupByApp: Bool = false) -> ExposeSession {
        let windows = (1 ... 4).map {
            ExposeWindow(
                id: CGWindowID($0),
                bundleIdentifier: $0.isMultiple(of: 2) ? "app.b" : "app.a",
                appName: $0.isMultiple(of: 2) ? "App B" : "App A",
                title: ""
            )
        }
        return ExposeSession(windows: windows, containerAspect: 1.6, groupByApp: groupByApp)
    }

    func testGroupingClustersTilesByAppInFirstAppearanceOrder() {
        let session = makeInterleavedSession()

        session.setGroupedByApp(true)

        XCTAssertEqual(session.tiles.map(\.id), [1, 3, 2, 4])
        XCTAssertEqual(session.sections?.map(\.appName), ["App A", "App B"])
        XCTAssertEqual(session.sections?.map(\.tileRange), [0 ..< 2, 2 ..< 4])
    }

    func testGroupingOffRestoresTheDefaultOrder() {
        let session = makeInterleavedSession(groupByApp: true)
        XCTAssertEqual(session.tiles.map(\.id), [1, 3, 2, 4])

        session.setGroupedByApp(false)

        XCTAssertEqual(session.tiles.map(\.id), [1, 2, 3, 4])
        XCTAssertNil(session.sections)
    }

    func testSelectionFollowsTheWindowAcrossGroupingToggles() {
        let session = makeInterleavedSession()
        session.select(1) // window id 2

        session.toggleGrouping()
        XCTAssertEqual(session.tiles[session.selectedIndex].id, 2)

        session.toggleGrouping()
        XCTAssertEqual(session.selectedIndex, 1)
    }

    func testGroupedVerticalMovesHonorSectionRows() {
        // Groups of 3 and 1 form a 3-column grid: rows [0,1,2] and [3].
        let windows = (1 ... 4).map {
            ExposeWindow(
                id: CGWindowID($0),
                bundleIdentifier: $0 <= 3 ? "app.a" : "app.b",
                appName: $0 <= 3 ? "App A" : "App B",
                title: ""
            )
        }
        let session = ExposeSession(windows: windows, containerAspect: 1.6, groupByApp: true)
        XCTAssertEqual(session.grid, GridDimensions(columns: 3, rows: 2))

        session.select(2)
        session.move(.down)
        XCTAssertEqual(session.selectedIndex, 3, "Down clamps to the shorter section row")

        session.move(.up)
        XCTAssertEqual(session.selectedIndex, 0, "Up returns to the column the row actually has")
    }

    // MARK: - removeTile

    func testRemoveSelectedTileSelectsItsSuccessor() {
        let session = makeSession(count: 4)
        session.select(1)

        session.removeTile(windowID: 2)

        XCTAssertEqual(session.tiles.map(\.id), [1, 3, 4])
        XCTAssertEqual(session.tiles[session.selectedIndex].id, 3)
    }

    func testRemoveLastSelectedTileClampsToNewEnd() {
        let session = makeSession(count: 3)
        session.select(2)

        session.removeTile(windowID: 3)

        XCTAssertEqual(session.tiles[session.selectedIndex].id, 2)
    }

    func testRemoveBeforeSelectionKeepsTheSameWindowSelected() {
        let session = makeSession(count: 4)
        session.select(2) // window id 3

        session.removeTile(windowID: 1)

        XCTAssertEqual(session.tiles[session.selectedIndex].id, 3)
    }

    func testRemoveAfterSelectionKeepsTheSameWindowSelected() {
        let session = makeSession(count: 4)
        session.select(1) // window id 2

        session.removeTile(windowID: 4)

        XCTAssertEqual(session.tiles[session.selectedIndex].id, 2)
    }

    func testRemoveUnknownWindowIsANoOp() {
        let session = makeSession(count: 2)

        session.removeTile(windowID: 99)

        XCTAssertEqual(session.tiles.map(\.id), [1, 2])
    }

    func testRemoveRecomputesTheGrid() {
        // 5 windows on a 1.6 container form a 3x2 grid; 4 fit on 2x2.
        let session = makeSession(count: 5)
        XCTAssertEqual(session.grid, GridDimensions(columns: 3, rows: 2))

        session.removeTile(windowID: 5)

        XCTAssertEqual(session.grid, GridDimensions.bestFit(count: 4, containerAspect: 1.6))
    }

    func testRemovingAnAppsLastWindowDropsItsSection() {
        let session = makeInterleavedSession(groupByApp: true)
        // Grouped order: A(1, 3), B(2, 4).

        session.removeTile(windowID: 2)
        XCTAssertEqual(session.sections?.map(\.appName), ["App A", "App B"])

        session.removeTile(windowID: 4)

        XCTAssertEqual(session.sections?.map(\.appName), ["App A"])
        XCTAssertEqual(session.tiles.map(\.id), [1, 3])
    }

    func testUngroupingAfterRemovalDoesNotResurrectTheWindow() {
        let session = makeInterleavedSession(groupByApp: true)

        session.removeTile(windowID: 3)
        session.setGroupedByApp(false)

        XCTAssertEqual(session.tiles.map(\.id), [1, 2, 4])
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
