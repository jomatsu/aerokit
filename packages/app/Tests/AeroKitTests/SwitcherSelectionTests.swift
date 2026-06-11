import XCTest
@testable import AeroKitCore
@testable import SwitcherFeature

final class SwitcherSelectionTests: XCTestCase {
    private func workspaces(_ count: Int, focused: Int? = nil) -> [Workspace] {
        (0 ..< count).map { index in
            Workspace(name: "W\(index)", apps: [], isFocused: index == focused, isEmpty: false)
        }
    }

    func testBeginAnchorsOnFocusedWorkspace() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(4, focused: 2))
        XCTAssertEqual(selection.index, 2)
        XCTAssertFalse(selection.hasUserNavigated)
    }

    func testBeginFallsBackToFirstWithoutFocus() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(3))
        XCTAssertEqual(selection.index, 0)
    }

    func testMoveNextWrapsAndMarksNavigation() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(3, focused: 2))
        selection.move(.next, count: 3, columns: 4)
        XCTAssertEqual(selection.index, 0)
        XCTAssertTrue(selection.hasUserNavigated)
    }

    func testMovePreviousWraps() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(3, focused: 0))
        selection.move(.previous, count: 3, columns: 4)
        XCTAssertEqual(selection.index, 2)
    }

    func testArrowMovesClampAtEdges() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(5, focused: 0))
        selection.move(.left, count: 5, columns: 2)
        XCTAssertEqual(selection.index, 0)
        selection.move(.down, count: 5, columns: 2)
        XCTAssertEqual(selection.index, 2)
        selection.move(.down, count: 5, columns: 2)
        XCTAssertEqual(selection.index, 4)
        selection.move(.right, count: 5, columns: 2)
        XCTAssertEqual(selection.index, 4)
    }

    func testMoveReportsWhetherIndexChanged() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(3, focused: 0))
        XCTAssertFalse(selection.move(.left, count: 3, columns: 2))
        XCTAssertTrue(selection.hasUserNavigated)
        XCTAssertTrue(selection.move(.right, count: 3, columns: 2))
    }

    func testReconcileSnapsToFocusWhenOverlayHidden() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(3, focused: 0))
        selection.move(.next, count: 3, columns: 4)
        selection.reconcile(
            previousName: "W1",
            workspaces: workspaces(3, focused: 2),
            overlayVisible: false
        )
        XCTAssertEqual(selection.index, 2)
    }

    func testMoveIgnoredWhileEmpty() {
        var selection = SwitcherSelection()
        selection.begin(in: [])
        selection.move(.next, count: 0, columns: 4)
        XCTAssertEqual(selection.index, 0)
        XCTAssertFalse(selection.hasUserNavigated)
    }

    func testReconcileSnapsToFocusUntilUserNavigates() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(3, focused: 0))
        selection.reconcile(
            previousName: "W0",
            workspaces: workspaces(3, focused: 1),
            overlayVisible: true
        )
        XCTAssertEqual(selection.index, 1)
    }

    func testReconcileFollowsSelectionByNameWhenUserDriven() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(4, focused: 0))
        selection.move(.next, count: 4, columns: 4)

        // W1 shifts to index 2 after a refresh inserts a workspace before it.
        let fresh = [
            Workspace(name: "W9", apps: [], isFocused: false, isEmpty: false),
            Workspace(name: "W0", apps: [], isFocused: true, isEmpty: false),
            Workspace(name: "W1", apps: [], isFocused: false, isEmpty: false)
        ]
        selection.reconcile(previousName: "W1", workspaces: fresh, overlayVisible: true)
        XCTAssertEqual(selection.index, 2)
    }

    func testReconcileClampsWhenSelectionDisappears() {
        var selection = SwitcherSelection()
        selection.begin(in: workspaces(5, focused: 0))
        selection.select(4)
        selection.reconcile(
            previousName: "W4",
            workspaces: workspaces(2, focused: 0),
            overlayVisible: true
        )
        XCTAssertEqual(selection.index, 1)
    }
}
