import AppKit
import Foundation
import ImageIO

public final class SnapshotStore: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let maxThumbnailPixelSize: CGFloat
    private var imageCache: [URL: (modifiedAt: Date, image: NSImage)] = [:]
    private let imageCacheLock = NSLock()

    public init(rootPath: String, maxThumbnailPixelSize: CGFloat = 640, fileManager: FileManager = .default) {
        rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        self.maxThumbnailPixelSize = maxThumbnailPixelSize
        self.fileManager = fileManager
    }

    public func currentDirectory() -> URL? {
        let current = rootURL.appendingPathComponent("current", isDirectory: true)
        if directoryHasCaptures(current) {
            return current
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return children
            .filter(directoryHasCaptures)
            .max { lhs, rhs in
                (lhs.contentModificationDate ?? .distantPast) < (rhs.contentModificationDate ?? .distantPast)
            }
    }

    public func isStale(maxAge: TimeInterval) -> Bool {
        guard let directory = currentDirectory() else {
            return true
        }

        let manifest = directory.appendingPathComponent("manifest.tsv")
        guard let modifiedAt = manifest.contentModificationDate else {
            return true
        }

        return Date().timeIntervalSince(modifiedAt) > maxAge
    }

    public func snapshotImage(for workspaceName: String) -> NSImage? {
        currentDirectory().flatMap { snapshotImage(for: workspaceName, in: $0) }
    }

    public func snapshotImage(for workspaceName: String, in directory: URL) -> NSImage? {
        let url = directory.appendingPathComponent(WorkspaceName.overviewFileName(workspaceName))
        guard let modifiedAt = url.contentModificationDate else {
            return nil
        }

        if let cached = imageCacheLock.withLock({ imageCache[url] }), cached.modifiedAt == modifiedAt {
            return cached.image
        }

        guard let image = downsampledImage(at: url) else {
            return nil
        }

        imageCacheLock.withLock {
            imageCache[url] = (modifiedAt, image)
        }
        return image
    }

    private func downsampledImage(at url: URL) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func directoryHasCaptures(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        let manifest = directory.appendingPathComponent("manifest.tsv")
        guard let data = try? String(contentsOf: manifest, encoding: .utf8) else {
            return false
        }

        return data
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let status = line.split(separator: "\t", omittingEmptySubsequences: false).last.map(String.init)
                return status == SnapshotStatus.captured.rawValue
                    || status == SnapshotStatus.cached.rawValue
                    || status == SnapshotStatus.capturedVisible.rawValue
            }
    }
}
