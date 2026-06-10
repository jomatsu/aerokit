public enum SnapshotReason: String, Sendable {
    case chooserShow = "chooser-show"
    case workspaceChange = "workspace-change"
    case windowDetected = "window-detected"
    case request
}
