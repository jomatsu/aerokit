import AppKit
import SwiftUI

struct WindowTile: View {
    let tile: ExposeSession.Tile
    let shortcut: String?
    let isSelected: Bool
    let cell: CGSize
    /// Off inside an app card, where the header already shows the icon.
    let showsLabelIcon: Bool
    let onActivate: () -> Void
    let onHover: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: TileMetrics.labelSpacing) {
            preview
                .frame(maxHeight: .infinity)
            label
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        // The minimum distance keeps plain clicks on the tap gesture.
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(ExposeOverlayView.overlaySpace))
                .onChanged(onDragChanged)
                .onEnded(onDragEnded)
        )
        .onHover { hovering in
            if hovering {
                onHover()
            }
        }
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var preview: some View {
        let available = CGSize(
            width: cell.width,
            height: TileMetrics.previewHeight(forCellHeight: cell.height)
        )
        let size = TileGeometry.displaySize(windowPoints: tile.pointSize, available: available)
        let shape = RoundedRectangle(cornerRadius: TileMetrics.cornerRadius, style: .continuous)

        return TilePreviewContent(image: tile.image, icon: tile.icon)
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            .overlay {
                shape.strokeBorder(
                    isSelected ? Color(nsColor: .controlAccentColor) : .white.opacity(0.12),
                    lineWidth: isSelected ? 3 : 1
                )
            }
            .overlay(alignment: .topLeading) {
                shortcutBadge
            }
            .animation(.easeOut(duration: 0.15), value: tile.image == nil)
    }

    /// Raycast-style keycap hint: a small rounded square, not a numbered
    /// circle, so it reads as "the key to press".
    @ViewBuilder private var shortcutBadge: some View {
        if let shortcut {
            let shape = RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            Text(shortcut)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .frame(minWidth: 18)
                .frame(height: 18)
                .background(.black.opacity(0.45), in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
                .padding(7)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if showsLabelIcon, let icon = tile.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(tile.window.displayTitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: TileMetrics.labelHeight)
        .frame(maxWidth: cell.width * 0.92)
    }
}
