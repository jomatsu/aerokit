import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum WindowCaptureError: Error, CustomStringConvertible {
    case captureFailed(CGWindowID, String)

    public var description: String {
        switch self {
        case let .captureFailed(id, message):
            "Window \(id) capture failed: \(message)"
        }
    }
}

/// Captures individual windows through CGWindowListCreateImage with a
/// ScreenCaptureKit fallback. Shared by the switcher's snapshot engine and
/// the exposé's live previews.
public final class WindowImageCapturer: Sendable {
    public init() {}

    /// Resolves the shareable windows once so a batch of captures shares a
    /// single (comparatively slow) SCShareableContent query.
    public func shareableWindows() async throws -> [CGWindowID: SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return Dictionary(content.windows.map { ($0.windowID, $0) }) { first, _ in first }
    }

    /// Window bounds (in points, global display space) for every window,
    /// fetched in one WindowServer round trip; drives the per-window capture
    /// resolution and the exposé's spatial ordering.
    public func windowBoundsByID() -> [CGWindowID: CGRect] {
        guard let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var result = [CGWindowID: CGRect]()
        for entry in info {
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let originX = bounds["X"], let originY = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else {
                continue
            }
            result[id] = CGRect(x: originX, y: originY, width: width, height: height)
        }
        return result
    }

    /// All on-screen window ids, front to back — the system's stacking
    /// order, the recency proxy a hold-to-cycle switcher cycles through.
    /// Desktop elements are excluded; AeroSpace's parked windows are still
    /// on screen (just moved offscreen), so callers filter by their own
    /// window set.
    public func onScreenWindowIDsFrontToBack() -> [CGWindowID] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }

    // MARK: - Fast path: CGWindowListCreateImage

    /// CGWindowListCreateImage reads the window backing store directly
    /// (~9ms/window vs ~105ms through SCScreenshotManager, whose XPC round
    /// trips serialize in replayd) and, unlike the CGS hardware-capture SPIs,
    /// returns full content for windows AeroSpace parked off-screen.
    ///
    /// The function is deprecated since macOS 14 and removed from the Swift
    /// overlay, so it is resolved at runtime; callers must keep the
    /// ScreenCaptureKit path as fallback for when it returns nil or the
    /// symbol disappears in a future release.
    typealias CreateImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    static let createImage: CreateImageFn? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CreateImageFn.self)
    }()

    /// Windows whose point size already exceeds the capture budget at
    /// nominal (1x) resolution: the downscale would discard every Retina
    /// pixel anyway, and the smaller backing-store copy roughly quarters
    /// both capture and downscale cost. Smaller windows keep best (2x) so
    /// they stay sharp; unknown bounds err toward quality.
    static func capturesAtNominalResolution(pointSize: CGSize?, maxDimension: CGFloat) -> Bool {
        guard let pointSize else {
            return false
        }
        return max(pointSize.width, pointSize.height) >= maxDimension
    }

    public func captureImageFast(windowID: CGWindowID, maxDimension: CGFloat, pointSize: CGSize?) -> CGImage? {
        guard let create = Self.createImage else {
            return nil
        }
        let listOption: UInt32 = 1 << 3 // kCGWindowListOptionIncludingWindow
        let resolutionBit: UInt32 = Self.capturesAtNominalResolution(pointSize: pointSize, maxDimension: maxDimension)
            ? 1 << 4 // NominalResolution
            : 1 << 3 // BestResolution
        let imageOption: UInt32 = (1 << 0) | resolutionBit // BoundsIgnoreFraming | resolution
        // 1×1 results are what minimized/unreadable windows come back as.
        guard let image = create(.null, listOption, UInt32(windowID), imageOption)?.takeRetainedValue(),
              image.width > 1, image.height > 1
        else {
            return nil
        }
        return Self.downscaled(image, maxDimension: maxDimension)
    }

    /// CPU-side counterpart of the SCK GPU downscale: bounds the long edge to
    /// `maxDimension` so full-Retina pixels never enter the compose pipeline.
    /// Images at or under the bound come back unchanged.
    public static func downscaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1,
              let context = makeContext(
                  width: Int((size.width * scale).rounded()),
                  height: Int((size.height * scale).rounded())
              )
        else {
            return image
        }
        // .medium is visually indistinguishable from .high at these shrink
        // ratios and measurably cheaper per window.
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage() ?? image
    }

    public static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: max(1, width),
            height: max(1, height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }

    // MARK: - Fallback: ScreenCaptureKit

    /// `maxDimension` bounds the long edge of the returned image:
    /// ScreenCaptureKit scales the capture down on the GPU, so full-Retina
    /// pixels never enter the encode/compose pipeline.
    public func captureImage(
        of window: SCWindow,
        displayScale: CGFloat,
        maxDimension: CGFloat
    ) async throws -> CGImage {
        let scale = Self.captureScale(
            frame: window.frame.size,
            displayScale: displayScale,
            maxDimension: maxDimension
        )
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
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

    /// Small windows keep their native Retina scale; anything larger is
    /// scaled so the long edge lands on `maxDimension`.
    static func captureScale(frame: CGSize, displayScale: CGFloat, maxDimension: CGFloat) -> CGFloat {
        let longEdge = max(frame.width, frame.height, 1)
        return min(displayScale, maxDimension / longEdge)
    }

    /// Resolved once per capture batch so the per-window captures avoid a
    /// MainActor hop each.
    @MainActor
    public func maximumDisplayScale() -> CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }
}
