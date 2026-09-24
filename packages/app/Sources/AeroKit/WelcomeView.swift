import AeroKitCore
import SwiftUI

/// One page of the welcome tour: a feature, told in a line, then shown.
struct WelcomeFeature {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let demo: AnyView
}

/// First-run tour. Each page leads with a short headline and plays the same
/// drawn demo as the settings (i) buttons; the last page asks for the one
/// permission previews need.
struct WelcomeView: View {
    @ObservedObject var model: GeneralSettingsModel
    let features: [WelcomeFeature]
    let onFinish: () -> Void
    @State private var page = 0

    private var lastPage: Int {
        features.count + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if page == 0 {
                    introduction
                } else if page == lastPage {
                    permission
                } else {
                    featurePage(features[page - 1])
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(page)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 12)),
                removal: .opacity
            ))
            footer
        }
        .frame(width: 620, height: 640)
        .animation(.easeOut(duration: 0.22), value: page)
        .onAppear { model.refreshStatus() }
    }

    private func heading(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(
                title: L10n.tr("Welcome to AeroKit"),
                detail: L10n.tr("""
                With AeroSpace, Mission Control, App Exposé, and three-finger swipes between \
                desktops don’t work the way they should. AeroKit brings these familiar Mac \
                features to your AeroSpace workspaces.
                """)
            )
            AmbientDesktopDemo()
            aeroSpaceStatus
        }
    }

    private func featurePage(_ feature: WelcomeFeature) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(
                title: L10n.tr(feature.title),
                detail: L10n.tr(feature.detail)
            )
            feature.demo
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(
                title: L10n.tr("Show window previews"),
                detail: L10n.tr("""
                Allow Screen Recording so the lists can show pictures of your windows. The \
                pictures are saved only on this Mac.
                """)
            )
            PreviewCaptureDemo()
            permissionStatus
        }
    }

    private var aeroSpaceStatus: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("AeroSpace")).font(.system(size: 13, weight: .medium))
            switch model.aeroSpaceHealth {
            case nil:
                ProgressView().controlSize(.small)
            case .running:
                SettingsStatus(L10n.tr("Running"), ready: true)
            case .installedNotRunning:
                Spacer()
                Button(L10n.tr("Open AeroSpace")) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "bobko.aerospace") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
            case .notInstalled:
                SettingsStatus(L10n.tr("Not Installed"), ready: false)
                Spacer()
                Button(L10n.tr("Get AeroSpace…")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/nikitabobko/AeroSpace")!)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var permissionStatus: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("Screen Recording")).font(.system(size: 13, weight: .medium))
            if model.screenCaptureGranted, !model.needsRelaunch {
                SettingsStatus(L10n.tr("Granted"), ready: true)
            }
            Spacer(minLength: 0)
            if model.needsRelaunch {
                Button(L10n.tr("Relaunch to Apply")) { model.restartApplication() }
            } else if model.isRequestingScreenCapture {
                ProgressView().controlSize(.small)
            } else if !model.screenCaptureGranted {
                Button(L10n.tr("Allow Window Previews…")) { model.requestScreenCapturePermission() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0 ... lastPage, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.accentColor : Color.primary.opacity(0.14))
                        .frame(width: index == page ? 16 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.tr("Page \(page + 1) of \(lastPage + 1)"))
            Spacer()
            if page < lastPage {
                Button(L10n.tr("Skip")) { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .padding(.trailing, 6)
            }
            if page > 0 {
                Button(L10n.tr("Back")) { page -= 1 }
                    .controlSize(.large)
            }
            Button(page < lastPage ? L10n.tr("Next") : L10n.tr("Get Started")) {
                if page < lastPage {
                    page += 1
                } else {
                    onFinish()
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}
