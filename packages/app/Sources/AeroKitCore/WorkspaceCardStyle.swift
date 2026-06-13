import AppKit
import SwiftUI

/// Shared visual language for workspace strips — the swipe HUD and the
/// exposé's drag-to-workspace drop bar. One set of metrics and chrome so
/// the two strips read as one family instead of drifting hand-kept copies.
/// Feature-specific overlays (icon scrims, emphasis veils, selection
/// rings) stay in their features, layered on top of these bases.
public enum WorkspaceCardMetrics {
    public static let thumbSize = CGSize(width: 140, height: 87.5)
    public static let cellSpacing: CGFloat = 12
    public static let captionSpacing: CGFloat = 6
    public static let captionHeight: CGFloat = 14
    public static let cardCornerRadius: CGFloat = 8
    public static let panelCornerRadius: CGFloat = 18
    public static let panelPadding: CGFloat = 12

    /// One card's full height: the thumbnail plus its caption row.
    public static var cellHeight: CGFloat {
        thumbSize.height + captionSpacing + captionHeight
    }
}

public extension View {
    /// Raycast-style glass panel behind a workspace strip: dark glass over
    /// blur with a top-lit hairline and a soft, close shadow (a heavy halo
    /// reads as smudges sticking out past the panel's sides).
    func workspaceStripPanel() -> some View {
        background {
            RoundedRectangle(cornerRadius: WorkspaceCardMetrics.panelCornerRadius, style: .continuous)
                .fill(.black.opacity(0.5))
                .background {
                    RoundedRectangle(cornerRadius: WorkspaceCardMetrics.panelCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    // Bright at the top where the light hits, falling off
                    // toward the bottom.
                    RoundedRectangle(cornerRadius: WorkspaceCardMetrics.panelCornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        }
    }
}

/// A workspace snapshot filled into the card shape, or the placeholder
/// plate when the workspace was never captured.
public struct WorkspaceCardThumbnail: View {
    private let image: NSImage?

    public init(image: NSImage?) {
        self.image = image
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.07))
                Image(systemName: "macwindow")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .frame(width: WorkspaceCardMetrics.thumbSize.width, height: WorkspaceCardMetrics.thumbSize.height)
        .clipShape(RoundedRectangle(cornerRadius: WorkspaceCardMetrics.cardCornerRadius, style: .continuous))
    }
}
