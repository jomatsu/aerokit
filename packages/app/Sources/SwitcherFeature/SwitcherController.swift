import AeroKitCore
import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
public final class SwitcherController {
    private let configuration: SwitcherConfiguration
    private let preferences: AppPreferences
    private let repository: WorkspaceRepository
    private let snapshotStore: SnapshotStore
    private let snapshotScheduler: SnapshotRefreshScheduler
    private let iconResolver: AppIconResolver
    private let overlay: SwiftUIOverlay
    private let hotKeyCenter: HotKeyCenter
    private let settingsModel: SwitcherSettingsModel

    /// The unified settings window lives in the app shell; the controller
    /// only asks for it to be opened.
    public var onOpenSettings: (() -> Void)?

    private var workspaces: [Workspace] = [] {
        didSet {
            if workspaces != oldValue {
                presentationCache = nil
            }
        }
    }

    private let feedbackCoordinator: SnapshotFeedbackCoordinator
    private var presentationCache: [WorkspacePresentation]?
    private var selectedIndex = 0
    private var hasUserNavigatedSinceShow = false
    private var cancellables: Set<AnyCancellable> = []

    public init(
        configuration: SwitcherConfiguration = SwitcherConfiguration(),
        hotKeyCenter: HotKeyCenter
    ) {
        self.configuration = configuration
        self.hotKeyCenter = hotKeyCenter
        preferences = AppPreferences()

        let client = AeroSpaceClient(executablePath: configuration.aerospacePath)
        repository = WorkspaceRepository(client: client, order: configuration.workspaceOrder)
        snapshotStore = SnapshotStore(
            rootPath: configuration.snapshotRootPath,
            maxThumbnailPixelSize: max(configuration.snapshotSize.width, configuration.snapshotSize.height) * 2
        )
        snapshotScheduler = SnapshotRefreshScheduler(
            configuration: configuration,
            preferences: preferences,
            snapshotStore: snapshotStore,
            engine: SnapshotEngine(configuration: configuration, client: client)
        )
        iconResolver = AppIconResolver()
        overlay = SwiftUIOverlay(configuration: configuration, preferences: preferences)
        settingsModel = SwitcherSettingsModel(
            configuration: configuration,
            preferences: preferences,
            snapshotStore: snapshotStore
        )
        feedbackCoordinator = SnapshotFeedbackCoordinator(settingsModel: settingsModel)

        wireActions()
    }

    public func start() {
        if configuration.snapshotRefreshEnabled {
            snapshotScheduler.startWatchingRequests()
        }

        registerLaunchHotKey()
        settingsModel.refreshStatus()
        refreshWorkspacesAsync()
        observePreferences()
        showOnboardingIfNeeded()
    }

    private func showSettings() {
        onOpenSettings?()
    }

    /// Settings pane embedded in the unified settings window.
    public func makeSettingsPane() -> some View {
        SwitcherSettingsView(model: settingsModel)
    }

    public func refreshSettingsStatus() {
        settingsModel.refreshStatus()
    }

    /// Status-bar menu entry point: open settings and kick off a refresh so
    /// its progress is visible.
    public func refreshSnapshotsFromMenu() {
        showSettings()
        settingsModel.refreshSnapshots()
    }

    public func handle(_ role: HotKeyRole) {
        switch role {
        case .cycleForward:
            if overlay.isVisible {
                advanceSelection()
            } else {
                show(initialMove: .next)
            }
        case .cycleBackward:
            if overlay.isVisible {
                moveSelection(.previous)
            } else {
                show(initialMove: .previous)
            }
        case .escape:
            hide()
        case .exposeToggle:
            break
        }
    }

    private func registerLaunchHotKey() {
        let spec = preferences.hotKey
        do {
            try hotKeyCenter.register(
                .cycleForward,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers
            )
            try hotKeyCenter.register(
                .cycleBackward,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers | UInt32(shiftKey)
            )
            settingsModel.markHotKeyRegistration(error: nil)
        } catch {
            logError("Failed to register hotkey: \(error)")
            settingsModel.markHotKeyRegistration(
                error: "Could not register \(spec.displayKeys.joined()) as the global hotkey. "
                    + "Another app may already use it — record a different shortcut above."
            )
        }
    }

    private func registerVisibleHotKeys() {
        do {
            try hotKeyCenter.register(.escape, keyCode: UInt32(kVK_Escape), modifiers: 0)
        } catch {
            logError("Failed to register visible hotkey: \(error)")
        }
        // Carbon hotkeys swallow the key without repeating, so hand the
        // trigger back to normal dispatch while the overlay is key: held keys
        // then deliver repeating keyDown events to the panel and keep cycling.
        unregisterLaunchHotKeys()
    }

    private func unregisterLaunchHotKeys() {
        hotKeyCenter.unregister(.cycleForward)
        hotKeyCenter.unregister(.cycleBackward)
    }

