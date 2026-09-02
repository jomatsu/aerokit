import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Replaces the ImageMagick pipeline of aerospace-workspace-snapshot.sh:
/// black-frame statistics, per-workspace overview composition, and PNG output.
public enum WorkspaceComposer {
    static let canvasColor = CGColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    static let borderColor = CGColor(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 1)

    // MARK: - Black-frame detection (magick identify '%[fx:mean] %[fx:standard_deviation]')

    public static func isBlackish(
        _ image: CGImage,
        maxMean: Double = 0.01,
        maxStandardDeviation: Double = 0.02
    ) -> Bool {
        guard let stats = meanAndStandardDeviation(of: image) else {
            return false
        }
        return stats.mean <= maxMean && stats.standardDeviation <= maxStandardDeviation
    }

    static func meanAndStandardDeviation(of image: CGImage) -> (mean: Double, standardDeviation: Double)? {
        let sampleSize = 64
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize)
        guard let context = CGContext(
            data: &pixels,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        let values = pixels.map { Double($0) / 255 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, variance.squareRoot())
    }

    // MARK: - Grid layout (tile_columns)

    public static func tileColumns(count: Int, rootLayout: String) -> Int {
        if rootLayout == "h_tiles", count <= 4 {
            return count
        }
        if rootLayout == "v_tiles", count <= 4 {
            return 1
        }
        switch count {
        case ...1: return 1
        case ...4: return 2
        case ...9: return 3
        case ...16: return 4
        default: return 5
        }
    }

    // MARK: - Overview composition (compose_workspace_snapshots)

    public static func composeOverview(
        images: [CGImage],
        rootLayout: String,
        canvasSize: CGSize = CGSize(width: 1600, height: 900),
        gap: CGFloat = 16
    ) -> CGImage? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        guard let context = makeCanvas(width: width, height: height) else {
            return nil
        }

        guard !images.isEmpty else {
            return context.makeImage()
        }

        let count = images.count
        let cols = tileColumns(count: count, rootLayout: rootLayout)
        let rows = (count + cols - 1) / cols
        let cellWidth = (canvasSize.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
        let cellHeight = (canvasSize.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        var innerWidth = cellWidth - gap
        var innerHeight = cellHeight - gap
        if innerWidth < 80 {
            innerWidth = cellWidth
        }
        if innerHeight < 60 {
            innerHeight = cellHeight
        }

        let gridLeft = (canvasSize.width - CGFloat(cols) * cellWidth) / 2
        let gridTop = (canvasSize.height - CGFloat(rows) * cellHeight) / 2

        context.interpolationQuality = .high

        for (index, image) in images.enumerated() {
            let row = index / cols
            let col = index % cols
            let cellRect = CGRect(
                x: gridLeft + CGFloat(col) * cellWidth,
                y: canvasSize.height - gridTop - CGFloat(row + 1) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )

            let borderRect = centered(width: innerWidth + gap, height: innerHeight + gap, in: cellRect)
            context.setFillColor(borderColor)
            context.fill(borderRect)

            let innerRect = centered(width: innerWidth, height: innerHeight, in: cellRect)
            context.setFillColor(canvasColor)
            context.fill(innerRect)

            context.draw(image, in: aspectFit(image, in: innerRect))
        }

        return context.makeImage()
    }

    public static func emptyOverview(canvasSize: CGSize = CGSize(width: 1600, height: 900)) -> CGImage? {
        makeCanvas(width: Int(canvasSize.width), height: Int(canvasSize.height))?.makeImage()
    }

    // MARK: - Image I/O

    /// Per-window captures are thumbnail material, so lossy JPEG keeps the
    /// encode fast and the files small; overviews stay PNG.
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.85) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination)
    }

    public static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    public static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Helpers

    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func makeCanvas(width: Int, height: Int) -> CGContext? {
        guard let context = makeContext(width: width, height: height) else {
            return nil
        }
        context.setFillColor(canvasColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func centered(width: CGFloat, height: CGFloat, in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func aspectFit(_ image: CGImage, in rect: CGRect) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else {
            return rect
        }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        return centered(width: imageSize.width * scale, height: imageSize.height * scale, in: rect)
    }
}
