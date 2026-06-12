public struct WorkspaceApp: Hashable, Sendable {
    public var name: String
    public var bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier?.isEmpty == true ? nil : bundleIdentifier
    }

    /// The distinct apps among `windows`, in window order. Keyed by bundle
    /// id (app name when missing) so one app under two display names stays
    /// one entry — every feature listing a workspace's apps must agree on
    /// this.
    public static func uniqueApps(from windows: [WorkspaceWindow]) -> [WorkspaceApp] {
        var seen = Set<String>()
        var apps: [WorkspaceApp] = []

        for window in windows {
            let key = window.bundleIdentifier.isEmpty ? window.appName : window.bundleIdentifier
            guard seen.insert(key).inserted else {
                continue
            }
            apps.append(WorkspaceApp(name: window.appName, bundleIdentifier: window.bundleIdentifier))
        }

        return apps
    }
}
