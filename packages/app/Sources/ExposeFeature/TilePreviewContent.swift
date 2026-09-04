import AppKit
import SwiftUI

/// A window's picture, or its app icon on a dim plate while the capture is
/// still on its way. Shared by the grid tiles and the drag ghost — the
/// ghost is the tile's stand-in, so the two must never drift apart.
struct TilePreviewContent: View {
    let image: CGImage?
    let icon: NSImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .transition(.opacity)
        } else {
            Rectangle()
                .fill(.white.opacity(0.07))
                .overlay {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                }
        }
    }
}
