import XCTest
@testable import SwipeFeature

final class SwipeNavigationTests: XCTestCase {
    private let workspaces = ["1", "2", "3"]

    func testNextMovesForward() {
        let plan = SwipeNavigation.plan(current: "1", workspaces: workspaces, step: .next, wrapAround: true)
        XCTAssertEqual(plan?.target, "2")
        XCTAssertEqual(plan?.workspaces, workspaces)
    }

    func testPreviousMovesBackward() {
        let plan = SwipeNavigation.plan(current: "3", workspaces: workspaces, step: .previous, wrapAround: true)
        XCTAssertEqual(plan?.target, "2")
    }

    func testNextWrapsPastTheEnd() {
        let plan = SwipeNavigation.plan(current: "3", workspaces: workspaces, step: .next, wrapAround: true)
        XCTAssertEqual(plan?.target, "1")
    }

    func testPreviousWrapsPastTheStart() {
        let plan = SwipeNavigation.plan(current: "1", workspaces: workspaces, step: .previous, wrapAround: true)
        XCTAssertEqual(plan?.target, "3")
    }

    func testEdgesStickWithoutWrapAround() {
        XCTAssertEqual(
            SwipeNavigation.plan(current: "3", workspaces: workspaces, step: .next, wrapAround: false)?.target,
            "3"
        )
        XCTAssertEqual(
            SwipeNavigation.plan(current: "1", workspaces: workspaces, step: .previous, wrapAround: false)?.target,
            "1"
        )
    }

    func testMissingCurrentIsInsertedInNaturalOrder() {
        // Skip-empty dropped the focused workspace "2" from the listing.
        let plan = SwipeNavigation.plan(current: "2", workspaces: ["1", "3", "10"], step: .next, wrapAround: true)
        XCTAssertEqual(plan?.workspaces, ["1", "2", "3", "10"])
        XCTAssertEqual(plan?.target, "3")
    }

    func testMissingCurrentInsertionPreservesListingOrder() {
        // AeroSpace's ordering is authoritative even when it disagrees with
        // natural sort; inserting the focused workspace must not reorder it.
        let plan = SwipeNavigation.plan(current: "3", workspaces: ["1", "10", "2"], step: .next, wrapAround: true)
        XCTAssertEqual(plan?.workspaces, ["1", "3", "10", "2"])
        XCTAssertEqual(plan?.target, "10")
    }

    func testLoneWorkspaceStaysPut() {
        let plan = SwipeNavigation.plan(current: "1", workspaces: [], step: .next, wrapAround: true)
        XCTAssertEqual(plan?.workspaces, ["1"])
        XCTAssertEqual(plan?.target, "1")
    }

    func testEmptyCurrentProducesNoPlan() {
        XCTAssertNil(SwipeNavigation.plan(current: "", workspaces: workspaces, step: .next, wrapAround: true))
    }
}
