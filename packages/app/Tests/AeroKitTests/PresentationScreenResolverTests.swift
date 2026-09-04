import AppKit
import XCTest
@testable import ExposeFeature

final class PresentationScreenResolverTests: XCTestCase {
    private func requireScreens() throws -> [NSScreen] {
        let screens = NSScreen.screens
        XCTAssertFalse(screens.isEmpty, "macOS tests need at least one NSScreen")
        return screens
    }

    func testOneBasedScreenNumberSelectsThatScreen() throws {
        let screens = try requireScreens()

        let chosen = PresentationScreenResolver.screen(
            for: 1,
            screens: screens,
            mouseLocation: .zero,
            main: screens.last
        )

        XCTAssertEqual(chosen, screens[0])
    }

    func testOutOfRangeAndZeroFallBackToCursorScreen() throws {
        let screens = try requireScreens()
        let mouse = NSPoint(x: screens[0].frame.midX, y: screens[0].frame.midY)

        for number in [0, 99] {
            let chosen = PresentationScreenResolver.screen(
                for: number,
                screens: screens,
                mouseLocation: mouse,
                main: nil
            )
            XCTAssertEqual(chosen, screens[0], "screenNumber \(number)")
        }
    }

    func testNilScreenNumberUsesCursorThenMainThenFirst() throws {
        let screens = try requireScreens()
        let inside = NSPoint(x: screens[0].frame.midX, y: screens[0].frame.midY)
        let outside = NSPoint(x: screens[0].frame.maxX + 10000, y: screens[0].frame.maxY + 10000)

        XCTAssertEqual(
            PresentationScreenResolver.screen(
                for: nil,
                screens: screens,
                mouseLocation: inside,
                main: nil
            ),
            screens[0]
        )
        XCTAssertEqual(
            PresentationScreenResolver.screen(
                for: nil,
                screens: screens,
                mouseLocation: outside,
                main: screens[0]
            ),
            screens[0]
        )
        XCTAssertEqual(
            PresentationScreenResolver.screen(
                for: nil,
                screens: screens,
                mouseLocation: outside,
                main: nil
            ),
            screens.first
        )
    }
}
