import AppKit

@MainActor
public final class SwitcherController {
    private let configuration: SwitcherConfiguration
    private let repository: WorkspaceRepository
    private let snapshotStore: SnapshotStore
    private let snapshotScheduler: SnapshotRefreshScheduler
    private let iconResolver: AppIconResolver
    private let overlay: SwiftUIOverlay
    private let hotKeyCenter: HotKeyCenter
    private let settingsModel: SwitcherSettingsModel
    private let settingsWindowController: SettingsWindowController
    private let statusBarController: StatusBarController

    private var workspaces: [Workspace] = [] {
        didSet { presentationCache = nil }
    }

    private var presentationCache: [WorkspacePresentation]?
    private var selectedIndex = 0
    private var isSnapshotRefreshRunning = false
    private var snapshotFeedback: SnapshotRefreshFeedback = .idle
    private var snapshotFeedbackClearWorkItem: DispatchWorkItem?

    public init(configuration: SwitcherConfiguration = SwitcherConfiguration()) {
        self.configuration = configuration

        let client = AeroSpaceClient(executablePath: configuration.aerospacePath)
        repository = WorkspaceRepository(client: client, order: configuration.workspaceOrder)
        snapshotStore = SnapshotStore(rootPath: configuration.snapshotRootPath)
        snapshotScheduler = SnapshotRefreshScheduler(configuration: configuration, snapshotStore: snapshotStore)
        iconResolver = AppIconResolver()
        overlay = SwiftUIOverlay(configuration: configuration)
        hotKeyCenter = HotKeyCenter()
        settingsModel = SwitcherSettingsModel(configuration: configuration, snapshotStore: snapshotStore)
        settingsWindowController = SettingsWindowController(model: settingsModel)
        statusBarController = StatusBarController()

        wireActions()
    }

    public func start() {
        hotKeyCenter.onPressed = { [weak self] hotKey in
            self?.handleHotKey(hotKey)
        }

        if configuration.snapshotRefreshEnabled {
            snapshotScheduler.startWatchingRequests()
        }

        registerLaunchHotKey()
        statusBarController.start()
        settingsModel.refreshStatus()
    }

    public func showSettings() {
        settingsModel.refreshStatus()
        settingsWindowController.show()
    }

    private func registerLaunchHotKey() {
        do {
            try hotKeyCenter.register(.optionBacktick)
        } catch {
            logError("Failed to register hotkey: \(error)")
        }
    }

    private func registerVisibleHotKeys() {
        do {
            try hotKeyCenter.register(.escape)
        } catch {
            logError("Failed to register visible hotkey: \(error)")
        }
    }

    private func logError(_ message: String) {
        fputs("\(message)\n", stderr)
    }

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
        overlay.onCancel = { [weak self] in
            self?.hide()
        }
        settingsModel.onRefreshSnapshots = { [weak self] in
            self?.refreshSnapshotsFromSettings() ?? false
        }
        statusBarController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        statusBarController.onRefreshSnapshots = { [weak self] in
            self?.settingsWindowController.show()
            self?.settingsModel.refreshSnapshots()
        }
        statusBarController.onQuit = {
            NSApp.terminate(nil)
        }

