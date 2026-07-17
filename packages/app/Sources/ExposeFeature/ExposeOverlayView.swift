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

    /// Name of the coordinate space drag locations, tile frames and chip
    /// frames all share.
    static let overlaySpace = "expose-overlay"

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
    let onMoveToWorkspace: (CGWindowID, String) -> Void

    /// In-flight tile drag; nil when the hand is off.
    @State private var drag: TileDrag?
    /// False at the grab (ghost still tile-sized), flipped with animation
    /// right after so the ghost shrinks to card size in the hand.
    @State private var ghostShrunk = false
    /// Vector from the cursor to the grabbed tile's picture center. The
    /// ghost appears exactly over the picture (cursor + offset) and the
    /// offset springs to zero with the shrink, so the picture slides under
    /// the hand instead of teleporting to it.
    @State private var ghostOffset = CGSize.zero
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var tileFrames: [CGWindowID: CGRect] = [:]

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

            bottomBar
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(motion.shown ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: motion.shown)

            if drag != nil, !session.workspaceTargets.isEmpty {
                WorkspaceDropBar(
                    targets: session.workspaceTargets,
                    previews: session.workspacePreviews,
                    disabledName: drag?.sourceWorkspace,
                    highlightedName: hoveredChipName,
                    coordinateSpace: Self.overlaySpace
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 28)
                .transition(.opacity.combined(with: .offset(y: -12)))
            }

            ghost
        }
        .coordinateSpace(name: Self.overlaySpace)
        .onPreferenceChange(ChipFramesKey.self) { chipFrames = $0 }
        .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 1), value: drag == nil)
        .ignoresSafeArea()
    }

    // MARK: - Tile drag

    /// The dragged tile's stand-in: the window picture at drop-card size,
    /// riding under the cursor while the original tile stays dimmed in
    /// place. It appears pixel-on-pixel over the tile's picture, then
    /// shrinks to the bar's card size while sliding under the hand — the
    /// window visibly becomes the thing it is about to be dropped into —
    /// and the snap-back plays the same move backwards.
    @ViewBuilder private var ghost: some View {
        if let drag, let index = session.tiles.firstIndex(where: { $0.id == drag.windowID }) {
            let tile = session.tiles[index]
            let size = ghostSize(for: tile)
            let shape = RoundedRectangle(cornerRadius: TileMetrics.cornerRadius, style: .continuous)
            let grabScale = grabScale(for: size)
            TilePreviewContent(image: tile.image, icon: tile.icon)
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .overlay {
                    // The ring is drawn at card size and scaled with the
                    // ghost, so its width is divided out at the grab to
                    // stay a constant 2pt through the shrink.
                    shape.strokeBorder(
                        Color(nsColor: .controlAccentColor),
                        lineWidth: ghostShrunk ? 2 : 2 / grabScale
                    )
                }
                .scaleEffect(ghostShrunk ? 1 : grabScale)
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                .position(drag.location)
                .offset(ghostOffset)
                .allowsHitTesting(false)
        }
    }

    /// Card-sized stand-in: aspect-fit the window into the drop bar's
    /// thumbnail box, so the ghost lands on a card at the card's own scale.
    private func ghostSize(for tile: ExposeSession.Tile) -> CGSize {
        let aspect: CGFloat = if let points = tile.pointSize, points.height > 0 {
            points.width / points.height
        } else if let image = tile.image, image.height > 0 {
            CGFloat(image.width) / CGFloat(image.height)
        } else {
            1.6
        }
        let box = WorkspaceDropBar.thumbSize
        let width = min(box.width, box.height * aspect)
        return CGSize(width: max(width, 1), height: max(width / aspect, 1))
    }

    /// Scale that blows the card-sized ghost back up to the picture's
    /// actual on-screen size — the shrink's starting point and the
    /// snap-back's destination. Matches `WindowTile`'s display math (small
    /// windows draw below the cell box), so the hand-off is pixel-exact in
    /// both directions.
    private func grabScale(for ghostSize: CGSize) -> CGFloat {
        guard let drag, let frame = tileFrames[drag.windowID], ghostSize.width > 0 else {
            return 1
        }
        let tile = session.tiles.first { $0.id == drag.windowID }
        let displayed = TileGeometry.displaySize(
            windowPoints: tile?.pointSize,
            available: CGSize(
                width: frame.width,
                height: max(TileMetrics.previewHeight(forCellHeight: frame.height), 1)
            )
        )
        return max(displayed.width / ghostSize.width, 0.01)
    }

    /// Center of the tile's picture area — the ghost's birth point and the
    /// snap-back's home. The label sits below the picture, so this is above
    /// the cell's center.
    private func previewCenter(forTileFrame frame: CGRect) -> CGPoint {
        let previewHeight = max(TileMetrics.previewHeight(forCellHeight: frame.height), 1)
        return CGPoint(x: frame.midX, y: frame.minY + previewHeight / 2)
    }

    /// The chip under the dragged tile; frames of disabled chips are never
    /// reported, so the source workspace can't light up. Slightly inflated
    /// for a forgiving drop.
    private var hoveredChipName: String? {
        guard let drag, !drag.isReturning else {
            return nil
        }
        return chipFrames.first { $0.value.insetBy(dx: -6, dy: -10).contains(drag.location) }?.key
    }

    private func dragChanged(_ value: DragGesture.Value, id: CGWindowID) {
        guard drag?.isReturning != true else {
            return
        }
        if drag == nil {
            // No workspaces to drop on — don't start a drag that can only
            // snap back. The tile is resolved by window id, not index: the
            // keyboard stays live under a mouse-down, and a ⌘W/⇧digit
            // re-flow must not hand the drag a different window.
            guard !session.workspaceTargets.isEmpty,
                  let tile = session.tiles.first(where: { $0.id == id })
            else {
                return
            }
            drag = TileDrag(
                windowID: tile.id,
                sourceWorkspace: tile.window.workspace,
                location: value.location
            )
            // The ghost is born exactly over the tile's picture, wherever
            // the hand grabbed it…
            ghostShrunk = false
            ghostOffset = tileFrames[tile.id].map { frame in
                let center = previewCenter(forTileFrame: frame)
                return CGSize(width: center.x - value.location.x, height: center.y - value.location.y)
            } ?? .zero
            // …and a runloop turn later — after its first tile-sized frame
            // — it shrinks to card size while sliding under the cursor.
            // Not onAppear: re-grabbing while the previous ghost's exit is
            // still in flight reuses the view, and a skipped onAppear left
            // the ghost stuck at full size.
            Task { @MainActor in
                withAnimation(.spring(response: 0.32, dampingFraction: 1)) {
                    ghostShrunk = true
                    ghostOffset = .zero
                }
            }
        } else {
            drag?.location = value.location
        }
    }

    private func dragEnded() {
        guard let drag, !drag.isReturning else {
            return
        }
        if let target = hoveredChipName {
            self.drag = nil
            ghostShrunk = false
            ghostOffset = .zero
            onMoveToWorkspace(drag.windowID, target)
        } else {
            snapBack()
        }
    }

    /// Dropped on nothing: the ghost flies home and grows back to tile
    /// size, then the original tile takes over.
    private func snapBack() {
        guard let id = drag?.windowID, let frame = tileFrames[id] else {
            drag = nil
            ghostShrunk = false
            ghostOffset = .zero
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 1), completionCriteria: .logicallyComplete) {
            drag?.isReturning = true
            ghostShrunk = false
            // Home is the picture's center, not the cell's — the label
            // sits below the picture the ghost grows back into.
            ghostOffset = .zero
            drag?.location = previewCenter(forTileFrame: frame)
        } completion: {
            drag = nil
        }
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

    /// Raycast-style action bar along the bottom edge: the grouping toggle
    /// (when its hint is on) next to the close shortcut.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            if showsGroupingHint {
                groupingHintBar
            }
            closeHintBar
        }
        .padding(.bottom, 14)
    }

    /// The grouping action's name next to its keycap, clickable as a
    /// fallback for the key. The label follows the session so it always
    /// names what pressing the key would do next.
    private var groupingHintBar: some View {
        Button(action: onToggleGrouping) {
            hintCapsule(
                session.isGroupedByApp ? "Ungroup" : "Group by App",
                key: String(quickSelectExclusion ?? "0")
            )
        }
        .buttonStyle(.plain)
    }

    private var closeHintBar: some View {
        hintCapsule("Close", key: "⌘W")
    }

    /// Raycast-style hint chrome shared by every bottom-bar action: the
    /// action's name next to its keycap in a dark capsule.
    private func hintCapsule(_ title: String, key: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            keycap(key)
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

    @ViewBuilder
    private func grid(in size: CGSize) -> some View {
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
                        ForEach(slots(in: row)) { slot in
                            tileView(at: slot.index, cell: cell)
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
                    ForEach(slots(in: row)) { slot in
                        tileView(at: slot.index, cell: cell)
                    }
                }
            }
        }
    }

    /// A row's tiles identified by window id, not position, so a removal
    /// re-flows the survivors instead of rewriting every tile in place.
    private func slots(in row: some Sequence<Int>) -> [TileSlot] {
        row.compactMap { index in
            session.tiles.indices.contains(index)
                ? TileSlot(index: index, id: session.tiles[index].id)
                : nil
        }
    }

    private func tileView(at index: Int, cell: CGSize) -> some View {
        let tile = session.tiles[index]
        return WindowTile(
            tile: tile,
            shortcut: QuickSelect.label(forIndex: index, excluding: quickSelectExclusion),
            isSelected: index == session.selectedIndex,
            cell: cell,
            showsLabelIcon: !session.isGroupedByApp,
            onActivate: { onActivate(index) },
            // The cursor sweeping the grid mid-drag must not fight the
            // selection ring.
            onHover: { if drag == nil { onHover(index) } },
            onDragChanged: { value in dragChanged(value, id: tile.id) },
            onDragEnded: { _ in dragEnded() }
        )
        .opacity(drag?.windowID == tile.id ? 0.2 : 1)
        .background(GeometryReader { proxy in
            Color.clear.preference(
                key: TileFramesKey.self,
                value: [tile.id: proxy.frame(in: .named(Self.overlaySpace))]
            )
        })
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .frame(width: cell.width, height: cell.height)
    }
}

/// A window's picture, or its app icon on a dim plate while the capture is
/// still on its way. Shared by the grid tiles and the drag ghost — the
/// ghost is the tile's stand-in, so the two must never drift apart.
private struct TilePreviewContent: View {
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

/// A tile's place in a row: `index` addresses the session, `id` is the
/// window — the stable identity SwiftUI animates re-flows by.
private struct TileSlot: Identifiable {
    let index: Int
    let id: CGWindowID
}

/// In-flight tile drag state.
private struct TileDrag {
    let windowID: CGWindowID
    /// The dragged window's own workspace; its chip is disabled.
    let sourceWorkspace: String
    /// Cursor location in the overlay coordinate space; the snap-back
    /// animates this home.
    var location: CGPoint
    /// True while the ghost is flying back after a missed drop; input is
    /// ignored until it lands.
    var isReturning = false
}

/// Tile frames in the overlay coordinate space, keyed by window id; the
/// snap-back's destination.
private struct TileFramesKey: PreferenceKey {
    static let defaultValue: [CGWindowID: CGRect] = [:]

    static func reduce(value: inout [CGWindowID: CGRect], nextValue: () -> [CGWindowID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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
