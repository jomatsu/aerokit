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
                "1": HUDRenderMocks.fakeScreenshot(hue: 0.58),
                "2": HUDRenderMocks.fakeScreenshot(hue: 0.08),
                "3": HUDRenderMocks.fakeScreenshot(hue: 0.33),
                "browser": HUDRenderMocks.fakeScreenshot(hue: 0.75),
            ],
            wrapsAround: false,
            animated: false
        )
        // Icons stream in separately in production (SwipeHUD.updateIcons),
        // so the model takes them as a plain assignment.
        model.icons = [
            "1": [HUDRenderMocks.fakeIcon(hue: 0.6), HUDRenderMocks.fakeIcon(hue: 0.95)],
            "2": [
                HUDRenderMocks.fakeIcon(hue: 0.1),
                HUDRenderMocks.fakeIcon(hue: 0.5),
                HUDRenderMocks.fakeIcon(hue: 0.8),
            ],
            "3": [HUDRenderMocks.fakeIcon(hue: 0.3)],
            "code": [HUDRenderMocks.fakeIcon(hue: 0.55), HUDRenderMocks.fakeIcon(hue: 0.0)],
        ]
        model.isVisible = true

        render(model: model, offset: 0, name: "rest")
        render(model: model, offset: 0.5, name: "mid")
        render(model: model, offset: 1.4, name: "drag")
        render(model: model, offset: -1, name: "edge")
    }

    private func render(model: SwipeHUDModel, offset: CGFloat, name: String) {
        model.offset = offset
        let view = SwipeHUDView(model: model)
            .frame(width: 900, height: 200)
            .background(Color(white: 0.35))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              HUDRenderMocks.writePNG(image, to: "/tmp/aerokit-hud-\(name).png")
        else {
            XCTFail("render failed")
            return
        }
    }
}
