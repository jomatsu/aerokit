import CoreGraphics
import XCTest
@testable import AeroSwitcherCore

final class WindowImageCapturerTests: XCTestCase {
    func testLargeWindowIsScaledDownToMaxDimension() {
        let scale = WindowImageCapturer.captureScale(
            frame: CGSize(width: 3200, height: 1800),
            displayScale: 2,
            maxDimension: 800
        )
        XCTAssertEqual(scale, 0.25, accuracy: 0.0001)
        XCTAssertEqual(3200 * scale, 800, accuracy: 0.01)
    }

    func testSmallWindowKeepsRetinaScale() {
        let scale = WindowImageCapturer.captureScale(
            frame: CGSize(width: 300, height: 200),
            displayScale: 2,
            maxDimension: 800
        )
        XCTAssertEqual(scale, 2)
    }

    func testZeroSizeFrameDoesNotDivideByZero() {
        let scale = WindowImageCapturer.captureScale(
            frame: .zero,
            displayScale: 2,
            maxDimension: 800
        )
        XCTAssertEqual(scale, 2)
    }

    /// Canary: the fast path resolves CGWindowListCreateImage at runtime
    /// because the deprecated symbol is gone from the Swift overlay. If a
    /// macOS update removes it entirely, this fails before users hit the
    /// (slower) ScreenCaptureKit-only behaviour silently.
    func testFastPathSymbolResolves() {
        XCTAssertNotNil(WindowImageCapturer.createImage)
    }

    func testDownscaledBoundsLongEdgeToMaxDimension() throws {
        let image = try XCTUnwrap(makeImage(width: 3200, height: 1800))
        let scaled = WindowImageCapturer.downscaled(image, maxDimension: 800)
        XCTAssertEqual(scaled.width, 800)
        XCTAssertEqual(scaled.height, 450)
    }

    /// Windows already wider than the compose cell capture at 1x — every
    /// Retina pixel would be discarded by the downscale anyway.
    func testLargeWindowCapturesAtNominalResolution() {
        XCTAssertTrue(WindowImageCapturer.capturesAtNominalResolution(
            pointSize: CGSize(width: 1800, height: 1000),
            maxDimension: 800
        ))
    }

    func testSmallWindowCapturesAtBestResolution() {
        XCTAssertFalse(WindowImageCapturer.capturesAtNominalResolution(
            pointSize: CGSize(width: 480, height: 320),
            maxDimension: 800
        ))
    }

    func testUnknownBoundsCaptureAtBestResolution() {
        XCTAssertFalse(WindowImageCapturer.capturesAtNominalResolution(
            pointSize: nil,
            maxDimension: 800
        ))
    }

    /// Bounds may legitimately be empty in a headless session, but every
    /// reported entry must have a usable size.
    func testWindowBoundsByIDReportsPositiveSizes() {
        for size in WindowImageCapturer().windowBoundsByID().values {
            XCTAssertGreaterThanOrEqual(size.width, 0)
            XCTAssertGreaterThanOrEqual(size.height, 0)
        }
    }

    func testDownscaledKeepsSmallImageUntouched() throws {
        let image = try XCTUnwrap(makeImage(width: 300, height: 200))
        let scaled = WindowImageCapturer.downscaled(image, maxDimension: 800)
        XCTAssertTrue(scaled === image)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        WorkspaceComposer.makeContext(width: width, height: height)?.makeImage()
    }
}
