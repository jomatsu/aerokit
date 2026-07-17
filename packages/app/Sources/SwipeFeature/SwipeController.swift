import AeroKitCore
import AppKit
import Combine
import Foundation
import SwiftUI

private let log = AppLog(category: "swipe")

/// Turns horizontal three-finger gestures into AeroSpace workspace switches
/// with a finger-attached HUD: the workspace strip appears as the gesture
/// begins, its selection follows the fingers, and the switch commits when
/// they lift. The trackpad monitor itself lives in the coordinator because
/// only one can observe the pad at a time.
@MainActor
public final class SwipeController {
    private let client: AeroSpaceClient
    private let preferences: SwipePreferences
    private let workspaceOrderStore: WorkspaceOrderStore
    private let settingsModel = SwipeSettingsModel()
    private let hud = SwipeHUD()
    /// Cached workspace snapshot lookup (the switcher's store) for the
    /// HUD's thumbnail cards; nil images just render placeholders. Sendable
    /// so the gesture's background hop can decode cold-cache thumbnails off
    /// the main actor, right as the finger-tracking animation starts.
    private let workspacePreview: @Sendable (String) -> NSImage?
    /// Thumbnails resolved for the gesture in flight, reused at settle.
    private var currentPreviews: [String: NSImage] = [:]
    private let iconResolver = AppIconResolver()
    private var cancellables: Set<AnyCancellable> = []

    /// The focused monitor's workspaces resolved when the gesture began.
    private struct Ring {
        var workspaces: [String]
        var current: String
    }

    /// Resolves while the fingers are still moving so the HUD can appear
    /// mid-gesture; the commit awaits it.
    private var ringTask: Task<Ring?, Never>?
    /// Loads app icons concurrently with the ring and pushes them into the
    /// HUD when ready — neither the HUD's appearance nor the commit waits
    /// for the extra `list-windows` round trip or the icon disk probes.
    private var iconTask: Task<Void, Never>?
    /// Serializes commits: the next gesture's ring fetch must observe the
    /// previous switch, or a quick second swipe would move from a stale
    /// workspace.
    private var commitTask: Task<Void, Never>?
    /// Identifies the newest commit so the post-commit focus check can
    /// tell "focus moved because something external switched" from "focus
    /// moved because the user swiped again".
    private var commitEpoch = 0
    private var gestureActive = false
    private var latestOffset: CGFloat = 0

    /// The coordinator re-evaluates whether the shared trackpad monitor
    /// should run whenever this fires.
    public var onSwipePreferenceChanged: (() -> Void)?

    public var wantsSwipeGestures: Bool {
        preferences.isEnabled
    }

    /// Finger travel per workspace step; the coordinator pushes it into the
    /// shared trackpad monitor.
    public var stepDistanceMM: Double {
        preferences.stepDistanceMM
    }

    public init(
        client: AeroSpaceClient,
        workspaceOrder: WorkspaceOrderStore,
        workspacePreview: @escaping @Sendable (String) -> NSImage? = { _ in nil }
    ) {
        self.client = client
        workspaceOrderStore = workspaceOrder
        self.workspacePreview = workspacePreview
        preferences = SwipePreferences()
    }

