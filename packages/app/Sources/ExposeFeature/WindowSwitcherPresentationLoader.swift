import AeroKitCore
import CoreGraphics
import Foundation

/// Off-main queries for one window-switcher strip. Unlike exposé, the
/// snapshot, focused window, and WindowServer reads share a single
/// BlockingWork hop — they are independent of each other only after the
/// workspace listing succeeds, and none of them should pin the cooperative
/// pool.
enum WindowSwitcherPresentationLoader {
    /// Everything the presentation needs from off-main queries: two CLI
    /// round trips plus the synchronous WindowServer ones.
    struct PresentationContext: Sendable {
        var snapshot: WorkspaceSnapshot
        var focusedID: CGWindowID?
        var stacking: [CGWindowID]
        var bounds: [CGWindowID: CGRect]
    }

    static func load(
        client: AeroSpaceClient,
        stacking: @escaping @Sendable () -> [CGWindowID],
        bounds: @escaping @Sendable () -> [CGWindowID: CGRect]
    ) async -> PresentationContext? {
        await BlockingWork.run {
            guard let snapshot = try? client.focusedWorkspaceWindows(), !snapshot.windows.isEmpty else {
                return nil
            }
            return PresentationContext(
                snapshot: snapshot,
                focusedID: client.focusedWindow()?.id,
                stacking: stacking(),
                bounds: bounds()
            )
        }
    }
}
