import AeroKitCore
import AppKit
import SwiftUI
import XCTest
@testable import ExposeFeature

/// Not an assertion suite for Exposé behavior: renders the real
/// `ExposeOverlayView` with fixed session data to `/tmp/aerokit-expose-*.png`
/// (or `RENDER_EXPOSE_DIR`) so PR6 type moves can be compared visually.
/// Skipped unless `RENDER_EXPOSE=1`. Does not exercise tile drag, drop, or
/// snap-back — those stay with interaction tests.
@MainActor
final class ExposeOverlayRenderTests: XCTestCase {
    private static let wideSize = CGSize(width: 1440, height: 900)
    private static let portraitSize = CGSize(width: 900, height: 1440)
    private static let renderScale: CGFloat = 2
    private static let groupingHintKey: Character = "0"

    private struct WindowFixture {
        var id: CGWindowID
        var bundleIdentifier: String
        var appName: String
        var title: String
        var workspace: String
        var pointSize: CGSize
        var hue: CGFloat
    }

    /// Five windows across three apps: two Safari, one Code (the selection),
    /// two Mail. Drafts is a tall window so placeholders and portrait layout
    /// have a distinct tile.
    private static let windowFixtures: [WindowFixture] = [
        WindowFixture(
            id: 101,
            bundleIdentifier: "test.safari",
            appName: "Safari",
            title: "Start Page",
            workspace: "1",
            pointSize: CGSize(width: 1280, height: 800),
            hue: 0.58
        ),
        WindowFixture(
            id: 102,
            bundleIdentifier: "test.safari",
            appName: "Safari",
            title: "Documentation",
            workspace: "1",
            pointSize: CGSize(width: 1100, height: 720),
            hue: 0.62
        ),
        WindowFixture(
            id: 201,
            bundleIdentifier: "test.code",
            appName: "Code",
            title: "ExposeOverlayView.swift",
            workspace: "2",
            pointSize: CGSize(width: 1440, height: 900),
            hue: 0.12
        ),
        WindowFixture(
            id: 301,
            bundleIdentifier: "test.mail",
            appName: "Mail",
            title: "Inbox",
            workspace: "1",
            pointSize: CGSize(width: 900, height: 700),
            hue: 0.95
        ),
        WindowFixture(
            id: 302,
            bundleIdentifier: "test.mail",
            appName: "Mail",
            title: "Drafts",
            workspace: "1",
            pointSize: CGSize(width: 700, height: 900),
            hue: 0.9
        )
    ]

    func testRenderExposeOverlay() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_EXPOSE"] == "1")

        let outputDirectory = try resolveOutputDirectory()

