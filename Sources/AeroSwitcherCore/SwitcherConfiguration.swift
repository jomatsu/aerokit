import AppKit

public struct SwitcherConfiguration: Sendable {
    public var aerospacePath: String
    public var snapshotRootPath: String
    public var snapshotRequestDirectoryPath: String
    public var snapshotRequestFilePath: String
    public var workspaceOrder: [String]
    public var columns: Int
    public var maxAppIcons: Int
    public var snapshotSize: CGSize
    public var snapshotAppIconSize: CGFloat
    public var padding: CGFloat
    public var snapshotComposeSize: CGSize
    public var snapshotComposeGap: CGFloat
    public var snapshotRefreshEnabled: Bool
    public var snapshotRefreshOnShow: Bool
    public var snapshotDebounce: TimeInterval
    public var snapshotWindowSettle: TimeInterval
    public var snapshotWorkspaceSettle: TimeInterval
    public var snapshotChooserSettle: TimeInterval
    public var snapshotMinInterval: TimeInterval
    public var snapshotStaleInterval: TimeInterval
    public var snapshotFailureBackoff: TimeInterval

    public init(
        aerospacePath: String = "/opt/homebrew/bin/aerospace",
        snapshotRootPath: String =
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Pictures/AeroSpace Workspaces",
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
        snapshotRefreshOnShow: Bool = true,
        snapshotDebounce: TimeInterval = 3.0,
        snapshotWindowSettle: TimeInterval = 5.0,
        snapshotWorkspaceSettle: TimeInterval = 3.0,
        snapshotChooserSettle: TimeInterval = 0.50,
        snapshotMinInterval: TimeInterval = 60.0,
        snapshotStaleInterval: TimeInterval = 180.0,
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
        self.snapshotRefreshOnShow = snapshotRefreshOnShow
        self.snapshotDebounce = snapshotDebounce
        self.snapshotWindowSettle = snapshotWindowSettle
        self.snapshotWorkspaceSettle = snapshotWorkspaceSettle
        self.snapshotChooserSettle = snapshotChooserSettle
        self.snapshotMinInterval = snapshotMinInterval
        self.snapshotStaleInterval = snapshotStaleInterval
        self.snapshotFailureBackoff = snapshotFailureBackoff
    }
}
