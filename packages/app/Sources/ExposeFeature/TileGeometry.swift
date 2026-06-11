import CoreGraphics

/// Shared layout constants for the overview grid; the capture pipeline uses
/// them to budget preview resolution to what the grid will actually draw.
enum TileMetrics {
    static let margin: CGFloat = 56
    static let gap: CGFloat = 28
    static let cornerRadius: CGFloat = 9
    static let labelHeight: CGFloat = 22
    static let labelSpacing: CGFloat = 10
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
}
