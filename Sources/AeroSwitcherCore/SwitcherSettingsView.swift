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
            header

            section("Permissions") {
                permissionRow
            }

            section("General") {
                launchAtLoginRow
                divider
                switchOnReleaseRow
                divider
                hideEmptyRow
                divider
                overlayHintsRow
                divider
                gridColumnsRow
            }

            section("Workspace Previews") {
                autoRefreshRow
                divider
                frequencyRow
                divider
                lastUpdatedRow
            }

            if let message = model.lastErrorMessage {
                errorBanner(message)
            }

            section("Shortcuts") {
                hotKeyRow
                divider
                shortcutDisplayRow(title: "Cycle backwards", keys: backwardKeys)
                divider
                refreshShortcutRow
                divider
                settingsShortcutRow
            }

            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: 460)
        .background {
            SettingsBackdrop().ignoresSafeArea()
        }
        .onAppear {
            model.refreshStatus()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            appIconChip

            VStack(alignment: .leading, spacing: 1) {
                Text("AeroSwitcher")
                    .font(.system(size: 17, weight: .semibold))
                Text("Workspace switcher for AeroSpace")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    private var appIconChip: some View {
        RoundedRectangle(cornerRadius: 9.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.33, green: 0.55, blue: 1.0),
                        Color(red: 0.52, green: 0.34, blue: 0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color(red: 0.4, green: 0.45, blue: 1.0).opacity(0.35), radius: 6, y: 2)
    }

    // MARK: - Permission row

    private var permissionRow: some View {
        SettingsRow(
            title: "Screen Recording",
            subtitle: "Required to capture workspace previews"
        ) {
            if model.needsRelaunch {
                Button("Relaunch to Apply") {
                    model.restartApplication()
                }
                .controlSize(.small)
            } else if model.screenCaptureGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Grant Access…") {
                    model.requestScreenCapturePermission()
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - General rows

    private var launchAtLoginRow: some View {
        SettingsRow(
            title: "Launch at Login",
            subtitle: model.launchAtLoginAvailable
                ? "Start AeroSwitcher automatically"
                : "Available when running the installed app"
        ) {
            SettingsToggle(isOn: $model.launchAtLogin, isEnabled: model.launchAtLoginAvailable)
        }
    }

    private var switchOnReleaseRow: some View {
        SettingsRow(
            title: "Switch on Release",
            subtitle: "Tap the hotkey to jump straight to the next workspace"
        ) {
            SettingsToggle(isOn: $preferences.switchOnRelease)
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

// MARK: - Sections & footer

extension SwitcherSettingsView {
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)

            VStack(spacing: 0, content: content)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary.opacity(0.45))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
                }
        }
    }

    private var divider: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, 14)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.orange.opacity(0.12))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open Snapshots Folder") {
                model.openSnapshotFolder()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))

            Spacer()

            Button("Quit AeroSwitcher") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}
