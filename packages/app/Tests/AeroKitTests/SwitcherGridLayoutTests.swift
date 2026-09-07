import AppKit
import XCTest
@testable import SwitcherFeature

final class SwitcherGridLayoutTests: XCTestCase {
    func testFullscreenEnlargesPreviewsAndReservesSpaceForTitles() {
        let size = CGSize(width: 2560, height: 1440)
        let layout = makeLayout(size: size, count: 8, fullscreen: true, titles: true)
        XCTAssertEqual(layout.panelSize, size)
        XCTAssertGreaterThan(layout.snapshotSize.width, 320)
        XCTAssertEqual(layout.snapshotSize.width / layout.snapshotSize.height, 16 / 9, accuracy: 0.001)
        // Two rows, each with icons, workspace label and titles, plus padding/chrome.
        XCTAssertLessThanOrEqual(2 * (layout.snapshotSize.height + 60 + 76) + 60 + 80, size.height)
    }

    func testCompactAndCrowdedLayoutsRemainWithinDisplay() {
        for size in [CGSize(width: 900, height: 1440), CGSize(width: 1280, height: 720)] {
            for fullscreen in [false, true] {
                for count in [0, 1, 8, 40] {
                    let layout = makeLayout(size: size, count: count, fullscreen: fullscreen, titles: true)
                    XCTAssertGreaterThan(layout.snapshotSize.width, 0)
                    XCTAssertLessThanOrEqual(layout.panelSize.width, size.width)
                    XCTAssertLessThanOrEqual(layout.panelSize.height, size.height)
                    XCTAssertGreaterThanOrEqual(layout.columns, 1)
                }
            }
        }
    }

    private func makeLayout(size: CGSize, count: Int, fullscreen: Bool, titles: Bool) -> SwitcherGridLayout {
        SwitcherGridLayout(
            available: size,
            count: count,
            columns: 4,
            configuration: SwitcherConfiguration(),
            fullscreen: fullscreen,
            showTitles: titles,
            showHints: true
        )
    }
}
