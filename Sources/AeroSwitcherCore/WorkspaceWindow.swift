public struct WorkspaceWindow: Equatable, Sendable {
    public var id: String
    public var bundleIdentifier: String
    public var appName: String
    public var workspace: String
    public var title: String

    public init(id: String, bundleIdentifier: String, appName: String, workspace: String, title: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.workspace = workspace
        self.title = title
    }
}
