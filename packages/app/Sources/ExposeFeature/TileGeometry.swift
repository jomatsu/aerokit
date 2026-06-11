import CoreGraphics

/// Shared layout constants for the overview grid; the capture pipeline uses
/// them to budget preview resolution to what the grid will actually draw.
enum TileMetrics {
    static let margin: CGFloat = 56
    static let gap: CGFloat = 28
    static let cornerRadius: CGFloat = 9
    static let labelHeight: CGFloat = 22
    static let labelSpacing: CGFloat = 10

    // Grouped mode: each app is a rounded card — header, then its tiles
    // packed tighter than the gap between cards so the clusters read.
    static let groupTileGap: CGFloat = 16
    static let groupCardPadding: CGFloat = 14
    static let groupCardCornerRadius: CGFloat = 16
    static let sectionHeaderHeight: CGFloat = 20
    static let sectionHeaderSpacing: CGFloat = 10
}

/// Pure layout math for the overview grid.
public enum TileGeometry {
    /// Size at which a window preview is drawn inside `available`: the
    /// window keeps its aspect ratio and is never shown larger than life,
    /// matching how Mission Control only ever scales windows down.
    public static func displaySize(windowPoints: CGSize?, available: CGSize) -> CGSize {
        guard let windowPoints, windowPoints.width > 0, windowPoints.height > 0 else {
            return available
        }
        let scale = min(
            available.width / windowPoints.width,
            available.height / windowPoints.height,
            1
        )
        return CGSize(width: windowPoints.width * scale, height: windowPoints.height * scale)
    }

    /// Splits a container into equally sized cells for the given grid after
    /// reserving the margins and inter-cell gaps.
    public static func cellSize(
        container: CGSize,
        grid: GridDimensions,
        gap: CGFloat,
        margin: CGFloat
    ) -> CGSize {
        let usableWidth = container.width - margin * 2 - gap * CGFloat(grid.columns - 1)
        let usableHeight = container.height - margin * 2 - gap * CGFloat(grid.rows - 1)
        return CGSize(
            width: max(1, usableWidth / CGFloat(grid.columns)),
            height: max(1, usableHeight / CGFloat(grid.rows))
        )
    }

    /// The chrome each app card adds around its tiles in grouped mode.
    public struct GroupChrome: Sendable {
        public var margin: CGFloat
        /// Between cards, and between shelf rows.
        public var groupGap: CGFloat
        /// Between tiles inside one card.
        public var tileGap: CGFloat
        public var cardPadding: CGFloat
        /// Header line plus its spacing to the tiles below.
        public var headerHeight: CGFloat

        public init(
            margin: CGFloat, groupGap: CGFloat, tileGap: CGFloat, cardPadding: CGFloat, headerHeight: CGFloat
        ) {
            self.margin = margin
            self.groupGap = groupGap
            self.tileGap = tileGap
            self.cardPadding = cardPadding
            self.headerHeight = headerHeight
        }
    }

    /// Uniform cell size for the grouped layout, with every card's padding,
    /// header, and the tighter intra-card gaps accounted for exactly. The
    /// width is set by the most crowded shelf row, the height by the total
    /// of every row's tile rows and header.
    public static func groupedCellSize(
        container: CGSize,
        layout: GroupedGridLayout,
        groupCounts: [Int],
        chrome: GroupChrome
    ) -> CGSize {
        let columns = layout.grid.columns
        var cellWidth = CGFloat.greatestFiniteMagnitude
        var fixedHeight = chrome.margin * 2 + chrome.groupGap * CGFloat(max(0, layout.rows.count - 1))
        var tileRowCount = 0

        for row in layout.rows {
            let tiles = row.reduce(0) { $0 + groupCounts[$1] }
            guard tiles > 0 else {
                continue
            }
            // Only an oversized single group wraps; its widest visual row
            // spans the full column count.
            let tileRows = max(1, (tiles + columns - 1) / columns)
            let visualColumns = min(tiles, columns)
            let widthChrome = CGFloat(row.count) * chrome.cardPadding * 2
                + CGFloat(row.count - 1) * chrome.groupGap
                + CGFloat(visualColumns - row.count) * chrome.tileGap
            let usable = container.width - chrome.margin * 2 - widthChrome
            cellWidth = min(cellWidth, usable / CGFloat(visualColumns))

            fixedHeight += chrome.cardPadding * 2 + chrome.headerHeight
                + chrome.tileGap * CGFloat(tileRows - 1)
            tileRowCount += tileRows
        }

        guard tileRowCount > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let cellHeight = (container.height - fixedHeight) / CGFloat(tileRowCount)
        return CGSize(width: max(1, cellWidth), height: max(1, cellHeight))
    }
}
