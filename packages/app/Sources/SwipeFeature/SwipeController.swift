import AeroKitCore
import Combine
import Foundation
import SwiftUI

/// Turns horizontal three-finger swipes into AeroSpace workspace switches
/// and shows the workspace strip HUD. The trackpad monitor itself lives in
/// the coordinator because only one can observe the pad at a time.
@MainActor
public final class SwipeController {
    private let client: AeroSpaceClient
    private let preferences: SwipePreferences
    private let settingsModel = SwipeSettingsModel()
    private let hud = SwipeHUD()
    /// Swipes arriving while a switch is in flight accumulate into a net
    /// offset — opposite directions cancel out — drained by one worker, so
    /// a slow CLI never builds a backlog of stale switches.
    private var pendingOffset = 0
    private var drainTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// The coordinator re-evaluates whether the shared trackpad monitor
    /// should run whenever this fires.
    public var onSwipePreferenceChanged: (() -> Void)?

    public var wantsSwipeGestures: Bool {
        preferences.isEnabled
    }

    public init(client: AeroSpaceClient) {
        self.client = client
        preferences = SwipePreferences()
    }

    public func start() {
        preferences.$isEnabled.dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    pendingOffset = 0
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

    public func handleSwipe(_ direction: TrackpadSwipeMonitor.Direction) {
        guard preferences.isEnabled else {
            return
        }
        let step: SwipeNavigation.Step
        switch direction {
        case .left:
            // Natural direction: content follows the fingers, so swiping
            // left reveals the workspace on the right.
            step = preferences.naturalDirection ? .next : .previous
        case .right:
            step = preferences.naturalDirection ? .previous : .next
        case .up, .down:
            return
        }
        pendingOffset += step == .next ? 1 : -1
        drainPendingSwitches()
    }

    private func drainPendingSwitches() {
        guard drainTask == nil else {
            return
        }
        drainTask = Task { [weak self] in
            while let self, let step = self.takePendingStep() {
                await self.switchOnce(step)
            }
            self?.drainTask = nil
        }
    }

    private func takePendingStep() -> SwipeNavigation.Step? {
        guard pendingOffset != 0 else {
            return nil
        }
        let step: SwipeNavigation.Step = pendingOffset > 0 ? .next : .previous
        pendingOffset += pendingOffset > 0 ? -1 : 1
        return step
    }

    private func switchOnce(_ step: SwipeNavigation.Step) async {
        let client = client
        let skipEmpty = preferences.skipEmpty
        let wrapAround = preferences.wrapAround
        let plan = await Task.detached(priority: .userInitiated) { () -> SwipeNavigation.Plan? in
            Self.resolveAndSwitch(client: client, step: step, skipEmpty: skipEmpty, wrapAround: wrapAround)
        }.value
        guard let plan else {
            return
        }
        if preferences.showHUD {
            hud.show(workspaces: plan.workspaces, current: plan.target)
        }
    }

    /// Blocking CLI round trips; runs detached. Returns nil (logged) when
    /// AeroSpace is unreachable or reports no usable workspace.
    private nonisolated static func resolveAndSwitch(
        client: AeroSpaceClient,
        step: SwipeNavigation.Step,
        skipEmpty: Bool,
        wrapAround: Bool
    ) -> SwipeNavigation.Plan? {
        do {
            let workspaces = try client.workspacesOnFocusedMonitor(includeEmpty: !skipEmpty)
            // Skipping empty workspaces can drop the focused one (it may
            // itself be empty), so fall back to asking for it directly.
            guard let current = try workspaces.first(where: \.isFocused)?.name
                ?? client.focusedWorkspaceName()
            else {
                return nil
            }
            guard let plan = SwipeNavigation.plan(
                current: current,
                workspaces: workspaces.map(\.name),
                step: step,
                wrapAround: wrapAround
            ) else {
                return nil
            }
            if plan.target != current {
                try client.switchToWorkspace(plan.target)
            }
            return plan
        } catch {
            fputs("AeroKit: swipe workspace switch failed: \(error)\n", stderr)
            return nil
        }
    }
}
