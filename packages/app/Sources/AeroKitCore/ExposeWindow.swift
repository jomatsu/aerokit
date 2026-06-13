import CoreGraphics

/// A window of the focused workspace as reported by the AeroSpace CLI.
public struct ExposeWindow: Equatable, Sendable, Identifiable {
    public var id: CGWindowID
    public var bundleIdentifier: String
    public var appName: String
    public var title: String
    /// Hosting workspace name; empty when unknown (older aerospace builds).
    /// App exposé spans workspaces, so each window carries its own.
    public var workspace: String

    public init(id: CGWindowID, bundleIdentifier: String, appName: String, title: String, workspace: String = "") {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.workspace = workspace
    }

    /// User-facing label: the window title when present, the app name otherwise.
    public var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