        try render(
            session: makeSession(groupByApp: false, previews: .all, container: Self.wideSize),
            size: Self.wideSize,
            name: "ungrouped-wide",
            to: outputDirectory
        )
        try render(
            session: makeSession(groupByApp: true, previews: .all, container: Self.wideSize),
            size: Self.wideSize,
            name: "grouped-wide",
            to: outputDirectory
        )
        try render(
            session: makeSession(groupByApp: false, previews: .mixed, container: Self.wideSize),
            size: Self.wideSize,
            name: "placeholders-wide",
            to: outputDirectory
        )
        try render(
            session: makeSession(groupByApp: false, previews: .all, container: Self.portraitSize),
            size: Self.portraitSize,
            name: "ungrouped-portrait",
            to: outputDirectory
        )
    }

    private enum PreviewFill {
        /// Every tile has a generated preview.
        case all
        /// Safari and Code have previews; Mail is a placeholder, and Drafts
        /// has neither image nor icon.
        case mixed
    }

    private func makeSession(
        groupByApp: Bool,
        previews: PreviewFill,
        container: CGSize
    ) throws -> ExposeSession {
        let fixtures = Self.windowFixtures
        let windows = fixtures.map {
            ExposeWindow(
                id: $0.id,
                bundleIdentifier: $0.bundleIdentifier,
                appName: $0.appName,
                title: $0.title,
                workspace: $0.workspace
            )
        }
        let bounds = Dictionary(uniqueKeysWithValues: fixtures.map { fixture in
            (fixture.id, CGRect(origin: .zero, size: fixture.pointSize))
        })
        var icons: [CGWindowID: NSImage] = [:]
        for fixture in fixtures where !(previews == .mixed && fixture.id == 302) {
            icons[fixture.id] = HUDRenderMocks.fakeIcon(hue: fixture.hue)
        }

        let session = ExposeSession(
            windows: windows,
            containerAspect: container.width / container.height,
            bounds: bounds,
            focusedWindowID: 201,
            icons: icons,
            groupByApp: groupByApp
        )

        let imagedIDs: Set<CGWindowID> = switch previews {
        case .all:
            Set(fixtures.map(\.id))
        case .mixed:
            [101, 102, 201]
        }
        for fixture in fixtures where imagedIDs.contains(fixture.id) {
            try session.setImage(
                fakePreview(hue: fixture.hue, pointSize: fixture.pointSize),
                forWindow: fixture.id
            )
        }
        return session
    }

    private func render(
        session: ExposeSession,
        size: CGSize,
        name: String,
        to outputDirectory: URL
    ) throws {
        // Settled before the view exists so ImageRenderer captures the
        // cascade's resting frame, not an in-flight offset/opacity.
        let motion = ExposeOverlayMotion()
        motion.edge = .bottom
        motion.veiled = true
        motion.shown = true

        let view = ExposeOverlayView(
            session: session,
            motion: motion,
            quickSelectExclusion: Self.groupingHintKey,
            showsGroupingHint: true,
            onActivate: { _ in },
            onHover: { _ in },
            onCancel: {},
            onToggleGrouping: {},
            onMoveToWorkspace: { _, _ in }
        )
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.35))
        .environment(\.colorScheme, .dark)
        .transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }

        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.renderScale
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = true

        var image: NSImage?
        if let appearance = NSAppearance(named: .darkAqua) {
            appearance.performAsCurrentDrawingAppearance {
                image = renderer.nsImage
            }
        } else {
            image = renderer.nsImage
        }

        let path = outputDirectory.appendingPathComponent("aerokit-expose-\(name).png").path
        guard let image, HUDRenderMocks.writePNG(image, to: path) else {
            XCTFail("render failed: \(name)")
            return
        }
        try assertPlausibleRender(image, at: path, canvas: size, name: name)
    }

    private func resolveOutputDirectory() throws -> URL {
        let env = ProcessInfo.processInfo.environment["RENDER_EXPOSE_DIR"]
        let path = env.flatMap { $0.isEmpty ? nil : $0 } ?? "/tmp"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fakePreview(hue: CGFloat, pointSize: CGSize) throws -> CGImage {
        let width = max(48, Int((pointSize.width / 2).rounded()))
        let height = max(48, Int((pointSize.height / 2).rounded()))
        let context = try XCTUnwrap(
            WindowImageCapturer.makeContext(width: width, height: height),
            "Could not create a mock preview context"
        )
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).cgColor)
        context.fill(bounds)
        context.setFillColor(NSColor(hue: hue, saturation: 0.7, brightness: 0.35, alpha: 0.65).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.45))
        let chrome = bounds.insetBy(dx: bounds.width * 0.08, dy: bounds.height * 0.12)
        context.setFillColor(NSColor.white.withAlphaComponent(0.88).cgColor)
        context.fill(CGRect(
            x: chrome.minX,
            y: chrome.minY + chrome.height * 0.15,
            width: chrome.width * 0.62,
            height: chrome.height * 0.7
        ))
        context.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        context.fill(CGRect(
            x: chrome.minX + chrome.width * 0.4,
            y: chrome.minY,
            width: chrome.width * 0.55,
            height: chrome.height * 0.5
        ))
        return try XCTUnwrap(context.makeImage(), "Could not create a mock preview image")
    }

    private func assertPlausibleRender(
        _ image: NSImage,
        at path: String,
        canvas: CGSize,
        name: String
    ) throws {
        let tiff = try XCTUnwrap(image.tiffRepresentation, "no TIFF for \(name)")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff), "no bitmap for \(name)")
        XCTAssertEqual(
            bitmap.pixelsWide,
            Int((canvas.width * Self.renderScale).rounded()),
            "pixel width for \(name)"
        )
        XCTAssertEqual(
            bitmap.pixelsHigh,
            Int((canvas.height * Self.renderScale).rounded()),
            "pixel height for \(name)"
        )

        let fileSize = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber,
            "missing PNG for \(name)"
        ).intValue
        XCTAssertGreaterThan(fileSize, 8000, "PNG too small for \(name): \(fileSize) bytes")

        var opaqueSamples = 0
        var distinct = Set<UInt32>()
        let stepX = max(1, bitmap.pixelsWide / 24)
        let stepY = max(1, bitmap.pixelsHigh / 24)
        for row in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
            for column in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
                guard let color = bitmap.colorAt(x: column, y: row),
                      let rgb = color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB)
                else {
                    continue
                }
                if rgb.alphaComponent > 0.05 {
                    opaqueSamples += 1
                }
                let red = UInt32((rgb.redComponent * 15).rounded())
                let green = UInt32((rgb.greenComponent * 15).rounded())
                let blue = UInt32((rgb.blueComponent * 15).rounded())
                distinct.insert((red << 8) | (green << 4) | blue)
            }
        }
        XCTAssertGreaterThan(opaqueSamples, 20, "render looks transparent: \(name)")
        XCTAssertGreaterThan(distinct.count, 4, "render looks empty: \(name)")
    }
}
