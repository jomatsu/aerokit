import AppKit
import SwiftUI
import XCTest
@testable import SwipeFeature

/// Not an assertion suite: renders the swipe HUD with mock data to
/// /tmp/aerokit-hud-*.png so its design can be reviewed without driving
/// the real trackpad. Skipped unless RENDER_HUD=1.
@MainActor
final class SwipeHUDRenderTests: XCTestCase {
    func testRenderHUD() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_HUD"] == "1")

        let workspaces = ["1", "2", "3", "browser", "code"]
        let model = SwipeHUDModel()
        model.update(
            workspaces: workspaces,
            current: "2",
            previews: [
                "1": Self.fakeScreenshot(hue: 0.58),
                "2": Self.fakeScreenshot(hue: 0.08),
                "3": Self.fakeScreenshot(hue: 0.33),
                "browser": Self.fakeScreenshot(hue: 0.75),
            ],
            wrapsAround: false,
            animated: false
        )
        model.isVisible = true

        render(model: model, offset: 0, name: "rest")
        render(model: model, offset: 0.5, name: "mid")
        render(model: model, offset: 1.4, name: "drag")
    }

    private func render(model: SwipeHUDModel, offset: CGFloat, name: String) {
        model.offset = offset
        let view = SwipeHUDView(model: model)
            .frame(width: 900, height: 200)
            .background(Color(white: 0.35))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("render failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: "/tmp/aerokit-hud-\(name).png"))
    }

    /// Gradient stand-in for a workspace snapshot.
    private static func fakeScreenshot(hue: CGFloat) -> NSImage {
        let size = NSSize(width: 320, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(
            starting: NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1),
            ending: NSColor(hue: hue, saturation: 0.7, brightness: 0.35, alpha: 1)
        )
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -60)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSRect(x: 30, y: 40, width: 180, height: 120).fill()
        NSColor.white.withAlphaComponent(0.6).setFill()
        NSRect(x: 170, y: 20, width: 120, height: 90).fill()
        image.unlockFocus()
        return image
    }
}
