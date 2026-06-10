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
        didSet {
            if workspaces != oldValue {
                presentationCache = nil
            }
        }
    }

    private var presentationCache: [WorkspacePresentation]?
    private var selectedIndex = 0
    private var hasUserNavigatedSinceShow = false
    private var isSnapshotRefreshRunning = false
    private var snapshotFeedback: SnapshotRefreshFeedback = .idle
    private var snapshotFeedbackClearWorkItem: DispatchWorkItem?

    public init(configuration: SwitcherConfiguration = SwitcherConfiguration()) {
        self.configuration = configuration

        let client = AeroSpaceClient(executablePath: configuration.aerospacePath)
        repository = WorkspaceRepository(client: client, order: configuration.workspaceOrder)
        snapshotStore = SnapshotStore(
            rootPath: configuration.snapshotRootPath,
            maxThumbnailPixelSize: max(configuration.snapshotSize.width, configuration.snapshotSize.height) * 2
        )
        snapshotScheduler = SnapshotRefreshScheduler(
            configuration: configuration,
            snapshotStore: snapshotStore,
            engine: SnapshotEngine(configuration: configuration, client: client)
        )
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
        refreshWorkspacesAsync()
    }

    public func showSettings() {
        settingsModel.refreshStatus()
        settingsWindowController.show()
    }

    private func registerLaunchHotKey() {
        do {
            try hotKeyCenter.register(.optionBacktick)
            try hotKeyCenter.register(.optionShiftBacktick)
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
        // Carbon hotkeys swallow the key without repeating, so hand Option+`
        // back to normal dispatch while the overlay is key: held keys then
        // deliver repeating keyDown events to the panel and keep cycling.
        hotKeyCenter.unregister(.optionBacktick)
        hotKeyCenter.unregister(.optionShiftBacktick)
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
        overlay.onModifierRelease = { [weak self] in
            guard let self, hasUserNavigatedSinceShow else {
                return
            }
            selectCurrentWorkspace()
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

        wireSnapshotScheduler()
    }

    private func wireSnapshotScheduler() {
        snapshotScheduler.onRefreshStarted = { [weak self] in
            guard let self else { return }
            markSnapshotRefreshStarted()
        }
        snapshotScheduler.onRefreshProgress = { [weak self] completed, total in
            guard let self, isSnapshotRefreshRunning else { return }
            snapshotFeedback = .refreshing(completed: completed, total: total)
            updateOverlayIfVisible()
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
        case .optionShiftBacktick:
            handleOptionShiftBacktick()
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

    private func handleOptionShiftBacktick() {
        if overlay.isVisible {
            moveSelection(.previous)
            return
        }

        show()
    }

    private func show() {
        selectedIndex = focusedWorkspaceIndex(in: workspaces) ?? 0
        hasUserNavigatedSinceShow = false

        overlay.show(
            items: presentationItems(),
            selectedIndex: selectedIndex,
            isLoading: isSnapshotRefreshRunning,
            snapshotFeedback: snapshotFeedback
        )
        registerVisibleHotKeys()
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
            selectedIndex = max(0, selectedIndex - configuration.columns)
        case .down:
            selectedIndex = min(workspaces.count - 1, selectedIndex + configuration.columns)
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
        case let .success(fresh):
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
                snapshotFeedback = .failure("Could not load workspaces from AeroSpace")
                updateOverlayIfVisible()
                clearSnapshotFeedback(after: 4.0)
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
}

// MARK: - Snapshot refresh

extension SwitcherController {
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

        return true
    }

    private func markSnapshotRefreshStarted() {
        snapshotFeedbackClearWorkItem?.cancel()
        snapshotFeedbackClearWorkItem = nil
        isSnapshotRefreshRunning = true
        snapshotFeedback = .refreshing(completed: 0, total: 0)
        settingsModel.markSnapshotRefreshStarted()
        updateOverlayIfVisible()
    }

    private func markSnapshotRefreshFinished() {
        isSnapshotRefreshRunning = false
        snapshotFeedback = .success
        presentationCache = nil
        prewarmSnapshotCache()
        settingsModel.markSnapshotRefreshFinished()
        updateOverlayIfVisible()
        clearSnapshotFeedback(after: 2.0)
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
