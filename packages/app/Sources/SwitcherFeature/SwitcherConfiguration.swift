import AeroKitCore
import AppKit

public struct SwitcherConfiguration: Sendable {
    public var aerospacePath: String
    public var snapshotRootPath: String
    public var snapshotRequestDirectoryPath: String
    public var snapshotRequestFilePath: String
    /// Sort priority for the switcher's workspace grid: listed names come
    /// first in this order, everything else follows in natural order. Purely
    /// cosmetic — snapshots cover whatever AeroSpace reports.
    public var workspaceOrder: [String]
    public var columns: Int
    public var maxAppIcons: Int
    public var snapshotSize: CGSize
    public var snapshotAppIconSize: CGFloat
    public var padding: CGFloat
    public var snapshotComposeSize: CGSize
    public var snapshotComposeGap: CGFloat
    public var snapshotRefreshEnabled: Bool
    public var snapshotDebounce: TimeInterval
    public var snapshotWindowSettle: TimeInterval
    public var snapshotWorkspaceSettle: TimeInterval
    public var snapshotChooserSettle: TimeInterval
    public var snapshotFailureBackoff: TimeInterval

    public init(
        aerospacePath: String = AeroSpaceClient.detectExecutablePath(),
        snapshotRootPath: String =
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/AeroKit/Workspace Snapshots",
        snapshotRequestDirectoryPath: String =
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Caches/AeroSpaceWorkspaceSnapshots",
        snapshotRequestFilePath: String =
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Caches/AeroSpaceWorkspaceSnapshots/request.tsv",
        workspaceOrder: [String] = ["1", "2", "3", "4", "Q", "W", "E", "R"],
        columns: Int = 4,
        maxAppIcons: Int = 4,
        snapshotSize: CGSize = CGSize(width: 320, height: 180),
        snapshotAppIconSize: CGFloat = 24,
        padding: CGFloat = 20,
        snapshotComposeSize: CGSize = CGSize(width: 1600, height: 900),
        snapshotComposeGap: CGFloat = 16,
        snapshotRefreshEnabled: Bool = true,
        snapshotDebounce: TimeInterval = 3.0,
        snapshotWindowSettle: TimeInterval = 5.0,
        snapshotWorkspaceSettle: TimeInterval = 3.0,
        snapshotChooserSettle: TimeInterval = 0.50,
        snapshotFailureBackoff: TimeInterval = 120.0
    ) {
        self.aerospacePath = aerospacePath
        self.snapshotRootPath = snapshotRootPath
        self.snapshotRequestDirectoryPath = snapshotRequestDirectoryPath
        self.snapshotRequestFilePath = snapshotRequestFilePath
        self.workspaceOrder = workspaceOrder
        self.columns = columns
        self.maxAppIcons = maxAppIcons
        self.snapshotSize = snapshotSize
        self.snapshotAppIconSize = snapshotAppIconSize
        self.padding = padding
        self.snapshotComposeSize = snapshotComposeSize
        self.snapshotComposeGap = snapshotComposeGap
        self.snapshotRefreshEnabled = snapshotRefreshEnabled
        self.snapshotDebounce = snapshotDebounce
        self.snapshotWindowSettle = snapshotWindowSettle
        self.snapshotWorkspaceSettle = snapshotWorkspaceSettle
        self.snapshotChooserSettle = snapshotChooserSettle
        self.snapshotFailureBackoff = snapshotFailureBackoff
    }
}
