import AppKit
import SwiftUI

/// Full-screen Exposé overview: a frosted backdrop with the workspace's
/// windows laid out in a grid of live previews.
///
/// The motion is a row cascade keyed to the opening gesture: each grid row
/// rises a short distance into place, and the rows take off in the
/// gesture's order — swipe up and the wave runs bottom-to-top, swipe down
/// and it runs top-to-bottom. Direction comes from choreography, not from
/// shoving the whole grid around, so it reads instantly without ever
/// looking like a slide transition. Raycast restraint everywhere else:
/// short travel, critically damped springs, and a dismissal that is a
/// single fast fade — exits answer to the hand, they don't perform.
struct ExposeOverlayView: View {
    /// How long the exit animation runs; the panel stays up exactly this
    /// long after `motion.shown` flips off.
    static let exitMilliseconds = 120

    /// How far a row rises (or descends) into place. Big enough to read
    /// from across the room — a one-row workspace gets no stagger, so the
    /// travel alone has to carry the direction.
    private static let rowTravel: CGFloat = 52
    /// Take-off delay between consecutive rows; the whole wave stays well
    /// under the time a hand needs to leave the trackpad.
    private static let rowStagger: Double = 0.04

    let session: ExposeSession
    let motion: ExposeOverlayMotion
    /// The grouping-toggle key, skipped by the quick-select labels.
    let quickSelectExclusion: Character?
    /// Whether the bottom bar advertises the grouping-toggle key; off for
    /// the app scope (no grouping there) and via the preference.
    let showsGroupingHint: Bool
    let onActivate: (Int) -> Void
    let onHover: (Int) -> Void
    let onCancel: () -> Void
    let onToggleGrouping: () -> Void

    var body: some View {
        ZStack {
            // Keyed to `veiled`, not `shown`: the dim answers the gesture
            // the moment the panel is up, while the grid waits for its
            // pictures — the screen never feels like it ignored the hand.
            backdrop
                .opacity(motion.veiled ? 1 : 0)
                .animation(
                    .easeOut(duration: motion.veiled ? 0.16 : Double(Self.exitMilliseconds) / 1000),
                    value: motion.veiled
                )

            GeometryReader { proxy in
                grid(in: proxy.size)
            }

            if showsGroupingHint {
                groupingHintBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(motion.shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: motion.shown)
            }
        }
        .ignoresSafeArea()
    }

    /// The cascade, applied per visual row: a rise (or descent) with a
    /// critically damped spring, taking off `rank` rows after the row at
    /// the gesture's edge. The fade finishes well before the travel does,
    /// so most of the distance is covered at full opacity — that's what
    /// makes the direction legible at a glance. Dismissal drops the
    /// choreography — every row fades together, as fast as the panel goes
    /// away.
    private func cascade(rank: Int, of count: Int, content: some View) -> some View {
        let order = motion.edge == .bottom ? count - 1 - rank : rank
        let delay = Double(order) * Self.rowStagger
        let hiddenOffset: CGFloat = motion.edge == .bottom ? Self.rowTravel : -Self.rowTravel
        let exit: Animation = .easeOut(duration: Double(Self.exitMilliseconds) / 1000)
        return content
            .opacity(motion.shown ? 1 : 0)
            .animation(
                motion.shown ? .easeOut(duration: 0.13).delay(delay) : exit,
                value: motion.shown
            )
            .offset(y: motion.shown ? 0 : hiddenOffset)
            .animation(
                motion.shown
                    ? .spring(response: 0.32, dampingFraction: 1).delay(delay)
                    : exit,
                value: motion.shown
            )
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

        let rows = session.rowRanges(in: 0 ..< session.tiles.count)
        return VStack(spacing: TileMetrics.gap) {
            ForEach(Array(rows.enumerated()), id: \.element.lowerBound) { rank, row in
                cascade(
                    rank: rank,
                    of: rows.count,
                    content:
                    HStack(spacing: TileMetrics.gap) {
                        ForEach(row, id: \.self) { index in
                            tileView(at: index, cell: cell)
                        }
                    }
                )
            }
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

        // Shelf rows are the cascade unit here; a card's inner rows arrive
        // with their card, keeping each app's windows one visual piece.
        return VStack(spacing: TileMetrics.gap) {
            ForEach(Array(sectionRows.enumerated()), id: \.offset) { rank, row in
                cascade(
                    rank: rank,
                    of: sectionRows.count,
                    content:
                    HStack(alignment: .top, spacing: TileMetrics.gap) {
                        ForEach(row, id: \.self) { sectionIndex in
                            groupCard(sections[sectionIndex], cell: cell)
                        }
                    }
                )
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
