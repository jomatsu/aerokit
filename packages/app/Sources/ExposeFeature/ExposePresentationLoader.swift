import AeroKitCore
import AppKit
import CoreGraphics
import Foundation

private let log = AppLog(category: "expose")

/// Off-main queries that fill one exposé presentation: workspace vs app
/// listings have different CLI dependencies, so they stay as two paths
/// rather than one generic loader.
enum ExposePresentationLoader {
    /// Everything the presentation needs from off-main queries: the
    /// workspace's windows, the focused window, and all window bounds.
    /// `@unchecked` because the preview/icon images are AppKit objects:
    /// the context is built inside one nonisolated call, handed to the
    /// main actor exactly once, and never mutated afterwards.
    struct PresentationContext: @unchecked Sendable {
        var snapshot: WorkspaceSnapshot
        var focusedWindowID: CGWindowID?
        var bounds: [CGWindowID: CGRect]
        var workspaceTargets: [WorkspaceTarget] = []
        var workspacePreviews: [String: NSImage] = [:]
    }

    /// The drop bar's workspaces and their snapshot previews (workspaces
    /// the switcher has not snapshotted yet simply get a placeholder).
    /// Empty (logged) on CLI failure — the overlay shows no drop bar.
    /// `@unchecked` for the AppKit images: built inside one nonisolated
    /// call, consumed once on the main actor, never mutated.
    struct DropBarContent: @unchecked Sendable {
        var targets: [WorkspaceTarget]
        var previews: [String: NSImage]
    }

    static func workspaceContext(
        client: AeroSpaceClient,
        windowBounds: @escaping @Sendable () -> [CGWindowID: CGRect],
        preview: @escaping @Sendable (String) -> NSImage?
    ) async -> PresentationContext? {
        // The focused-window query only seeds the initial selection, and
        // the drop-bar content is invisible until a drag starts, so both
        // run concurrently instead of paying extra CLI round trips before
        // the overlay can show. Each blocking round trip hops to BlockingWork
        // so the overlap happens on the GCD pool, not the cooperative one.
        async let focused = BlockingWork.run { client.focusedWindow() }
        async let dropBar = BlockingWork.run {
            loadDropBarContent(preview: preview) {
                try client.workspacesOnFocusedMonitor(includeEmpty: true)
            }
        }
        guard let snapshot = await BlockingWork.run({
            loadSnapshot("workspace") { try client.focusedWorkspaceWindows() }
        }) else {
            return nil
        }
        return await PresentationContext(
            snapshot: snapshot,
            focusedWindowID: focused?.id,
            bounds: windowBounds(),
            workspaceTargets: dropBar.targets,
            workspacePreviews: dropBar.previews
        )
    }

    /// The CLI calls are sequential by necessity — the focused window's app
    /// determines which windows to list.
    static func appContext(
        client: AeroSpaceClient,
        windowBounds: @escaping @Sendable () -> [CGWindowID: CGRect],
        preview: @escaping @Sendable (String) -> NSImage?
    ) async -> PresentationContext? {
        // The bounds query talks to the WindowServer, not the CLI, so it can
        // overlap the dependent CLI round trips; the drop-bar content is
        // invisible until a drag starts, so it loads concurrently too. The
        // CLI round trips hop to BlockingWork; the WindowServer query stays
        // on the cooperative pool because it can't wedge the way the CLI can.
        async let bounds = windowBounds()
        // The app's windows span monitors, so every workspace is a valid
        // drop target.
        async let dropBar = BlockingWork.run {
            loadDropBarContent(preview: preview) { try client.listWorkspaces() }
        }
        guard let focused = await BlockingWork.run({ client.focusedWindow() }) else {
            log.error("app exposé: no focused window")
            return nil
        }
        guard var snapshot = await BlockingWork.run({
            loadSnapshot("app") {
                try client.appWindows(bundleIdentifier: focused.bundleIdentifier, pid: focused.pid)
            }
        }) else {
            return nil
        }
        // The app's windows can span monitors; the overlay belongs on the
        // one hosting the focused window.
        snapshot.screenNumber = focused.screenNumber ?? snapshot.screenNumber
        return await PresentationContext(
            snapshot: snapshot,
            focusedWindowID: focused.id,
            bounds: bounds,
            workspaceTargets: dropBar.targets,
            workspacePreviews: dropBar.previews
        )
    }

    static func loadDropBarContent(
        preview: @Sendable (String) -> NSImage?,
        _ list: () throws -> [(name: String, isFocused: Bool)]
    ) -> DropBarContent {
        do {
            let targets = try list().map { WorkspaceTarget(name: $0.name, isFocused: $0.isFocused) }
            let previews = targets.reduce(into: [String: NSImage]()) { previews, target in
                previews[target.name] = preview(target.name)
            }
            return DropBarContent(targets: targets, previews: previews)
        } catch {
            log.error("listing workspaces failed: \(error)")
            return DropBarContent(targets: [], previews: [:])
        }
    }

    /// nil (logged) on CLI failure, nil on an empty listing — neither shows
    /// an overlay.
    static func loadSnapshot(
        _ label: String,
        _ list: () throws -> WorkspaceSnapshot
    ) -> WorkspaceSnapshot? {
        do {
            let snapshot = try list()
            return snapshot.windows.isEmpty ? nil : snapshot
        } catch {
            log.error("listing \(label) windows failed: \(error)")
            return nil
        }
    }
}
