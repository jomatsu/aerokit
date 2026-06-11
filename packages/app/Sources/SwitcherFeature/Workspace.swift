import AeroKitCore

public struct Workspace: Equatable, Sendable {
    public var name: String
    public var apps: [WorkspaceApp]
    public var isFocused: Bool
    public var isEmpty: Bool

    public init(name: String, apps: [WorkspaceApp], isFocused: Bool, isEmpty: Bool) {
        self.name = name
        self.apps = apps
        self.isFocused = isFocused
        self.isEmpty = isEmpty
    }
}