        snapshotScheduler.onRefreshFinished = { [weak self] _ in
            guard let self else { return }
            markSnapshotRefreshFinished()
        }
        snapshotScheduler.onRefreshFailed = { [weak self] message in
            guard let self else { return }
            markSnapshotRefreshFailed(message)
            logError("Snapshot refresh failed: \(message)")
        }
        snapshotScheduler.onRequestReceived = { [weak self] reason in
            guard reason == .workspaceChange else {
                return
            }
            self?.hide()
        }
    }

    private func handleHotKey(_ hotKey: RegisteredHotKey) {
        switch hotKey {
        case .optionBacktick:
            handleOptionBacktick()
        case .escape:
            hide()
        }
    }

    private func handleOptionBacktick() {
        if overlay.isVisible {
            advanceSelection()
            return
        }

        show()
    }

    private func show() {
        do {
            workspaces = try repository.load()
            selectedIndex = focusedWorkspaceIndex(in: workspaces) ?? 0
        } catch {
            logError("Failed to load workspaces: \(error)")
            workspaces = []
            selectedIndex = 0
        }

        overlay.show(
            items: presentationItems(),
            selectedIndex: selectedIndex,
            isLoading: isSnapshotRefreshRunning,
            snapshotFeedback: snapshotFeedback
        )
        registerVisibleHotKeys()
        refreshWorkspacesAsync()

        let shouldRefreshSnapshots = configuration.snapshotRefreshEnabled
            && configuration.snapshotRefreshOnShow
            && snapshotStore.isStale(maxAge: configuration.snapshotStaleInterval)

        if shouldRefreshSnapshots {
            if snapshotScheduler.refreshOnShowIfNeeded() {
                markSnapshotRefreshStarted()
            }
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
        selectedIndex = (selectedIndex + 1) % workspaces.count
        updateOverlayIfVisible()
    }

    private func moveSelection(_ move: SelectionMove) {
        guard !workspaces.isEmpty else {
            return
        }

        switch move {
        case .left:
            selectedIndex = max(0, selectedIndex - 1)
        case .right:
            selectedIndex = min(workspaces.count - 1, selectedIndex + 1)
        case .up:
            selectedIndex = max(0, selectedIndex - configuration.columns)
        case .down:
            selectedIndex = min(workspaces.count - 1, selectedIndex + configuration.columns)
        case .next:
            selectedIndex = (selectedIndex + 1) % workspaces.count
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
        do {
            try repository.switchToWorkspace(name)
            if configuration.snapshotRefreshEnabled {
                if snapshotScheduler.schedule(reason: .workspaceChange) {
                    markSnapshotRefreshStarted()
                }
            }
        } catch {
            logError("Failed to switch workspace \(name): \(error)")
        }
        hide()
    }

    private func refreshWorkspacesAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [repository] in
            let result = Result { try repository.load() }
            DispatchQueue.main.async {
                self.applyWorkspaceRefresh(result)
            }
        }
    }

    private func applyWorkspaceRefresh(_ result: Result<[Workspace], any Error>) {
        switch result {
        case let .success(fresh):
            workspaces = fresh
            if !overlay.isVisible {
                selectedIndex = focusedWorkspaceIndex(in: fresh) ?? 0
            } else if selectedIndex >= fresh.count {
                selectedIndex = max(0, fresh.count - 1)
            }
            updateOverlayIfVisible()
        case let .failure(error):
            logError("Failed to refresh workspaces: \(error)")
        }
    }

    private func updateOverlayIfVisible() {
        guard overlay.isVisible else {
            return
        }
        overlay.update(
            items: presentationItems(),
            selectedIndex: selectedIndex,
            isLoading: isSnapshotRefreshRunning,
            snapshotFeedback: snapshotFeedback
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

    private func refreshSnapshotsFromSettings() -> Bool {
        settingsModel.refreshStatus()

        guard ScreenCapturePermission.isGranted else {
            markSnapshotRefreshFailed("Grant Screen Recording permission before refreshing snapshots.")
            return false
        }

        guard snapshotScheduler.refreshNow() else {
            markSnapshotRefreshFailed("Snapshot refresh could not be started.")
            return false
        }

        markSnapshotRefreshStarted()
        return true
    }

    private func markSnapshotRefreshStarted() {
        snapshotFeedbackClearWorkItem?.cancel()
        snapshotFeedbackClearWorkItem = nil
        isSnapshotRefreshRunning = true
        snapshotFeedback = .refreshing
        settingsModel.markSnapshotRefreshStarted()
        updateOverlayIfVisible()
    }

    private func markSnapshotRefreshFinished() {
        isSnapshotRefreshRunning = false
        snapshotFeedback = .success
        presentationCache = nil
        settingsModel.markSnapshotRefreshFinished()
        updateOverlayIfVisible()
        clearSnapshotFeedback(after: 2.0)
    }

    private func markSnapshotRefreshFailed(_ message: String) {
        isSnapshotRefreshRunning = false
        snapshotFeedback = .failure(message)
        settingsModel.markSnapshotRefreshFailed(message)
        updateOverlayIfVisible()
        clearSnapshotFeedback(after: 4.0)
    }

    private func clearSnapshotFeedback(after delay: TimeInterval) {
        snapshotFeedbackClearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !isSnapshotRefreshRunning else {
                return
            }
            snapshotFeedback = .idle
            updateOverlayIfVisible()
        }

        snapshotFeedbackClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
