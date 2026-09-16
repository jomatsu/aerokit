import AeroKitCore
import AppKit
import SwiftUI
import XCTest
@testable import SwitcherFeature

/// Opt-in visual fixtures: RENDER_SWITCHER=1 swift test --filter SwitcherOverlayRenderTests.
@MainActor
final class SwitcherOverlayRenderTests: XCTestCase {
    func testRenderAppearanceVariants() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_SWITCHER"] == "1")
        let suite = "SwitcherOverlayRenderTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.disableOpeningAnimation = true
        let configuration = SwitcherConfiguration()
        let model = SwiftUIOverlay(configuration: configuration, preferences: preferences)
        model.update(items: fixtures(), selectedIndex: 2, snapshotFeedback: .idle)

        for (name, size, fullscreen, titles, blur) in [
            ("compact", CGSize(width: 1440, height: 900), false, false, false),
            ("fullscreen", CGSize(width: 1920, height: 1080), true, true, true),
            ("portrait", CGSize(width: 900, height: 1440), true, true, false),
            ("compact-titles", CGSize(width: 1440, height: 900), false, true, true)
        ] {
            preferences.fullscreenSwitcher = fullscreen
            preferences.showWindowTitles = titles
            preferences.useExposeBackground = blur
            let view = SwitcherOverlayView(model: model, configuration: configuration, preferences: preferences)
                .frame(width: size.width, height: size.height)
                .background(Color.gray)
                .environment(\.colorScheme, .dark)
            try await render(view, size: size, name: name)
        }
    }

    private func render(_ view: some View, size: CGSize, name: String) async throws {
        // ImageRenderer omits lazy scroll content; host offscreen and let
        // AppKit lay it out before capturing the real view hierarchy.
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        XCTAssertTrue(HUDRenderMocks.writePNG(image, to: "/tmp/aerokit-switcher-\(name).png"))
    }

    private func fixtures() -> [WorkspacePresentation] {
        (1 ... 8).map { index in
            let windows = (1 ... 5).map { number in
                WorkspaceWindow(
                    id: "\(index)-\(number)",
                    bundleIdentifier: "test.browser",
                    appName: "Browser",
                    workspace: "\(index)",
                    title: number == 1 ? "AeroKit — workspace switcher appearance and layout review" :
                        "Document \(number)"
                )
            }
            let snapshot = NSImage(size: CGSize(width: 640, height: 360), flipped: false) { bounds in
                NSColor(calibratedHue: CGFloat(index) / 10, saturation: 0.45, brightness: 0.3, alpha: 1).setFill()
                bounds.fill()
                NSColor.darkGray.setFill()
                bounds.insetBy(dx: 18, dy: 18).fill()
                NSColor.gray.setFill()
                CGRect(x: 28, y: 30, width: 280, height: 280).fill()
                NSColor.lightGray.setFill()
                CGRect(x: 322, y: 30, width: 280, height: 280).fill()
                return true
            }
            let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app")
            return WorkspacePresentation(
                workspace: Workspace(
                    name: "\(index)",
                    apps: [],
                    isFocused: index == 1,
                    isEmpty: false,
                    windows: windows
                ),
                snapshot: snapshot,
                appIcons: [icon]
            )
        }
    }
}
