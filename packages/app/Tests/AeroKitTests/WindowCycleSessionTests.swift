import AeroKitCore
import XCTest
@testable import ExposeFeature

@MainActor
final class WindowCycleSessionTests: XCTestCase {
    private func window(_ id: CGWindowID, _ title: String) -> ExposeWindow {
        ExposeWindow(id: id, bundleIdentifier: "com.example", appName: title, title: title)
    }

    private let idA = CGWindowID(1)
    private let idB = CGWindowID(2)
    private let idC = CGWindowID(3)

    func testPreselectsSecondWindow() {
        let session = WindowCycleSession(
            windows: [window(idA, "A"), window(idB, "B"), window(idC, "C")],
            icons: [:]
        )
        XCTAssertEqual(session.selectedEntry?.id, idB)
    }

    func testSingleWindowStaysOnZero() {
        let session = WindowCycleSession(windows: [window(idA, "A")], icons: [:])
        XCTAssertEqual(session.selectedIndex, 0)
        // Move is a no-op with one entry: committing re-focuses the same window.
        session.move(.next)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testNextPreviousWrap() {
        let session = WindowCycleSession(
            windows: [window(idA, "A"), window(idB, "B"), window(idC, "C")],
            icons: [:]
        )
        session.move(.next)
        XCTAssertEqual(session.selectedEntry?.id, idC)
        session.move(.next)
        XCTAssertEqual(session.selectedEntry?.id, idA)
        session.move(.previous)
        XCTAssertEqual(session.selectedEntry?.id, idC)
    }

    func testSetImageIgnoresUnknownWindow() {
        let session = WindowCycleSession(windows: [window(idA, "A")], icons: [:])
        session.setImage(NSImage(), forWindow: CGWindowID(99))
        XCTAssertNil(session.entries[0].image)
    }
}