    private func logError(_ message: String) {
        fputs("\(message)\n", stderr)
    }
}

// MARK: - Wiring

extension SwitcherController {
    private func wireActions() {
        overlay.onAdvance = { [weak self] in
            self?.advanceSelection()
        }
        overlay.onMove = { [weak self] move in
            self?.moveSelection(move)
        }
        overlay.onSelect = { [weak self] in
            self?.selectCurrentWorkspace()
        }
        overlay.onQuickSelect = { [weak self] workspace in
            self?.selectWorkspace(named: workspace)
        }
        overlay.onActivateWorkspace = { [weak self] workspace in
            self?.selectWorkspace(named: workspace)
        }
        overlay.onReloadSnapshots = { [weak self] in
            _ = self?.refreshSnapshotsFromSettings()
        }
        overlay.onOpenSettings = { [weak self] in
            self?.hide()
            self?.showSettings()
        }
        overlay.onCancel = { [weak self] in
            self?.hide()
        }
        overlay.onModifierRelease = { [weak self] in
            guard let self, hasUserNavigatedSinceShow else {
                return
            }
            selectCurrentWorkspace()
        }
        overlay.onHoverSelect = { [weak self] index in
            guard let self, workspaces.indices.contains(index), selectedIndex != index else {
                return
            }
            selectedIndex = index
            hasUserNavigatedSinceShow = true
            updateOverlayIfVisible()
        }
        wireSettings()
        wireSnapshotScheduler()
    }

    private func wireSettings() {
        settingsModel.onRefreshSnapshots = { [weak self] in
            self?.refreshSnapshotsFromSettings() ?? false
        }
        settingsModel.onHotKeyRecordingChanged = { [weak self] isRecording in
            guard let self else { return }
            // Suspend the global trigger while recording so the chosen
            // combination reaches the recorder instead of opening the switcher.
            if isRecording {
                unregisterLaunchHotKeys()
            } else if !overlay.isVisible {
                registerLaunchHotKey()
            }
        }
    }

    private func wireSnapshotScheduler() {
        snapshotScheduler.onRefreshStarted = { [weak self] in
            self?.feedbackCoordinator.markStarted()
        }
        snapshotScheduler.onRefreshProgress = { [weak self] completed, total in
            self?.feedbackCoordinator.markProgress(completed: completed, total: total)
        }
        snapshotScheduler.onRefreshFinished = { [weak self] _ in
            self?.feedbackCoordinator.markFinished()
        }
        snapshotScheduler.onRefreshFailed = { [weak self] message in
            self?.feedbackCoordinator.markFailed(message)
            self?.logError("Snapshot refresh failed: \(message)")
        }
        snapshotScheduler.onRequestReceived = { [weak self] reason in
            guard reason == .workspaceChange else {
                return
            }
            self?.hide()
        }

        feedbackCoordinator.onChange = { [weak self] in
            self?.updateOverlayIfVisible()
        }
        feedbackCoordinator.onRefreshCompleted = { [weak self] in
            self?.presentationCache = nil
            self?.prewarmSnapshotCache()
        }
    }

    private func observePreferences() {
        preferences.$hotKey.dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                unregisterLaunchHotKeys()
                if !overlay.isVisible {
                    registerLaunchHotKey()
                }
            }
            .store(in: &cancellables)

        preferences.$hideEmptyWorkspaces.dropFirst()
            .sink { [weak self] _ in self?.refreshWorkspacesAsync() }
            .store(in: &cancellables)
    }

    private func showOnboardingIfNeeded() {
        // A failed hotkey registration leaves the app unreachable, so it
        // warrants the settings window just like a missing permission.
        guard !ScreenCapturePermission.isGranted || settingsModel.hotKeyErrorMessage != nil else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showSettings()
        }
    }
}

// MARK: - Selection & workspaces

extension SwitcherController {
    private func show(initialMove: SelectionMove) {
        selectedIndex = focusedWorkspaceIndex(in: workspaces) ?? 0
        hasUserNavigatedSinceShow = false

        overlay.show(
            items: presentationItems(),
            selectedIndex: selectedIndex,
            snapshotFeedback: feedbackCoordinator.feedback
        )
        registerVisibleHotKeys()

        // cmd-tab style: pre-select the adjacent workspace so a quick tap of
        // the hotkey commits it as soon as the modifier is released.
        if preferences.switchOnRelease {
            moveSelection(initialMove)
        }

        refreshWorkspacesAsync()

        if configuration.snapshotRefreshEnabled {
            snapshotScheduler.refreshOnShowIfNeeded()
        }
    }

    private func hide() {
        overlay.hide()
        hotKeyCenter.unregister(.escape)
        registerLaunchHotKey()
    }

    private func advanceSelection() {
        guard !workspaces.isEmpty else {
            return
        }
        hasUserNavigatedSinceShow = true
        selectedIndex = (selectedIndex + 1) % workspaces.count
        updateOverlayIfVisible()
    }

