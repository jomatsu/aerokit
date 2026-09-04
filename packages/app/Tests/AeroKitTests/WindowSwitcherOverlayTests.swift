import AppKit
import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

@MainActor
final class WindowSwitcherOverlayTests: XCTestCase {
    private func window(_ id: CGWindowID, _ title: String) -> ExposeWindow {
        ExposeWindow(id: id, bundleIdentifier: "com.example", appName: title, title: title)
    }

    private func session() -> WindowCycleSession {
        WindowCycleSession(windows: [window(1, "A"), window(2, "B")], icons: [:])
    }

    private func requireScreen() throws -> NSScreen {
        try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first, "No screen available")
    }

    func testHideWithoutShowDoesNotCrashOrCancel() {
        let overlay = WindowSwitcherOverlay()
        var cancelled = false
        overlay.onCancel = { cancelled = true }
        overlay.hide()
        overlay.hide()
        XCTAssertFalse(overlay.isVisible)
        XCTAssertFalse(cancelled)
    }

    func testShowThenHideDoesNotFireCancel() throws {
        let overlay = WindowSwitcherOverlay()
        var cancelled = false
        overlay.onCancel = { cancelled = true }
        try overlay.show(session: session(), cardWidth: 80, on: requireScreen())
        XCTAssertTrue(overlay.isVisible)
        overlay.hide()
        XCTAssertFalse(overlay.isVisible)
        XCTAssertFalse(cancelled)
    }

    func testQuickShowHideShowKeepsTheSecondPresentation() throws {
        let overlay = WindowSwitcherOverlay()
        var cancelled = false
        overlay.onCancel = { cancelled = true }
        let screen = try requireScreen()
        overlay.show(session: session(), cardWidth: 80, on: screen)
        overlay.hide()
        overlay.show(session: session(), cardWidth: 80, on: screen)
        XCTAssertTrue(overlay.isVisible)
        XCTAssertFalse(cancelled)
        overlay.hide()
        XCTAssertFalse(overlay.isVisible)
        XCTAssertFalse(cancelled)
    }

    func testHideThenNextTickDoesNotFireCancel() async throws {
        let overlay = WindowSwitcherOverlay()
        var cancelled = false
        overlay.onCancel = { cancelled = true }
        try overlay.show(session: session(), cardWidth: 80, on: requireScreen())
        overlay.hide()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(overlay.isVisible)
        XCTAssertFalse(cancelled)
    }
}
