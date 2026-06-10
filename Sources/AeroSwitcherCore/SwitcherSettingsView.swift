import SwiftUI

struct SwitcherSettingsView: View {
    @ObservedObject var model: SwitcherSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            permissionSection
            snapshotSection
            Text(model.statusMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            model.refreshStatus()
        }
    }

    private var header: some View {
        HStack {
            Text("AeroSwitcher")
                .font(.system(size: 22, weight: .semibold))
            Spacer()
        }
    }

    private var permissionSection: some View {
        GroupBox("Screen Recording") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.screenCaptureGranted ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(model.screenCaptureGranted ? "Granted" : "Not Granted")
                        .font(.system(size: 14, weight: .medium))
                }

                Text(
                    "Snapshots refresh only when Screen Recording is granted."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Request Permission") {
                        model.requestScreenCapturePermission()
                    }

                    if model.screenCaptureGranted {
                        Button("Restart AeroSwitcher") {
                            model.restartApplication()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private var snapshotSection: some View {
        GroupBox("Workspace Snapshots") {
            VStack(alignment: .leading, spacing: 12) {
                labeledText(title: "Current directory", value: model.snapshotDirectoryPath)
                labeledText(title: "Last updated", value: model.snapshotModifiedText)

                HStack {
                    Button(model.isRefreshingSnapshots ? "Refreshing..." : "Refresh Snapshots") {
                        model.refreshSnapshots()
                    }
                    .disabled(!model.screenCaptureGranted || model.isRefreshingSnapshots)

                    Button("Open Folder") {
                        model.openSnapshotFolder()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private func labeledText(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