    private func moveSelection(_ move: SelectionMove) {
        guard !workspaces.isEmpty else {
            return
        }

        hasUserNavigatedSinceShow = true

        switch move {
        case .left:
            selectedIndex = max(0, selectedIndex - 1)
        case .right:
            selectedIndex = min(workspaces.count - 1, selectedIndex + 1)
        case .up:
            selectedIndex = max(0, selectedIndex - preferences.gridColumns)
        case .down:
            selectedIndex = min(workspaces.count - 1, selectedIndex + preferences.gridColumns)
        case .next:
            selectedIndex = (selectedIndex + 1) % workspaces.count
        case .previous:
            selectedIndex = (selectedIndex - 1 + workspaces.count) % workspaces.count
        }

        updateOverlayIfVisible()
    }

    private func selectCurrentWorkspace() {
        guard workspaces.indices.contains(selectedIndex) else {
            hide()
            return
        }
        selectWorkspace(named: workspaces[selectedIndex].name)
    }

    private func selectWorkspace(named name: String) {
        hide()

        performInBackground { [repository] in
            try repository.switchToWorkspace(name)
        } then: { result in
            self.finishWorkspaceSwitch(named: name, result: result)
        }
    }

    private func finishWorkspaceSwitch(named name: String, result: Result<Void, any Error>) {
        switch result {
        case .success:
            refreshWorkspacesAsync()
            if configuration.snapshotRefreshEnabled {
                snapshotScheduler.schedule(reason: .workspaceChange)
            }
        case let .failure(error):
            logError("Failed to switch workspace \(name): \(error)")
        }
    }

    private func refreshWorkspacesAsync() {
        performInBackground { [repository] in
            try repository.load()
        } then: { result in
            self.applyWorkspaceRefresh(result)
        }
    }

    private func performInBackground<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T,
        then handle: @escaping @MainActor (Result<T, any Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result(catching: work)
            DispatchQueue.main.async {
                handle(result)
            }
        }
    }

    private func applyWorkspaceRefresh(_ result: Result<[Workspace], any Error>) {
        switch result {
        case var .success(fresh):
            if preferences.hideEmptyWorkspaces {
                fresh = fresh.filter { !$0.isEmpty || $0.isFocused }
            }
            let selectedName = workspaces.indices.contains(selectedIndex) ? workspaces[selectedIndex].name : nil
            workspaces = fresh
            if !overlay.isVisible || !hasUserNavigatedSinceShow {
                selectedIndex = focusedWorkspaceIndex(in: fresh) ?? 0
            } else if let selectedName, let index = fresh.firstIndex(where: { $0.name == selectedName }) {
                selectedIndex = index
            } else if selectedIndex >= fresh.count {
                selectedIndex = max(0, fresh.count - 1)
            }
            prewarmSnapshotCache()
            updateOverlayIfVisible()
        case let .failure(error):
            logError("Failed to refresh workspaces: \(error)")
            if overlay.isVisible {
                feedbackCoordinator.showTransientFailure("Could not load workspaces from AeroSpace")
            }
        }
    }

    private func updateOverlayIfVisible() {
        guard overlay.isVisible else {
            return
        }
        overlay.update(
            items: presentationItems(),
            selectedIndex: selectedIndex,
            snapshotFeedback: feedbackCoordinator.feedback
        )
    }

    private func presentationItems() -> [WorkspacePresentation] {
        if let presentationCache {
            return presentationCache
        }

        let snapshotDirectory = snapshotStore.currentDirectory()
        let items = workspaces.map { workspace in
            WorkspacePresentation(
                workspace: workspace,
                snapshot: snapshotDirectory.flatMap { snapshotStore.snapshotImage(for: workspace.name, in: $0) },
                appIcons: workspace.apps.compactMap(iconResolver.icon(for:))
            )
        }
        presentationCache = items
        return items
    }

    private func focusedWorkspaceIndex(in workspaces: [Workspace]) -> Int? {
        workspaces.firstIndex(where: \.isFocused)
    }
}

// MARK: - Snapshot refresh

extension SwitcherController {
    private func refreshSnapshotsFromSettings() -> Bool {
        settingsModel.refreshStatus()

        guard ScreenCapturePermission.isGranted else {
            feedbackCoordinator.markFailed("Grant Screen Recording permission before refreshing snapshots.")
            return false
        }

        guard snapshotScheduler.refreshNow() else {
            feedbackCoordinator.markFailed("Snapshot refresh could not be started.")
            return false
        }

        return true
    }

    private func prewarmSnapshotCache() {
        let names = workspaces.map(\.name)
        DispatchQueue.global(qos: .utility).async { [snapshotStore] in
            guard let directory = snapshotStore.currentDirectory() else {
                return
            }
            for name in names {
                _ = snapshotStore.snapshotImage(for: name, in: directory)
            }
        }
    }
}
