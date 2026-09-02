import AeroKitCore
import AppKit
import SwiftUI

struct SwipeSettingsView: View {
    @ObservedObject var model: SwipeSettingsModel
    @ObservedObject var preferences: SwipePreferences
    let workspaceOrder: WorkspaceOrderStore
    let loadWorkspaces: @Sendable () throws -> [WorkspaceOrderEntry]
    /// Applies the user's own config edit. AeroKit never writes the
    /// AeroSpace config — this only runs `aerospace reload-config` after
    /// the user has pasted the line themselves.
    let reloadAerospaceConfig: @Sendable () throws -> Void

    @State private var hookStatus: WorkspaceChangeHook.Status?
    @State private var copiedNotice: String?
    @State private var reloadMessage: String?
    @State private var reloadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            trackpadSection

            if let message = model.systemGestureConflictMessage {
                SettingsErrorBanner(message)
            }

            behaviorSection
            workspaceOrderSection
            keyboardSwitchSection

            if let message = model.swipeErrorMessage {
                SettingsErrorBanner(message)
            }
        }
        .onAppear {
            model.refreshSystemGestureConflict(gestureEnabled: preferences.isEnabled)
            refreshHookStatus()
        }
    }

    private func refreshHookStatus() {
        Task {
            let status = await BlockingWork.run {
                WorkspaceChangeHook.status(executablePath: WorkspaceChangeHook.currentExecutablePath())
            }
            hookStatus = status
        }
    }

    private func reloadAerospace() {
        reloadMessage = nil
        Task {
            do {
                try await BlockingWork.run { try reloadAerospaceConfig() }
                reloadFailed = false
                reloadMessage = "AeroSpace reloaded"
                refreshHookStatus()
            } catch {
                reloadFailed = true
                reloadMessage = error.localizedDescription
            }
        }
    }

    private var trackpadSection: some View {
        SettingsSection("Trackpad") {
            SettingsRow(
                title: "Three-finger horizontal swipe",
                subtitle: "Swipe left or right to switch AeroSpace workspaces"
            ) {
                SettingsToggle(isOn: $preferences.isEnabled)
            }
            SettingsDivider()
            SettingsRow(
                title: "Natural direction",
                subtitle: "Content follows your fingers: swiping left moves to the workspace on the right"
            ) {
                SettingsToggle(isOn: $preferences.naturalDirection, isEnabled: preferences.isEnabled)
            }
        }
    }

    private var behaviorSection: some View {
        SettingsSection("Behavior") {
            wrapAroundRow
            SettingsDivider()
            skipEmptyRow
            SettingsDivider()
            showHUDRow
            SettingsDivider()
            stepDistanceRow
        }
    }

    private var workspaceOrderSection: some View {
        SettingsSection("Workspace Order") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Drag workspaces into the order swipes travel through — the switcher grid follows the same order")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                WorkspaceOrderEditor(
                    store: workspaceOrder,
                    loadWorkspaces: loadWorkspaces
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var keyboardSwitchSection: some View {
        SettingsSection("Keyboard Switches (Experimental)") {
            VStack(alignment: .leading, spacing: 10) {
                introText
                hookStatusRow
                wiringGuidance
                copyButtons
                if let notice = copiedNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if !preferences.showHUD {
                    hudOffNote
                }
                actionButtons
                if let message = reloadMessage {
                    reloadMessageView(message)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var introText: some View {
        Text(
            "Flash the workspace strip when AeroSpace keybindings switch workspaces. AeroKit never "
                + "edits your config — you paste the line yourself."
        )
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A fresh-line snippet under "needsMerge" without a merge would talk
    /// the user into deleting their existing hook — manual chaining
    /// instructions instead. Wired-but-stale gets the fresh line to replace
    /// the dead path with.
    @ViewBuilder private var wiringGuidance: some View {
        if let status = hookStatus, status.wiring != .wired || !status.wiredPathExists {
            if status.wiring == .needsMerge, status.mergedHookLine == nil {
                Text(
                    "Can't compose a merged line for this hook. Append "
                        + "'; <this app's path> --workspace-changed' to the end of its command, then reload."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    setupSteps
                    hookSnippet
                }
            }
        }
    }

    private var hudOffNote: some View {
        Text("“Show workspace strip” above is off — keyboard flashes stay hidden until it is on.")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionButtons: some View {
        HStack {
            Button("Reload AeroSpace config") {
                reloadAerospace()
            }
            .controlSize(.small)
            Button("Re-check") {
                reloadMessage = nil
                refreshHookStatus()
            }
            .controlSize(.small)
        }
    }

    private func reloadMessageView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(reloadFailed ? .orange : .secondary)
    }

    /// The paste-it-yourself recipe. Written out because the edit differs
    /// by config: a fresh file takes the line appended, an existing hook
    /// takes the merged replacement.
    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepRow(1, "Copy the line below — it calls AeroKit whenever the focused workspace changes.")
            stepRow(2, "Open \(hookStatus?.configPath ?? "~/.aerospace.toml") and \(pasteInstruction).")
            stepRow(3, "Save the file, then click \"Reload AeroSpace config\" below.")
        }
    }

    private var pasteInstruction: String {
        switch hookStatus?.wiring {
        case .needsMerge:
            "replace your exec-on-workspace-change line with the merged line below"
        default:
            "add the line below at the end of the file (replacing any old AeroKit line)"
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background {
                    Circle().fill(.quaternary.opacity(0.7))
                }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The line to paste: a fresh hook line, or — when an existing
    /// recognizable shell hook runs — that hook with AeroKit chained in.
    /// The line to copy: a fresh hook line, the composed merge for an
    /// existing shell hook, or nil when the layout needs a human.
    private var hookDisplayLine: String? {
        guard let status = hookStatus else { return nil }
        if status.wiring == .needsMerge {
            return status.mergedHookLine
        }
        return WorkspaceChangeFlash.tomlSnippet(
            executablePath: WorkspaceChangeHook.currentExecutablePath()
        )
    }

    /// A ready-to-paste instruction for an AI agent to perform the wiring.
    /// nil when nothing needs changing.
    private var aiPrompt: String? {
        guard let status = hookStatus, status.wiring != .wired else { return nil }
        let configPath = status.configPath ?? "~/.aerospace.toml"
        let exePath = WorkspaceChangeHook.currentExecutablePath()
        let footer = "Change nothing else in the file, then run `aerospace reload-config`."
        switch status.wiring {
        case .absent:
            let line = WorkspaceChangeFlash.tomlSnippet(executablePath: exePath)
            return "Edit \(configPath) (the AeroSpace config) and add this line:\n\n\(line)\n\n" + footer
        case .needsMerge:
            if let merged = status.mergedHookLine {
                return "Edit \(configPath) (the AeroSpace config): replace the existing "
                    + "exec-on-workspace-change line with exactly this one — it chains AeroKit "
                    + "after the current command:\n\n\(merged)\n\n" + footer
            }
            var prompt = "Edit \(configPath) (the AeroSpace config): find the "
                + "exec-on-workspace-change assignment"
            if let existing = status.existingHookLine {
                prompt += ", which currently reads:\n\n\(existing)"
            }
            prompt += "\n\nAppend `; \(exePath) --workspace-changed` inside its command string "
                + "(double-quote the path if it contains spaces). " + footer
            return prompt
        case .wired:
            return nil
        }
    }

    private func copyToPasteboard(_ text: String?, notice: String) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedNotice = notice
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedNotice = nil
        }
    }

    /// The two copy buttons: the raw line for a human, and a natural-
    /// language prompt an AI agent can execute to perform the same edit.
    private var copyButtons: some View {
        HStack(spacing: 8) {
            Button("Copy config line") {
                copyToPasteboard(hookDisplayLine, notice: "Config line copied")
            }
            .disabled(hookDisplayLine == nil)
            Button("Copy AI prompt") {
                copyToPasteboard(aiPrompt, notice: "AI prompt copied")
            }
            .disabled(aiPrompt == nil)
        }
        .controlSize(.small)
    }

    private var hookSnippet: some View {
        Group {
            if let line = hookDisplayLine {
                Text(line)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.7))
        }
    }

    @ViewBuilder private var hookStatusRow: some View {
        switch hookStatus?.wiring {
        case .wired:
            if hookStatus?.wiredPathExists == false, let stale = hookStatus?.wiredPath {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("The hook calls '\(stale)', which doesn't exist — replace it with the line below.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Configured — AeroSpace reports workspace changes to AeroKit")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        case .needsMerge:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("Your exec-on-workspace-change doesn't call AeroKit yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .absent:
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
                Text("Not configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case nil:
            Text("Checking hook status…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var wrapAroundRow: some View {
        SettingsRow(
            title: "Wrap around",
            subtitle: "Swiping past the last workspace continues from the first"
        ) {
            SettingsToggle(isOn: $preferences.wrapAround, isEnabled: preferences.isEnabled)
        }
    }

    private var skipEmptyRow: some View {
        SettingsRow(
            title: "Skip empty workspaces",
            subtitle: "Step over workspaces that have no windows"
        ) {
            SettingsToggle(isOn: $preferences.skipEmpty, isEnabled: preferences.isEnabled)
        }
    }

    private var showHUDRow: some View {
        SettingsRow(
            title: "Show workspace strip",
            subtitle: "Briefly display the workspace list after every switch — also gates keyboard-switch flashes"
        ) {
            // Not gated on `isEnabled`: keyboard-switch flashes only read
            // this preference, so a swipe-off user can still opt in here.
            SettingsToggle(isOn: $preferences.showHUD)
        }
    }

    private var stepDistanceRow: some View {
        SettingsRow(
            title: "Swipe distance per workspace",
            subtitle: "How far your fingers travel for each workspace step"
        ) {
            HStack(spacing: 8) {
                Slider(
                    value: $preferences.stepDistanceMM,
                    in: SwipePreferences.stepDistanceRange,
                    step: 5
                )
                .frame(width: 140)
                .disabled(!preferences.isEnabled)
                Text("\(Int(preferences.stepDistanceMM)) mm")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

@MainActor
final class SwipeSettingsModel: ObservableObject {
    @Published var swipeErrorMessage: String?
    @Published var systemGestureConflictMessage: String?

    /// The system's three-finger Space swipe cannot be consumed, so while
    /// it is on, every workspace swipe also slides the screen to another
    /// macOS Space. There is no reliable programmatic fix (the trackpad
    /// preference only applies on re-login), so surface the exact setting
    /// to change instead of a button.
    func refreshSystemGestureConflict(gestureEnabled: Bool) {
        systemGestureConflictMessage = gestureEnabled
            && SystemSwipeGestures.horizontalThreeFingerSpaceSwipeEnabled
            ? """
            macOS also reacts to three-finger horizontal swipes and slides \
            to another Space over the switched workspace. Set System \
            Settings → Trackpad → More Gestures → “Swipe between \
            full-screen applications” to Off or four fingers.
            """
            : nil
    }
}
