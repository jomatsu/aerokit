import AeroKitCore
import AppKit
import SwiftUI

@MainActor
final class GeneralSettingsModel: ObservableObject {
    @Published private(set) var screenCaptureGranted = false

    /// nil while a probe is in flight (also the initial state).
    @Published private(set) var aeroSpaceHealth: AeroSpaceHealth?

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
    }

    func refreshStatus() {
        screenCaptureGranted = ScreenCapturePermission.isGranted
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

    func requestScreenCapturePermission() {
        _ = ScreenCapturePermission.request()
        if !ScreenCapturePermission.isGranted {
            ScreenCapturePermission.openSettings()
        }
        refreshStatus()
    }

    func restartApplication() {
        ApplicationRelauncher.relaunch()
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: GeneralSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("AeroSpace") {
                aeroSpaceRow
            }

            SettingsSection("Permissions") {
                permissionRow
            }

            SettingsSection("General") {
                launchAtLoginRow
                SettingsDivider()
                versionRow
            }
        }
        .onAppear {
            model.refreshStatus()
        }
    }

    @ViewBuilder private var aeroSpaceRow: some View {
        switch model.aeroSpaceHealth {
        case nil:
            SettingsRow(
                title: "AeroSpace",
                subtitle: "Checking the AeroSpace server…"
            ) {
                ProgressView().controlSize(.small)
            }
        case .running:
            SettingsRow(
                title: "AeroSpace",
                subtitle: "Connected to the AeroSpace server"
            ) {
                Label("Running", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
        case .installedNotRunning:
            SettingsRow(
                title: "AeroSpace",
                subtitle: "The CLI is installed but the server did not respond — start AeroSpace"
            ) {
                Label("Not Running", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        case .notInstalled:
            SettingsRow(
                title: "AeroSpace",
                subtitle: "AeroKit requires the AeroSpace window manager"
            ) {
                HStack(spacing: 10) {
                    Label("Not Installed", systemImage: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                    Button("Get AeroSpace…") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/nikitabobko/AeroSpace")!)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var versionRow: some View {
        SettingsRow(title: "Version") {
            Text(AppVersion.current)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var permissionRow: some View {
        SettingsRow(
            title: "Screen Recording",
            subtitle: "Required for workspace previews and the window overview"
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

    private var launchAtLoginRow: some View {
        SettingsRow(
            title: "Launch at Login",
            subtitle: model.launchAtLoginAvailable
                ? "Start AeroKit automatically"
                : "Available when running the installed app"
        ) {
            SettingsToggle(isOn: $model.launchAtLogin, isEnabled: model.launchAtLoginAvailable)
        }
    }
}
