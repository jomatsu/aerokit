import AeroKitCore
import AppKit
import Foundation

private let log = AppLog(category: "swipe")

/// Blocking AeroSpace listing plus HUD asset resolution for a swipe. The
/// controller owns gesture lifetime, commit serialization, and HUD effects;
/// this type owns the round trips that fill the ring, thumbnails, and icons.
struct SwipeWorkspaceLoader: Sendable {
    /// The focused monitor's workspaces resolved when the gesture began.
    struct Ring: Equatable, Sendable {
        var workspaces: [String]
        var current: String
    }

    /// Sendable carriers for values loaded off the main actor: the AppKit
    /// images are handed to the main actor exactly once and never mutated
    /// afterwards. Required because NSImage itself is not Sendable, and the
    /// macOS 26 SDK checks every BlockingWork boundary.
    struct LoadedRing: @unchecked Sendable {
        var ring: Ring?
        var previews: [String: NSImage]
    }

    struct LoadedIcons: @unchecked Sendable {
        var icons: [String: [NSImage]]
    }

    /// Blocking CLI round trips; the caller runs it on BlockingWork. Returns
    /// nil (logged) when AeroSpace is unreachable or reports no usable
    /// workspace.
    func loadRing(client: AeroSpaceClient, skipEmpty: Bool, order: [String]) -> Ring? {
        do {
            let workspaces = try client.workspacesOnFocusedMonitor(includeEmpty: !skipEmpty)
            // Skipping empty workspaces can drop the focused one (it may
            // itself be empty), so fall back to asking for it directly.
            guard let current = try workspaces.first(where: \.isFocused)?.name
                ?? client.focusedWorkspaceName()
            else {
                return nil
            }
            let ring = SwipeNavigation.ring(
                current: current,
                workspaces: workspaces.map(\.name),
                priority: order
            )
            log.notice("swipe ring: \(ring.joined(separator: " → ")) (current: \(current))")
            return Ring(workspaces: ring, current: current)
        } catch {
            log.error("swipe workspace listing failed: \(error)")
            return nil
        }
    }

    /// The store caches decoded thumbnails, so this is disk-bound once per
    /// snapshot refresh at most — but that cold decode belongs here, off the
    /// main actor, not under the HUD's first animation frame.
    func loadPreviews(
        workspaces: [String],
        preview: (String) -> NSImage?
    ) -> [String: NSImage] {
        workspaces.reduce(into: [String: NSImage]()) { $0[$1] = preview($1) }
    }

    /// Blocking CLI round trip plus icon resolution; the caller runs it on
    /// BlockingWork. One `list-windows --all` covers every workspace —
    /// icon-less cards are better than serializing a call per workspace.
    func loadIcons(
        client: AeroSpaceClient,
        icon: (WorkspaceApp) -> NSImage?
    ) -> [String: [NSImage]] {
        do {
            return try Dictionary(grouping: client.listWindows(), by: \.workspace)
                .mapValues { windows in
                    WorkspaceApp.uniqueApps(from: windows).compactMap(icon)
                }
        } catch {
            log.error("swipe window listing failed: \(error)")
            return [:]
        }
    }
}

/// Async surface the controller awaits. Production hops through BlockingWork;
/// tests substitute a continuation-gated fake so load order is controllable.
protocol SwipeWorkspaceLoading: Sendable {
    func loadRingAndPreviews(
        client: AeroSpaceClient,
        skipEmpty: Bool,
        order: [String],
        includePreviews: Bool,
        preview: @escaping @Sendable (String) -> NSImage?
    ) async -> SwipeWorkspaceLoader.LoadedRing

    func loadIcons(
        client: AeroSpaceClient,
        icon: @escaping @Sendable (WorkspaceApp) -> NSImage?
    ) async -> SwipeWorkspaceLoader.LoadedIcons
}

extension SwipeWorkspaceLoader: SwipeWorkspaceLoading {
    func loadRingAndPreviews(
        client: AeroSpaceClient,
        skipEmpty: Bool,
        order: [String],
        includePreviews: Bool,
        preview: @escaping @Sendable (String) -> NSImage?
    ) async -> LoadedRing {
        await BlockingWork.run { () -> LoadedRing in
            guard let ring = loadRing(client: client, skipEmpty: skipEmpty, order: order) else {
                return LoadedRing(ring: nil, previews: [:])
            }
            let previews = includePreviews
                ? loadPreviews(workspaces: ring.workspaces, preview: preview)
                : [:]
            return LoadedRing(ring: ring, previews: previews)
        }
    }

    func loadIcons(
        client: AeroSpaceClient,
        icon: @escaping @Sendable (WorkspaceApp) -> NSImage?
    ) async -> LoadedIcons {
        await BlockingWork.run {
            LoadedIcons(icons: loadIcons(client: client, icon: icon))
        }
    }
}
