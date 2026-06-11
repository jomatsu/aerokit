public struct WorkspaceApp: Hashable, Sendable {
    public var name: String
    public var bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier?.isEmpty == true ? nil : bundleIdentifier
    }
}
