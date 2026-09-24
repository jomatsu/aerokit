import AeroKitCore
import AppKit
import SwiftUI

@MainActor
final class GeneralSettingsModel: ObservableObject {
    @Published private(set) var screenCaptureGranted = false

    /// nil while a probe is in flight (also the initial state).
    @Published private(set) var aeroSpaceHealth: AeroSpaceHealth?

    @Published private(set) var isRequestingScreenCapture = false
    @Published private(set) var screenCaptureError: LocalizedStringResource?

    @Published var launchAtLogin: Bool {
        didSet {
            // Comparing against the actual SMAppService state both prevents
            // redundant register/unregister calls and makes status-sync
            // assignments no-ops.
            guard launchAtLogin != LaunchAtLogin.isEnabled else {
                return
            }
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    let launchAtLoginAvailable = LaunchAtLogin.isAvailable

    /// Screen Recording grants only take effect after a relaunch, so remember
    /// the state the process started with to know when a relaunch is pending.
    private let grantedAtLaunch: Bool

    /// Running bundle's display name so Dev and release are distinguishable.
    let currentAppDisplayName: String

    var screenCaptureHelp: String {
        L10n.tr("""
        Uses macOS Screen Recording permission to show your windows. \
        Allow \(currentAppDisplayName) in System Settings.
        """)
    }

    private let client: AeroSpaceClient
    private var healthTask: Task<Void, Never>?

    var needsRelaunch: Bool {
        screenCaptureGranted && !grantedAtLaunch
    }

    init(client: AeroSpaceClient) {
        self.client = client
        grantedAtLaunch = ScreenCapturePermission.isGranted
        screenCaptureGranted = grantedAtLaunch
        launchAtLogin = LaunchAtLogin.isEnabled
        currentAppDisplayName = CurrentAppScreenCaptureRegistration.Identity.runningDisplayName()
    }

    func refreshStatus() {
        screenCaptureGranted = ScreenCapturePermission.isGranted
        if screenCaptureGranted {
            screenCaptureError = nil
        }
        launchAtLogin = LaunchAtLogin.isEnabled
        refreshAeroSpaceHealth()
    }

    private func refreshAeroSpaceHealth() {
        // One probe at a time; refreshStatus fires on every window
        // activation and the CLI fallback can take tens of milliseconds.
        guard healthTask == nil else { return }
        let client = client
        healthTask = Task { [weak self] in
            let health = await BlockingWork.run { client.checkHealth() }
            self?.aeroSpaceHealth = health
            self?.healthTask = nil
        }
    }

    /// Reset this build's Screen Recording TCC entry, then request access.
    /// Only `tccutil` hops off the main actor; the system prompt and Settings
    /// link stay on the main actor. A second press is ignored until it finishes.
    func requestScreenCapturePermission() {
        guard !isRequestingScreenCapture else { return }
        screenCaptureError = nil
        if ScreenCapturePermission.isGranted {
            screenCaptureGranted = true
            return
        }
        isRequestingScreenCapture = true
        Task { @MainActor [weak self] in
            let reset = await BlockingWork.run {
                CurrentAppScreenCaptureRegistration.resetCurrentApp()
            }
            self?.completeScreenCaptureRegistration(reset)
        }
    }

    private func completeScreenCaptureRegistration(
        _ reset: CurrentAppScreenCaptureRegistration.ResetOutcome
    ) {
        let outcome = CurrentAppScreenCaptureRegistration.complete(after: reset)
        switch outcome {
        case .alreadyGranted, .completed:
            screenCaptureError = nil
        case .failed(.missingAppIdentity):
            screenCaptureError = "Couldn't identify this running app, so Screen Recording was not reset."
        case .failed(.resetFailed):
            screenCaptureError = "Couldn't re-register \(currentAppDisplayName) for Screen Recording."
        }
        isRequestingScreenCapture = false
        refreshStatus()
    }

    func openScreenRecordingSettings() {
        ScreenCapturePermission.openSettings()
    }

    func restartApplication() {
        ApplicationRelauncher.relaunch()
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: GeneralSettingsModel
    let showWelcome: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPageHeader(
                L10n.tr("General"),
                subtitle: L10n.tr("Check AeroSpace status, permissions, and basic app options.")
            )
            SettingsSection(L10n.tr("Basics")) {
                languageRow
                SettingsDivider()
                launchAtLoginRow
            }

            SettingsSection(L10n.tr("AeroSpace")) {
                AeroSpaceStatusRow(model: model)
            }

            SettingsSection(L10n.tr("Permissions")) {
                ScreenCapturePermissionRow(model: model)
            }

            if let message = model.screenCaptureError {
                SettingsErrorBanner(
                    L10n.tr(message),
                    actionTitle: L10n.tr("Open Screen Recording Settings…")
                ) {
                    model.openScreenRecordingSettings()
                }
            }

            versionRow
        }
        .onAppear {
            model.refreshStatus()
        }
    }

    private var languageRow: some View {
        @Bindable var languages = LanguagePreferences.shared
        return SettingsRow(
            title: L10n.tr("Language"),
            subtitle: L10n.tr("Choose the language used in AeroKit. Changes apply immediately.")
        ) {
            Picker(L10n.tr("Language"), selection: $languages.selected) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private var versionRow: some View {
        HStack {
            Text(L10n.tr("Version"))
            Text(AppVersion.current)
            Spacer()
            Button(L10n.tr("Show Welcome Tour…"), action: showWelcome)
                .buttonStyle(.link)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
    }

    private var launchAtLoginRow: some View {
        SettingsToggleRow(
            L10n.tr("Open AeroKit when you log in"),
            subtitle: model
                .launchAtLoginAvailable ? L10n
                .tr("Keep workspace and window shortcuts ready whenever you start your Mac.") :
                L10n.tr("Available in the installed app."),
            isOn: $model.launchAtLogin
        )
        .disabled(!model.launchAtLoginAvailable)
    }
}

/// Whether AeroSpace is running, with the fix when it isn't. Shared by the
/// General page and the welcome tour.
struct AeroSpaceStatusRow: View {
    @ObservedObject var model: GeneralSettingsModel

    var body: some View {
        switch model.aeroSpaceHealth {
        case nil:
            SettingsRow(
                title: L10n.tr("AeroSpace"),
                subtitle: L10n.tr("Checking whether your workspace manager is running…")
            ) {
                ProgressView().controlSize(.small)
            }
        case .running:
            SettingsRow(
                title: L10n.tr("AeroSpace"),
                subtitle: L10n.tr("AeroKit can find and switch your workspaces.")
            ) {
                Label(L10n.tr("Running"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
        case .installedNotRunning:
            SettingsRow(
                title: L10n.tr("AeroSpace"),
                subtitle: L10n.tr("Open AeroSpace to use workspace switching and window previews.")
            ) {
                Button(L10n.tr("Open AeroSpace")) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "bobko.aerospace") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
            }
        case .notInstalled:
            SettingsRow(
                title: L10n.tr("AeroSpace"),
                subtitle: L10n.tr("AeroKit requires the AeroSpace window manager")
            ) {
                HStack(spacing: 10) {
                    Label(L10n.tr("Not Installed"), systemImage: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                    Button(L10n.tr("Get AeroSpace…")) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/nikitabobko/AeroSpace")!)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Screen Recording status with the action that grants or applies it.
struct ScreenCapturePermissionRow: View {
    @ObservedObject var model: GeneralSettingsModel

    var body: some View {
        SettingsRow(
            title: L10n.tr("Show previews of your windows"),
            subtitle: model.screenCaptureGranted ? nil : model.screenCaptureHelp
        ) {
            if model.needsRelaunch {
                Button(L10n.tr("Relaunch to Apply")) {
                    model.restartApplication()
                }
                .controlSize(.small)
            } else if model.screenCaptureGranted {
                Label(L10n.tr("Granted"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else if model.isRequestingScreenCapture {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(L10n.tr("Allow Window Previews…")) {
                    model.requestScreenCapturePermission()
                }
                .controlSize(.small)
            }
        }
    }
}
