import AppKit

public struct WorkspacePresentation: Identifiable {
    public var id: String {
        workspace.name
    }

    public var workspace: Workspace
    public var snapshot: NSImage?
    public var appIcons: [NSImage]

    public init(workspace: Workspace, snapshot: NSImage?, appIcons: [NSImage]) {
        self.workspace = workspace
        self.snapshot = snapshot
        self.appIcons = appIcons
    }
}
