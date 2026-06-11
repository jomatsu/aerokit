import AeroKitCore
import AppKit
import SwiftUI

@MainActor
final class GeneralSettingsModel: ObservableObject {
    @Published private(set) var screenCaptureGranted = false

    @Published var launchAtLogin: Bool {
        didSet {
            // Comparing against the actual agent state both prevents redundant
            // launchctl calls and makes status-sync assignments no-ops.
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

    var needsRelaunch: Bool {
        screenCaptureGranted && !grantedAtLaunch
    }

    init() {
        grantedAtLaunch = ScreenCapturePermission.isGranted
        screenCaptureGranted = grantedAtLaunch
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func refreshStatus() {
        screenCaptureGranted = ScreenCapturePermission.isGranted
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func requestScreenCapturePermission() {
        _ = ScreenCapturePermission.request()
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
            SettingsSection("Permissions") {
                permissionRow
            }

            SettingsSection("General") {
                launchAtLoginRow
            }
        }
        .onAppear {
            model.refreshStatus()
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
