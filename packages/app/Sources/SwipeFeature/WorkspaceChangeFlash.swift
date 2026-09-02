import AeroKitCore
import Foundation

/// Policy for flashing the swipe HUD on workspace changes AeroKit didn't
/// perform — the user's own AeroSpace keybindings, CLI switches, or other
/// automation, surfaced by the optional `exec-on-workspace-change` hook.
/// The controller applies it; tests pin it.
public enum WorkspaceChangeFlash {
    /// How long after one of AeroKit's own swipe commits the hook's report
    /// of that same switch is ignored: the commit already settled the HUD
    /// onto the new workspace, and the hook's echo arrives one process
    /// spawn plus a distributed notification later — which after a cold
    /// app launch can approach a second. A genuine keyboard switch this
    /// soon after a swipe loses its flash, but the strip is by then still
    /// showing the swipe's outcome — the state on screen is the same
    /// either way.
    public static let ownCommitSuppression: Duration = .milliseconds(1000)

    /// The hook must not double-show the strip for a switch the swipe HUD
    /// is already displaying: a gesture in flight owns the panel
    /// interactively, and a just-committed swipe already settled it.
    public static func shouldShow(
        gestureActive: Bool,
        lastOwnCommit: ContinuousClock.Instant?,
        now: ContinuousClock.Instant
    ) -> Bool {
        guard !gestureActive else {
            return false
        }
        guard let lastOwnCommit else {
            return true
        }
        return now - lastOwnCommit > ownCommitSuppression
    }

    /// The `~/.aerospace.toml` line that surfaces every workspace change to
    /// the running AeroKit: AeroSpace spawns the CLI with the new and
    /// previous workspace in the environment, the CLI posts a distributed
    /// notification, and the app flashes the strip.
    public static func tomlSnippet(executablePath: String) -> String {
        WorkspaceChangeHook.hookLine(executablePath: executablePath)
    }
}
