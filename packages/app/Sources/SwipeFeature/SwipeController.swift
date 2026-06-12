import AeroKitCore
import AppKit
import Combine
import Foundation
import SwiftUI

/// Turns horizontal three-finger gestures into AeroSpace workspace switches
/// with a finger-attached HUD: the workspace strip appears as the gesture
/// begins, its selection follows the fingers, and the switch commits when
/// they lift. The trackpad monitor itself lives in the coordinator because
/// only one can observe the pad at a time.
@MainActor
public final class SwipeController {
    private let client: AeroSpaceClient
    private let preferences: SwipePreferences
    private let settingsModel = SwipeSettingsModel()
    private let hud = SwipeHUD()
    /// Cached workspace snapshot lookup (the switcher's store) for the
    /// HUD's thumbnail cards; nil images just render placeholders.
    private let workspacePreview: (String) -> NSImage?
    /// Thumbnails resolved for the gesture in flight, reused at settle.
    private var currentPreviews: [String: NSImage] = [:]
    private var cancellables: Set<AnyCancellable> = []

    /// The focused monitor's workspaces resolved when the gesture began.
    private struct Ring {
        var workspaces: [String]
        var current: String
    }

    /// Resolves while the fingers are still moving so the HUD can appear
    /// mid-gesture; the commit awaits it.
    private var ringTask: Task<Ring?, Never>?
    /// Serializes commits: the next gesture's ring fetch must observe the
    /// previous switch, or a quick second swipe would move from a stale
    /// workspace.
    private var commitTask: Task<Void, Never>?
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

    public init(client: AeroSpaceClient, workspacePreview: @escaping (String) -> NSImage? = { _ in nil }) {
        self.client = client
        self.workspacePreview = workspacePreview
        preferences = SwipePreferences()
    }

    public func start() {
        preferences.$isEnabled.dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    gestureActive = false
                    hud.hide()
                }
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
        SwipeSettingsView(model: settingsModel, preferences: preferences)
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
        let previousCommit = commitTask
        ringTask = Task { [weak self] in
            // The previous gesture's switch must land before this ring is
            // read, or AeroSpace still reports the old focused workspace.
            await previousCommit?.value
            let ring = await Task.detached(priority: .userInitiated) { () -> Ring? in
                Self.loadRing(client: client, skipEmpty: skipEmpty)
            }.value
            guard let ring, let self, preferences.showHUD else {
                return ring
            }
            // The store caches decoded thumbnails, so this is disk-bound
            // once per snapshot refresh at most.
            currentPreviews = ring.workspaces.reduce(into: [:]) { previews, name in
                previews[name] = workspacePreview(name)
            }
            // Bring the HUD up mid-gesture as soon as the ring is known.
            if gestureActive {
                hud.beginInteractive(
                    workspaces: ring.workspaces,
                    current: ring.current,
                    previews: currentPreviews,
                    wrapsAround: preferences.wrapAround
                )
                hud.setOffset(latestOffset)
            }
            return ring
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
            ).flatMap { $0.target != ring.current ? $0 : nil }

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
            await Task.detached(priority: .userInitiated) {
                do {
                    try client.switchToWorkspace(plan.target)
                } catch {
                    fputs("AeroKit: swipe workspace switch failed: \(error)\n", stderr)
                }
            }.value
        }
    }

    /// Blocking CLI round trips; runs detached. Returns nil (logged) when
    /// AeroSpace is unreachable or reports no usable workspace.
    private nonisolated static func loadRing(client: AeroSpaceClient, skipEmpty: Bool) -> Ring? {
        do {
            let workspaces = try client.workspacesOnFocusedMonitor(includeEmpty: !skipEmpty)
            // Skipping empty workspaces can drop the focused one (it may
            // itself be empty), so fall back to asking for it directly.
            guard let current = try workspaces.first(where: \.isFocused)?.name
                ?? client.focusedWorkspaceName()
            else {
                return nil
            }
            return Ring(
                workspaces: SwipeNavigation.ring(current: current, workspaces: workspaces.map(\.name)),
                current: current
            )
        } catch {
            fputs("AeroKit: swipe workspace listing failed: \(error)\n", stderr)
            return nil
        }
    }
}
