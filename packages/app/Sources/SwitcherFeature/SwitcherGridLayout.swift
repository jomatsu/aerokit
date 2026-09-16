import AppKit

/// Fits cards to the display while preserving preview aspect ratio. Very
/// large workspace collections scroll instead of shrinking to unreadable cards.
struct SwitcherGridLayout {
    static let titleHeight: CGFloat = 76

    let columns: Int
    let snapshotSize: CGSize
    let panelSize: CGSize

    init(
        available: CGSize,
        count: Int,
        columns requestedColumns: Int,
        configuration: SwitcherConfiguration,
        fullscreen: Bool,
        showTitles: Bool,
        showHints: Bool
    ) {
        columns = max(1, min(requestedColumns, max(1, count)))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let padding = configuration.padding
        let bounds = CGSize(
            width: max(1, available.width - (fullscreen ? 0 : 32)),
            height: max(1, available.height - (fullscreen ? 0 : 32))
        )
        let chrome: CGFloat = 42 + (showHints ? 38 : 0)
        let metadata = configuration.snapshotAppIconSize + 36 + (showTitles ? Self.titleHeight : 0)
        let aspect = configuration.snapshotSize.width / max(1, configuration.snapshotSize.height)
        let widthLimit = max(1, (bounds.width - CGFloat(columns + 1) * padding - 8) / CGFloat(columns))
        let heightLimit = max(56, (bounds.height - chrome - CGFloat(rows + 1) * padding) / CGFloat(rows) - metadata)
        let width = fullscreen
            ? min(widthLimit, heightLimit * aspect)
            : min(widthLimit, configuration.snapshotSize.width)
        snapshotSize = CGSize(width: width, height: width / aspect)
        panelSize = fullscreen ? bounds : CGSize(
            width: width * CGFloat(columns) + CGFloat(columns + 1) * padding + 8,
            height: min(
                bounds.height,
                CGFloat(rows) * (snapshotSize.height + metadata)
                    + CGFloat(rows + 1) * padding + chrome
            )
        )
    }
}
