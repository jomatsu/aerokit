import AeroKitCore
import AppKit
import CoreGraphics
import Foundation

/// The shared preview-capture pipeline: one fast CGWindowListCreateImage
/// pass per window (capped by the shared capture limiter), streaming images
/// into the caller's delivery closure as they land, then a sequential
/// ScreenCaptureKit fallback for windows the fast path could not read.
/// Shared by the exposé's tiles and the window switcher's strip.
@MainActor
enum WindowPreviewCapture {
    /// One presentation's capture inputs.
    struct Request {
        let capturer: WindowImageCapturer
        let ids: [CGWindowID]
        let bounds: [CGWindowID: CGRect]
        let displayScale: CGFloat
        let maxDimension: CGFloat
    }

    /// - Parameters:
    ///   - deliver: called on the main actor per window; a nil image means
    ///     the fast path missed (the fallback retries those).
    ///   - onInitialPass: fired once the fast pass has delivered everything
    ///     it could — the cue that the tiles are as pictorial as they are
    ///     going to quickly get. Skipped when the task was cancelled (the
    ///     presentation was dismissed) so a stale session can't start a
    ///     newer overlay's entry.
    static func run(
        _ request: Request,
        deliver: (CGWindowID, CGImage?) -> Void,
        onInitialPass: () -> Void
    ) async {
        var missed: [CGWindowID] = []
        await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            for id in request.ids {
                let pointSize = request.bounds[id]?.size
                group.addTask {
                    let image = await CaptureLimiter.shared.withSlot { () -> CGImage? in
                        // A dismissed overlay cancels its captures; once
                        // the slot frees up, skip the stale work instead
                        // of capturing for a session that is gone.
                        guard !Task.isCancelled else {
                            return nil
                        }
                        return request.capturer.captureImageFast(
                            windowID: id,
                            maxDimension: request.maxDimension,
                            pointSize: pointSize
                        )
                    }
                    return (id, image)
                }
            }
            for await (id, image) in group {
                deliver(id, image)
                if image == nil {
                    missed.append(id)
                }
            }
        }

        guard !Task.isCancelled else {
            return
        }
        onInitialPass()

        guard !missed.isEmpty else {
            return
        }
        // Sequential on purpose: the fallback is rare and
        // SCScreenshotManager captures serialize in replayd anyway.
        let fallbackImages = await captureFallback(
            capturer: request.capturer,
            missed: missed,
            displayScale: request.displayScale,
            maxDimension: request.maxDimension
        )
        for (id, image) in fallbackImages {
            deliver(id, image)
        }
    }

    /// SCK pass for windows the fast path could not read. Nonisolated on
    /// purpose: ScreenCaptureKit objects stay inside this function, and
    /// only Sendable results (window id + CGImage) cross back.
    private nonisolated static func captureFallback(
        capturer: WindowImageCapturer,
        missed: [CGWindowID],
        displayScale: CGFloat,
        maxDimension: CGFloat
    ) async -> [(CGWindowID, CGImage)] {
        guard let shareable = try? await capturer.shareableWindows() else {
            return []
        }
        var images: [(CGWindowID, CGImage)] = []
        for id in missed {
            guard !Task.isCancelled, let window = shareable[id] else {
                continue
            }
            if let image = try? await capturer.captureImage(
                of: window,
                displayScale: displayScale,
                maxDimension: maxDimension
            ) {
                images.append((id, image))
            }
        }
        return images
    }
}
