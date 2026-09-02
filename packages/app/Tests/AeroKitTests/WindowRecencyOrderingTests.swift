import AeroKitCore
import XCTest
@testable import ExposeFeature

final class WindowRecencyOrderingTests: XCTestCase {
    private func window(_ id: CGWindowID, _ title: String) -> ExposeWindow {
        ExposeWindow(id: id, bundleIdentifier: "com.example", appName: title, title: title)
    }

    private let idA = CGWindowID(1)
    private let idB = CGWindowID(2)
    private let idC = CGWindowID(3)

    func testStackingOrderFiltersToWorkspaceSet() {
        // b and d are on screen, but d belongs to another (parked) workspace.
        let windows = [window(idA, "A"), window(idB, "B")]
        let ordered = WindowRecencyOrdering.ordered(
            windows: windows,
            stacking: [CGWindowID(9), idB, idA],
            focusedID: nil
        )
        XCTAssertEqual(ordered.map(\.id), [idB, idA])
    }

    func testMissingFromStackingAppendedInAeroSpaceOrder() {
        let windows = [window(idA, "A"), window(idB, "B"), window(idC, "C")]
        let ordered = WindowRecencyOrdering.ordered(windows: windows, stacking: [idB], focusedID: nil)
        XCTAssertEqual(ordered.map(\.id), [idB, idA, idC])
    }

    func testFocusedWindowRotatedToFront() {
        let windows = [window(idA, "A"), window(idB, "B"), window(idC, "C")]
        let ordered = WindowRecencyOrdering.ordered(
            windows: windows,
            stacking: [idA, idB, idC],
            focusedID: idB
        )
        XCTAssertEqual(ordered.map(\.id), [idB, idA, idC])
    }

    func testFocusedAtFrontStaysPut() {
        let windows = [window(idA, "A"), window(idB, "B")]
        let ordered = WindowRecencyOrdering.ordered(windows: windows, stacking: [idA, idB], focusedID: idA)
        XCTAssertEqual(ordered.map(\.id), [idA, idB])
    }

    func testDuplicateStackingIDsIgnored() {
        let windows = [window(idA, "A"), window(idB, "B")]
        let ordered = WindowRecencyOrdering.ordered(windows: windows, stacking: [idB, idB, idA], focusedID: nil)
        XCTAssertEqual(ordered.map(\.id), [idB, idA])
    }
}
