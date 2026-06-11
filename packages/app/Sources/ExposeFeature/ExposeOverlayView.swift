import AppKit
import SwiftUI

/// Full-screen Exposé overview: a frosted backdrop with the workspace's
/// windows laid out in a grid of live previews.
struct ExposeOverlayView: View {
    let session: ExposeSession
    /// The grouping-toggle key, skipped by the quick-select labels.
    let quickSelectExclusion: Character?
    /// Whether the bottom bar advertises the grouping-toggle key; off for
    /// the app scope (no grouping there) and via the preference.
    let showsGroupingHint: Bool
    let onActivate: (Int) -> Void
    let onHover: (Int) -> Void
    let onCancel: () -> Void
    let onToggleGrouping: () -> Void

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

            if showsGroupingHint {
                groupingHintBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(appeared ? 1 : 0)
            }
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

    /// Raycast-style action bar: the grouping action's name next to its
    /// keycap, clickable as a fallback for the key. The label follows the
    /// session so it always names what pressing the key would do next.
    private var groupingHintBar: some View {
        Button(action: onToggleGrouping) {
            HStack(spacing: 8) {
                Text(session.isGroupedByApp ? "Ungroup" : "Group by App")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                keycap(String(quickSelectExclusion ?? "0"))
            }
            .padding(.leading, 13)
            .padding(.trailing, 9)
            .frame(height: 34)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
    }

    private func keycap(_ label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4.5, style: .continuous)
        return Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .frame(minWidth: 18)
            .frame(height: 18)
            .background(.white.opacity(0.14), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
    }

    @ViewBuilder private func grid(in size: CGSize) -> some View {
        if let sections = session.sections, let sectionRows = session.sectionRows {
            groupedGrid(sections: sections, sectionRows: sectionRows, in: size)
        } else {
            flatGrid(in: size)
        }
    }

    private func flatGrid(in size: CGSize) -> some View {
        let cell = TileGeometry.cellSize(
            container: size,
            grid: session.grid,
            gap: TileMetrics.gap,
            margin: TileMetrics.margin
        )

        return VStack(spacing: TileMetrics.gap) {
            tileRows(in: 0 ..< session.tiles.count, gap: TileMetrics.gap, cell: cell)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Grouped (app cards)

    private func groupedGrid(
        sections: [ExposeSession.Section],
        sectionRows: [[Int]],
        in size: CGSize
    ) -> some View {
        let cell = TileGeometry.groupedCellSize(
            container: size,
            layout: GroupedGridLayout(grid: session.grid, rows: sectionRows),
            groupCounts: sections.map(\.tileRange.count),
            chrome: TileGeometry.GroupChrome(
                margin: TileMetrics.margin,
                groupGap: TileMetrics.gap,
                tileGap: TileMetrics.groupTileGap,
                cardPadding: TileMetrics.groupCardPadding,
                headerHeight: TileMetrics.sectionHeaderHeight + TileMetrics.sectionHeaderSpacing
            )
        )

        return VStack(spacing: TileMetrics.gap) {
            ForEach(sectionRows, id: \.first) { row in
                HStack(alignment: .top, spacing: TileMetrics.gap) {
                    ForEach(row, id: \.self) { sectionIndex in
                        groupCard(sections[sectionIndex], cell: cell)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func groupCard(_ section: ExposeSession.Section, cell: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: TileMetrics.groupCardCornerRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: TileMetrics.sectionHeaderSpacing) {
            sectionHeader(section)
            tileRows(in: section.tileRange, gap: TileMetrics.groupTileGap, cell: cell)
        }
        .padding(TileMetrics.groupCardPadding)
        .background {
            shape
                .fill(.white.opacity(0.05))
                .overlay {
                    shape.strokeBorder(.white.opacity(0.09), lineWidth: 1)
                }
        }
    }

    private func sectionHeader(_ section: ExposeSession.Section) -> some View {
        HStack(spacing: 6) {
            if let icon = section.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(section.appName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            if section.tileRange.count > 1 {
                Text("\(section.tileRange.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(.white.opacity(0.12), in: Capsule())
            }
        }
        .frame(height: TileMetrics.sectionHeaderHeight)
        .padding(.leading, 2)
    }

    private func tileRows(in range: Range<Int>, gap: CGFloat, cell: CGSize) -> some View {
        VStack(spacing: gap) {
            ForEach(session.rowRanges(in: range), id: \.lowerBound) { row in
                HStack(spacing: gap) {
                    ForEach(row, id: \.self) { index in
                        tileView(at: index, cell: cell)
                    }
                }
            }
        }
    }

    private func tileView(at index: Int, cell: CGSize) -> some View {
        WindowTile(
            tile: session.tiles[index],
            shortcut: QuickSelect.label(forIndex: index, excluding: quickSelectExclusion),
            isSelected: index == session.selectedIndex,
            cell: cell,
            showsLabelIcon: !session.isGroupedByApp,
            onActivate: { onActivate(index) },
            onHover: { onHover(index) }
        )
        .frame(width: cell.width, height: cell.height)
    }
}

private struct WindowTile: View {
    let tile: ExposeSession.Tile
    let shortcut: String?
    let isSelected: Bool
    let cell: CGSize
    /// Off inside an app card, where the header already shows the icon.
    let showsLabelIcon: Bool
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
