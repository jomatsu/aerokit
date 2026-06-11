import Foundation

/// Distributed notifications so a second invocation of the binary (e.g.
/// `AeroKit --toggle-expose` from an AeroSpace keybinding) can talk to the
/// running instance.
public enum AeroKitNotification {
    public static let openSettings = Notification.Name("com.nasubikun.aerokit.open-settings")
    public static let toggleExpose = Notification.Name("com.nasubikun.aerokit.toggle-expose")
}
