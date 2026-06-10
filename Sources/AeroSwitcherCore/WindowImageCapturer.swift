import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum WindowCaptureError: Error, CustomStringConvertible {
    case windowNotFound(CGWindowID)
    case captureFailed(CGWindowID, String)

    public var description: String {
        switch self {
        case let .windowNotFound(id):
            "Window \(id) is not available for capture"
        case let .captureFailed(id, message):
            "Window \(id) capture failed: \(message)"
        }
    }
}

/// Captures individual windows through ScreenCaptureKit, replacing
/// `screencapture -x -o -l<window-id>`.
public final class WindowImageCapturer: Sendable {
    public init() {}

    /// Resolves the shareable windows once so a batch of captures shares a
    /// single (comparatively slow) SCShareableContent query.
    public func shareableWindows() async throws -> [CGWindowID: SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return Dictionary(content.windows.map { ($0.windowID, $0) }) { first, _ in first }
    }

    public func captureImage(of window: SCWindow, scale: CGFloat) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best

        let filter = SCContentFilter(desktopIndependentWindow: window)
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw WindowCaptureError.captureFailed(window.windowID, "\(error)")
        }
    }

    /// Resolved once per capture batch so the per-window captures avoid a
    /// MainActor hop each.
    @MainActor
    public func maximumDisplayScale() -> CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }
}
