import Foundation

/// Distributed notifications so a second invocation of the binary (e.g.
/// `AeroKit --toggle-expose` from an AeroSpace keybinding) can talk to the
/// running instance.
public enum AeroKitNotification {
    public static let openSettings = Notification.Name("com.nasubikun.aerokit.open-settings")
    public static let toggleExpose = Notification.Name("com.nasubikun.aerokit.toggle-expose")
    public static let toggleAppExpose = Notification.Name("com.nasubikun.aerokit.toggle-app-expose")
    /// Posted by a `--workspace-changed` invocation (wired through
    /// AeroSpace's exec-on-workspace-change hook) so the running instance
    /// can flash the swipe HUD for workspace switches it didn't perform
    /// itself — the user's own keybindings, CLI switches, other automation.
    public static let workspaceChanged = Notification.Name("com.nasubikun.aerokit.workspace-changed")
}
