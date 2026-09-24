import AeroKitCore
import AppKit
import SwiftUI

struct SwipeDisplaySettingsView: View {
    @ObservedObject var preferences: SwipePreferences
    let reloadAerospaceConfig: @Sendable () throws -> Void
    @State private var hookStatus: WorkspaceChangeHook.Status?
    @State private var showingIntegration = false

    var body: some View {
        SettingsSection(L10n.tr("Workspace names when switching")) {
            SettingsToggleRow(
                L10n.tr("Show workspace names while switching"),
                subtitle: L10n.tr("A small strip shows where you are as you switch."),
                isOn: $preferences.showHUD
            )
            SettingsDivider()
            integrationRow
        }
        .onAppear { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .sheet(isPresented: $showingIntegration, onDismiss: refreshStatus) {
            WorkspaceIntegrationView(preferences: preferences, reloadAerospaceConfig: reloadAerospaceConfig)
        }
    }

    private var integrationRow: some View {
        SettingsRow(
            title: L10n.tr("Also show names when using AeroSpace (Experimental)"),
            subtitle: L10n.tr("Show the same strip after switches made with AeroSpace shortcuts or commands.")
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                Text(integrationStatus).font(.caption).foregroundStyle(.secondary)
                Button(hookStatus?.wiring == .wired ? L10n.tr("Review Setup…") : L10n.tr("Set Up…")) {
                    showingIntegration = true
                }
            }
        }
    }

    private var integrationStatus: String {
        guard let hookStatus else { return L10n.tr("Checking…") }
        if hookStatus.wiring == .wired, hookStatus.wiredPathExists {
            return preferences.showHUD ? L10n.tr("Configured") : L10n.tr("Configured (strip hidden)")
        }
        return hookStatus.wiring == .wired ? L10n.tr("Needs repair") : L10n.tr("Not configured")
    }

    private func refreshStatus() {
        Task {
            hookStatus = await BlockingWork.run {
                WorkspaceChangeHook.status(executablePath: WorkspaceChangeHook.currentExecutablePath())
            }
        }
    }
}
