public struct WorkspaceWindow: Equatable, Sendable {
    public var id: String
    public var bundleIdentifier: String
    public var appName: String
    public var workspace: String
    public var title: String
    public var layout: String
    public var parentContainerLayout: String
    public var workspaceRootContainerLayout: String

    public init(
        id: String,
        bundleIdentifier: String,
        appName: String,
        workspace: String,
        title: String,
        layout: String = "",
        parentContainerLayout: String = "",
        workspaceRootContainerLayout: String = ""
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.workspace = workspace
        self.title = title
        self.layout = layout
        self.parentContainerLayout = parentContainerLayout
        self.workspaceRootContainerLayout = workspaceRootContainerLayout
    }
}