    public func start() {
        settingsModel.refreshSystemGestureConflict(gestureEnabled: preferences.isEnabled)
        if settingsModel.systemGestureConflictMessage != nil {
            log.error("system three-finger Space swipe is enabled; workspace swipes will also slide macOS Spaces")
        }

        preferences.$isEnabled.dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    gestureActive = false
                    hud.hide()
                }
                settingsModel.refreshSystemGestureConflict(gestureEnabled: enabled)
                onSwipePreferenceChanged?()
            }
            .store(in: &cancellables)
        preferences.$showHUD.dropFirst()
            .sink { [weak self] show in
                if !show {
                    self?.hud.hide()
                }
            }
            .store(in: &cancellables)
        // Debounced: the settings slider emits continuously while dragged,
        // and every change restarts the trackpad monitor.
        preferences.$stepDistanceMM.dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.onSwipePreferenceChanged?() }
            .store(in: &cancellables)
    }

    /// Settings pane embedded in the unified settings window.
    public func makeSettingsPane() -> some View {
        SwipeSettingsView(
            model: settingsModel,
            preferences: preferences,
            workspaceOrder: workspaceOrderStore
        ) { [client] in
            try client.workspaceOrderEntries()
        }
    }

    /// Reflects the shared monitor's state in this feature's settings pane.
    public func updateSwipeAvailability(monitorRunning: Bool) {
        settingsModel.swipeErrorMessage = TrackpadSwipeMonitor.unavailableMessage(
            gestureEnabled: preferences.isEnabled,
            monitorRunning: monitorRunning
        )
    }

    public func handle(_ event: SwipeEvent) {
        guard preferences.isEnabled, event.axis == .horizontal else {
            return
        }
        switch event {
        case .began:
            beginGesture()
        case let .moved(_, progress):
            updateGesture(progress)
        case let .ended(_, steps):
            finishGesture(steps)
        }
    }

    /// The strip is ordered left to right. With natural direction the
    /// content follows the fingers, so fingers moving left (negative
    /// progress) reveal the workspace on the right.
    private func displayOffset(_ progress: Float) -> CGFloat {
        CGFloat(preferences.naturalDirection ? -progress : progress)
    }

    private func beginGesture() {
        gestureActive = true
        latestOffset = 0

        let client = client
        let skipEmpty = preferences.skipEmpty
        let order = workspaceOrderStore.order
        let showHUD = preferences.showHUD
        let preview = workspacePreview
        let previousCommit = commitTask
        ringTask = Task { [weak self] in
            // The previous gesture's switch must land before this ring is
            // read, or AeroSpace still reports the old focused workspace.
            await previousCommit?.value
            let loaded = await BlockingWork.run { () -> (ring: Ring, previews: [String: NSImage])? in
                guard let ring = Self.loadRing(client: client, skipEmpty: skipEmpty, order: order) else {
                    return nil
                }
                // The store caches decoded thumbnails, so this is disk-bound
                // once per snapshot refresh at most — but that cold decode
                // belongs here, off the main actor, not under the HUD's
                // first animation frame.
                let previews = showHUD
                    ? ring.workspaces.reduce(into: [String: NSImage]()) { $0[$1] = preview($1) }
                    : [:]
                return (ring: ring, previews: previews)
            }
            guard let loaded, let self, showHUD else {
                return loaded?.ring
            }
            currentPreviews = loaded.previews
            // Bring the HUD up mid-gesture as soon as the ring is known.
            if gestureActive {
                hud.beginInteractive(
                    workspaces: loaded.ring.workspaces,
                    current: loaded.ring.current,
                    previews: currentPreviews,
                    wrapsAround: preferences.wrapAround
                )
                hud.setOffset(latestOffset)
            }
            return loaded.ring
        }

        // App icons load alongside the ring, off the main thread (cache
        // misses probe Launch Services and the disk), and stream into the
        // HUD whenever they arrive. Cancelling keeps a slow older load
        // from overwriting a newer gesture's icons.
        iconTask?.cancel()
        guard preferences.showHUD else {
            return
        }
        let resolver = iconResolver
        iconTask = Task { [weak self] in
            let icons = await BlockingWork.run { () -> [String: [NSImage]] in
                Self.loadIcons(client: client, resolver: resolver)
            }
            guard let self, !Task.isCancelled else {
                return
            }
            hud.updateIcons(icons)
        }
    }

    private func updateGesture(_ progress: Float) {
        guard gestureActive else {
            return
        }
        latestOffset = displayOffset(progress)
        hud.setOffset(latestOffset)
    }

    private func finishGesture(_ steps: Int) {
        guard gestureActive else {
            return
        }
        gestureActive = false

        // Land on whatever card the selection shows at release — a long
        // swipe commits several workspaces. The sign maps through the same
        // natural-direction rule as the display.
        let offset = preferences.naturalDirection ? -steps : steps

        let ringTask = ringTask
        let wrapAround = preferences.wrapAround
        let showHUD = preferences.showHUD
        let client = client
        commitEpoch += 1
        let epoch = commitEpoch
        commitTask = Task { [weak self] in
            guard let ring = await ringTask?.value else {
                return
            }
            // nil when the gesture cancelled or hit a non-wrapping edge —
            // the selection then springs back to where it started.
            let plan = offset == 0 ? nil : SwipeNavigation.plan(
                current: ring.current,
                workspaces: ring.workspaces,
                offset: offset,
                wrapAround: wrapAround
            )
            .flatMap { $0.target != ring.current ? $0 : nil }

            if showHUD, let self {
                hud.settle(
                    workspaces: plan?.workspaces ?? ring.workspaces,
                    current: plan?.target ?? ring.current,
                    previews: currentPreviews,
                    wrapsAround: wrapAround
                )
            }
            guard let plan else {
                return
            }
            await BlockingWork.run {
                do {
                    try client.switchToWorkspace(plan.target)
                    // What AeroSpace reports right after the switch: a
                    // mismatch already here would be the switch itself
                    // going wrong, not a later external actor.
                    let landed = (try? client.focusedWorkspaceName()).flatMap(\.self)
                    log.notice("swipe landed: \(landed ?? "unknown") (committed: \(plan.target))")
                } catch {
                    log.error("swipe workspace switch failed: \(error)")
                }
            }
            self?.verifyFocus(after: plan.target, epoch: epoch)
        }
    }

    /// Reads focus back one second after a commit landed. If it moved off
    /// the committed workspace and no newer gesture took over, something
    /// outside AeroKit switched — most likely the system's own
    /// three-finger Space swipe, which reacts to the same physical
    /// gesture and slides the screen to another macOS Space on top of our
    /// (correct) workspace switch. The frontmost app names the Space the
    /// screen actually ended on.
    private func verifyFocus(after target: String, epoch: Int) {
        let client = client
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, epoch == commitEpoch else {
                return
            }
            let focused = await BlockingWork.run { (try? client.focusedWorkspaceName()).flatMap(\.self) }
            guard let focused, focused != target else {
                return
            }
            let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
            log.error(
                """
                post-swipe drift: \(target) → \(focused) within 1s \
                (frontmost: \(frontmost)) — an external gesture handler \
                (e.g. the macOS three-finger Space swipe) moved the screen \
                after the commit
                """
            )
        }
    }

    /// Blocking CLI round trips; the caller runs it on BlockingWork. Returns
    /// nil (logged) when AeroSpace is unreachable or reports no usable
    /// workspace.
    private nonisolated static func loadRing(client: AeroSpaceClient, skipEmpty: Bool, order: [String]) -> Ring? {
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

    /// Blocking CLI round trip plus icon resolution; the caller runs it on
    /// BlockingWork. One `list-windows --all` covers every workspace —
    /// icon-less cards are better than serializing a call per workspace.
    private nonisolated static func loadIcons(
        client: AeroSpaceClient,
        resolver: AppIconResolver
    ) -> [String: [NSImage]] {
        do {
            return try Dictionary(grouping: client.listWindows(), by: \.workspace)
                .mapValues { windows in
                    WorkspaceApp.uniqueApps(from: windows).compactMap(resolver.icon(for:))
                }
        } catch {
            log.error("swipe window listing failed: \(error)")
            return [:]
        }
    }
}
