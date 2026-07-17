import AeroKitCore
import SwiftUI

struct SwitcherSettingsView: View {
    @ObservedObject var model: SwitcherSettingsModel
    @ObservedObject var preferences: AppPreferences

    init(model: SwitcherSettingsModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("General") {
                switchOnReleaseRow
                SettingsDivider()
                preselectNextRow
                SettingsDivider()
                hideEmptyRow
                SettingsDivider()
                overlayHintsRow
                SettingsDivider()
                gridColumnsRow
            }

            SettingsSection("Workspace Order") {
                workspaceOrderRow
            }

            SettingsSection("Workspace Previews") {
                autoRefreshRow
                SettingsDivider()
                frequencyRow
                SettingsDivider()
                lastUpdatedRow
                SettingsDivider()
                excludeAppsRow
            }

            if let message = model.lastErrorMessage {
                SettingsErrorBanner(message)
            }

            SettingsSection("Shortcuts") {
                hotKeyRow
                SettingsDivider()
                shortcutDisplayRow(title: "Cycle backwards", keys: backwardKeys)
                SettingsDivider()
                refreshShortcutRow
                SettingsDivider()
                settingsShortcutRow
            }

            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(message)
            }

            footer
        }
        .onAppear {
            model.refreshStatus()
        }
    }

    private var switchOnReleaseRow: some View {
        SettingsRow(
            title: "Switch on Release",
            subtitle: "Releasing the modifier switches, ⌘⇥ style. Off: confirm with Return"
        ) {
            SettingsToggle(isOn: $preferences.switchOnRelease)
        }
    }

    private var preselectNextRow: some View {
        SettingsRow(
            title: "Start on Next Workspace",
            subtitle: "Open with the adjacent workspace pre-selected instead of the current one"
        ) {
            SettingsToggle(isOn: $preferences.preselectNextOnOpen)
        }
    }

    private var hideEmptyRow: some View {
        SettingsRow(
            title: "Hide Empty Workspaces",
            subtitle: "Only show workspaces with windows"
        ) {
            SettingsToggle(isOn: $preferences.hideEmptyWorkspaces)
        }
    }

    private var overlayHintsRow: some View {
        SettingsRow(
            title: "Shortcut Hints",
            subtitle: "Show key hints below the switcher"
        ) {
            SettingsToggle(isOn: $preferences.showOverlayHints)
        }
    }

    private var workspaceOrderRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag workspaces into the order they appear in the grid — swiping follows the same order")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            WorkspaceOrderEditor(
                store: model.workspaceOrder,
                loadWorkspaces: model.loadWorkspaces
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var gridColumnsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Grid Layout")
                    .font(.system(size: 12.5, weight: .medium))
                Text("How workspaces are arranged in the switcher")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            GridLayoutPicker(selection: $preferences.gridColumns, range: 2 ... 6)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Preview rows

    private var autoRefreshRow: some View {
        SettingsRow(
            title: "Auto Refresh",
            subtitle: "Capture previews in the background"
        ) {
            SettingsToggle(isOn: $preferences.autoRefresh)
        }
    }

    private var frequencyRow: some View {
        SettingsRow(
            title: "Update Frequency",
            subtitle: "How often previews may refresh"
        ) {
            Picker("", selection: $preferences.refreshFrequency) {
                ForEach(SnapshotRefreshFrequency.allCases) { frequency in
                    Text(frequency.shortLabel).tag(frequency)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
            .disabled(!preferences.autoRefresh)
        }
    }

    private var lastUpdatedRow: some View {
        SettingsRow(title: "Previews", subtitle: lastUpdatedText) {
            if model.isRefreshingSnapshots {
                RefreshProgressRing(progress: ringProgress)
            } else {
                Button {
                    model.refreshSnapshots()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh previews now")
                .disabled(!model.screenCaptureGranted)
            }
        }
    }

    private var excludeAppsRow: some View {
        SettingsRow(
            title: "Exclude Apps",
            subtitle: "App names or bundle IDs, comma-separated — their windows are never saved"
        ) {
            TextField("1Password, com.apple.Passwords", text: $preferences.snapshotExcludedApps)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 220)
                .font(.system(size: 11))
        }
    }

    private var ringProgress: Double? {
        guard let progress = model.refreshProgress, progress.total > 0 else {
            return nil
        }
        return Double(progress.completed) / Double(progress.total)
    }

    private var lastUpdatedText: LocalizedStringKey {
        if model.isRefreshingSnapshots {
            if let progress = model.refreshProgress {
                return "Refreshing \(progress.completed) of \(progress.total)…"
            }
            return "Refreshing…"
        }
        guard let modifiedAt = model.snapshotModifiedAt else {
            return "Not captured yet"
        }
        return "Updated \(Text(modifiedAt, style: .relative)) ago"
    }

    // MARK: - Shortcut rows

    private var hotKeyRow: some View {
        SettingsRow(
            title: "Show Switcher",
            subtitle: "Hold the modifier and press again to cycle"
        ) {
            HotKeyRecorder(
                spec: $preferences.hotKey,
                validate: { isFree($0, excluding: \.hotKey) },
                onRecordingChanged: { model.setHotKeyRecording($0) }
            )
        }
    }

    private var refreshShortcutRow: some View {
        SettingsRow(
            title: "Refresh previews",
            subtitle: "While the switcher is open"
        ) {
            HotKeyRecorder(
                spec: $preferences.refreshShortcut,
                validate: { isFree($0, excluding: \.refreshShortcut) },
                onRecordingChanged: { model.setHotKeyRecording($0) }
            )
        }
    }

    private var settingsShortcutRow: some View {
        SettingsRow(
            title: "Open settings",
            subtitle: "While the switcher is open"
        ) {
            HotKeyRecorder(
                spec: $preferences.settingsShortcut,
                validate: { isFree($0, excluding: \.settingsShortcut) },
                onRecordingChanged: { model.setHotKeyRecording($0) }
            )
        }
    }

    private func isFree(
        _ candidate: HotKeySpec,
        excluding own: KeyPath<AppPreferences, HotKeySpec>
    ) -> Bool {
        let others: [KeyPath<AppPreferences, HotKeySpec>] = [
            \.hotKey, \.refreshShortcut, \.settingsShortcut
        ].filter { $0 != own }
        return others.allSatisfy { keyPath in
            let existing = preferences[keyPath: keyPath]
            return existing.keyCode != candidate.keyCode
                || existing.modifierFlags != candidate.modifierFlags
        }
    }

    private var backwardKeys: [String] {
        let keys = preferences.hotKey.displayKeys
        return keys.dropLast() + ["⇧"] + keys.suffix(1)
    }

    private func shortcutDisplayRow(title: String, keys: [String]) -> some View {
        SettingsRow(title: title) {
            KeyCapGroup(keys: keys)
        }
    }
}

// MARK: - Footer

extension SwitcherSettingsView {
    private var footer: some View {
        HStack {
            Button("Open Snapshots Folder") {
                model.openSnapshotFolder()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))

            Spacer()
        }
        .padding(.top, 2)
    }
}
