import AppKit

/// Mock assets shared by the HUD render suites (`SwipeHUDRenderTests`,
/// `SwipeHUDVariantRenderTests`).
enum HUDRenderMocks {
    /// Rounded-square stand-in for an app icon.
    static func fakeIcon(hue: CGFloat) -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        let path = NSBezierPath(
            roundedRect: NSRect(x: 4, y: 4, width: 56, height: 56),
            xRadius: 14,
            yRadius: 14
        )
        NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 20, y: 20, width: 24, height: 24)).fill()
        image.unlockFocus()
        return image
    }

    /// Gradient stand-in for a workspace snapshot.
    static func fakeScreenshot(hue: CGFloat) -> NSImage {
        let size = NSSize(width: 320, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(
            starting: NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1),
            ending: NSColor(hue: hue, saturation: 0.7, brightness: 0.35, alpha: 1)
        )
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -60)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSRect(x: 30, y: 40, width: 180, height: 120).fill()
        NSColor.white.withAlphaComponent(0.6).setFill()
        NSRect(x: 170, y: 20, width: 120, height: 90).fill()
        image.unlockFocus()
        return image
    }

    /// PNG-encodes a rendered image to /tmp for review.
    static func writePNG(_ image: NSImage, to path: String) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
