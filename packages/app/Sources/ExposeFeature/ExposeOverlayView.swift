import AppKit
import SwiftUI

/// Full-screen Exposé overview: a frosted backdrop with the workspace's
/// windows laid out in a grid of live previews.
struct ExposeOverlayView: View {
    let session: ExposeSession
    let onActivate: (Int) -> Void
    let onHover: (Int) -> Void
    let onCancel: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            backdrop
                .opacity(appeared ? 1 : 0)

            GeometryReader { proxy in
                grid(in: proxy.size)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.17)) {
                appeared = true
            }
        }
    }

    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.32))
            .contentShape(Rectangle())
            .onTapGesture(perform: onCancel)
    }

    private func grid(in size: CGSize) -> some View {
        let cell = TileGeometry.cellSize(
            container: size,
            grid: session.grid,
            gap: TileMetrics.gap,
            margin: TileMetrics.margin
        )

        return VStack(spacing: TileMetrics.gap) {
            ForEach(rowRanges, id: \.lowerBound) { row in
                HStack(spacing: TileMetrics.gap) {
                    ForEach(row, id: \.self) { index in
                        tileView(at: index, cell: cell)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func tileView(at index: Int, cell: CGSize) -> some View {
        WindowTile(
            tile: session.tiles[index],
            shortcut: QuickSelect.label(forIndex: index),
            isSelected: index == session.selectedIndex,
            cell: cell,
            onActivate: { onActivate(index) },
            onHover: { onHover(index) }
        )
        .frame(width: cell.width, height: cell.height)
    }

    private var rowRanges: [Range<Int>] {
        stride(from: 0, to: session.tiles.count, by: session.grid.columns).map {
            $0 ..< min($0 + session.grid.columns, session.tiles.count)
        }
    }
}

private struct WindowTile: View {
    let tile: ExposeSession.Tile
    let shortcut: String?
    let isSelected: Bool
    let cell: CGSize
    let onActivate: () -> Void
    let onHover: () -> Void

    var body: some View {
        VStack(spacing: TileMetrics.labelSpacing) {
            preview
                .frame(maxHeight: .infinity)
            label
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
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
            height: cell.height - TileMetrics.labelHeight - TileMetrics.labelSpacing
        )
        let size = TileGeometry.displaySize(windowPoints: tile.pointSize, available: available)
        let shape = RoundedRectangle(cornerRadius: TileMetrics.cornerRadius, style: .continuous)

        return previewContent
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

    @ViewBuilder private var previewContent: some View {
        if let image = tile.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .transition(.opacity)
        } else {
            Rectangle()
                .fill(.white.opacity(0.07))
                .overlay {
                    if let icon = tile.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                }
        }
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
            if let icon = tile.icon {
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
