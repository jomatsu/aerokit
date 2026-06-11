import CoreGraphics
import XCTest
@testable import AeroKitCore
@testable import SwitcherFeature

final class WorkspaceComposerTests: XCTestCase {
    func testTileColumnsDefaultLayout() {
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 0, rootLayout: ""), 1)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 1, rootLayout: ""), 1)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 2, rootLayout: ""), 2)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 4, rootLayout: ""), 2)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 5, rootLayout: ""), 3)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 9, rootLayout: ""), 3)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 10, rootLayout: ""), 4)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 16, rootLayout: ""), 4)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 17, rootLayout: ""), 5)
    }

    func testTileColumnsHorizontalTiles() {
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 3, rootLayout: "h_tiles"), 3)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 4, rootLayout: "h_tiles"), 4)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 5, rootLayout: "h_tiles"), 3)
    }

    func testTileColumnsVerticalTiles() {
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 3, rootLayout: "v_tiles"), 1)
        XCTAssertEqual(WorkspaceComposer.tileColumns(count: 5, rootLayout: "v_tiles"), 3)
    }

    func testBlackishDetection() throws {
        let black = try XCTUnwrap(solidImage(white: 0))
        let white = try XCTUnwrap(solidImage(white: 1))
        XCTAssertTrue(WorkspaceComposer.isBlackish(black))
        XCTAssertFalse(WorkspaceComposer.isBlackish(white))
    }

    func testComposeOverviewMatchesCanvasSize() throws {
        let cell = try XCTUnwrap(solidImage(white: 0.5))
        let overview = try XCTUnwrap(WorkspaceComposer.composeOverview(
            images: [cell, cell, cell],
            rootLayout: "",
            canvasSize: CGSize(width: 1600, height: 900)
        ))
        XCTAssertEqual(overview.width, 1600)
        XCTAssertEqual(overview.height, 900)
    }

    func testEmptyOverviewMatchesCanvasSize() throws {
        let overview = try XCTUnwrap(WorkspaceComposer.emptyOverview(canvasSize: CGSize(width: 1600, height: 900)))
        XCTAssertEqual(overview.width, 1600)
        XCTAssertEqual(overview.height, 900)
    }

    func testWriteJPEGRoundTrip() throws {
        let image = try XCTUnwrap(solidImage(white: 0.5))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aeroswitcher-test-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(WorkspaceComposer.writeJPEG(image, to: url))

        let loaded = try XCTUnwrap(WorkspaceComposer.loadImage(at: url))
        XCTAssertEqual(loaded.width, image.width)
        XCTAssertEqual(loaded.height, image.height)
    }

    private func solidImage(white: CGFloat, size: Int = 100) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: white, green: white, blue: white, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}
