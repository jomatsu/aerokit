import CoreGraphics
import Foundation

/// Compose-size images from earlier runs, keyed by window ID and validated
/// against the source file's modification date, so the snapshot reuse path
/// skips decoding entirely. Bounded by the number of configured windows
/// (pruned each refresh).
///
/// `@unchecked` because the entry dictionary is guarded by `lock`.
final class ComposeImageCache: @unchecked Sendable {
    private let maxDimension: CGFloat
    private var entries: [String: (modifiedAt: Date, image: CGImage)] = [:]
    private let lock = NSLock()

    init(maxDimension: CGFloat) {
        self.maxDimension = maxDimension
    }

    func store(_ image: CGImage, forWindowID id: String, sourceURL: URL) {
        guard let modifiedAt = sourceURL.contentModificationDate else {
            return
        }
        lock.withLock {
            entries[id] = (modifiedAt, image)
        }
    }

    /// Returns the compose-size image for the capture at `url`, decoding the
    /// file only on a cache miss.
    func image(forWindowID id: String, at url: URL) -> CGImage? {
        guard let modifiedAt = url.contentModificationDate else {
            return nil
        }
        // copyItem preserves the modification date, so the key stays valid
        // across the cached-copy chain even though the path changes per run.
        if let cached = lock.withLock({ entries[id] }), cached.modifiedAt == modifiedAt {
            return cached.image
        }

        guard let image = WorkspaceComposer.loadImage(at: url) else {
            return nil
        }
        // New captures already arrive at compose size; this only shrinks
        // full-resolution captures carried over from runs of older versions.
        let composeImage = WindowImageCapturer.downscaled(image, maxDimension: maxDimension)
        lock.withLock {
            entries[id] = (modifiedAt, composeImage)
        }
        return composeImage
    }

    func prune(keeping windowIDs: Set<String>) {
        lock.withLock {
            entries = entries.filter { windowIDs.contains($0.key) }
        }
    }
}
