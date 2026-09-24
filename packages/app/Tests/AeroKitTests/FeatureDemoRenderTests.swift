import SwiftUI
import XCTest
@testable import AeroKitCore

/// Every demo renders at each phase of its loop, in a language with long
/// strings, without collapsing to an empty image.
@MainActor
final class FeatureDemoRenderTests: XCTestCase {
    private let phases = [0.0, 0.15, 0.3, 0.45, 0.6, 0.7, 0.8, 0.95]

    func testDemosRenderAcrossTheLoop() throws {
        let demos: [(String, AnyView)] = [
            ("switcher-release", AnyView(WorkspaceSwitcherDemo(
                shortcut: ["⌥", "`"], releaseToSwitch: true, startsOnNext: false
            ))),
            ("switcher-return", AnyView(WorkspaceSwitcherDemo(
                shortcut: ["⌃", "⌥", "Space"], releaseToSwitch: false, startsOnNext: true
            ))),
            ("swipe", AnyView(WorkspaceSwipeDemo(naturalDirection: true))),
            ("overview", AnyView(WindowOverviewDemo(shortcut: ["⌥", "M"]))),
            ("vertical", AnyView(VerticalGestureDemo())),
            ("quick-switch", AnyView(QuickWindowSwitchDemo(shortcut: []))),
            ("ambient", AnyView(AmbientDesktopDemo())),
            ("capture", AnyView(PreviewCaptureDemo()))
        ]
        let output = ProcessInfo.processInfo.environment["AEROKIT_DEMO_RENDER_DIR"].map(URL.init(fileURLWithPath:))
        for (name, demo) in demos {
            for phase in phases {
                let renderer = ImageRenderer(
                    content: demo
                        .environment(\.demoProgressOverride, phase)
                        .padding(20)
                        .frame(width: 440)
                        .background(Color.white)
                )
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage, "\(name) @ \(phase)")
                XCTAssertGreaterThan(image.size.height, 120, "\(name) @ \(phase)")
                if let output, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                {
                    try png.write(to: output.appendingPathComponent("\(name)-\(Int(phase * 100)).png"))
                }
            }
        }
    }
}
