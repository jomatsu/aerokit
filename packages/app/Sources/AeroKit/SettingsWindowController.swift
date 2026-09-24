import AeroKitCore
import AppKit
import CoreGraphics
import SwiftUI

/// Resizable settings window with persistent navigation and per-page scrolling.
@MainActor
final class SettingsWindowController {
    private static let contentSize = NSSize(width: 980, height: 760)

    private let content: AeroKitSettingsView
    private let welcome = WelcomePresentation()
    private let onWillShow: () -> Void
    private var window: NSWindow?
    /// Never removed: the coordinator keeps this controller for the app's
    /// lifetime, and a nonisolated deinit could not touch it anyway.
    private var languageObserver: (any NSObjectProtocol)?
    private var activationObserver: (any NSObjectProtocol)?

    init(
        client: AeroSpaceClient,
        workspacesPane: some View,
        windowsPane: some View,
        previewPane: some View,
        welcomeFeatures: [WelcomeFeature],
        onWillShow: @escaping () -> Void
    ) {
        let general = GeneralSettingsModel(client: client)
        content = AeroKitSettingsView(
            generalModel: general,
            welcome: welcome,
            welcomeFeatures: welcomeFeatures,
            workspacesPane: AnyView(workspacesPane),
            windowsPane: AnyView(windowsPane),
            previewPane: AnyView(previewPane)
        )
        self.onWillShow = onWillShow

        languageObserver = NotificationCenter.default.addObserver(
            forName: LanguagePreferences.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.window?.title = L10n.tr("AeroKit Settings") }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak general] _ in
            Task { @MainActor in
                guard self?.window?.isVisible == true else { return }
                general?.refreshStatus()
            }
        }
    }

    /// CGWindowID of the settings window once it has been shown.
    var windowID: CGWindowID? {
        window.map { CGWindowID($0.windowNumber) }
    }

    func show() {
        onWillShow()
        content.generalModel.refreshStatus()

        if window == nil {
            let hostingView = NSHostingView(rootView: content)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: Self.contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.tr("AeroKit Settings")
            window.contentMinSize = NSSize(width: 880, height: 620)
            window.setFrameAutosaveName("AeroKitSettings")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.isMovableByWindowBackground = false
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Opens the welcome tour as a sheet over the settings window.
    func presentWelcome() {
        welcome.isPresented = true
    }
}

/// Whether the welcome tour sheet is up; shared by the window controller,
/// which opens it on first launch, and the General page's replay button.
@MainActor
final class WelcomePresentation: ObservableObject {
    static let shownKey = "welcome.shown"

    @Published var isPresented = false

    func finish() {
        isPresented = false
        UserDefaults.standard.set(true, forKey: Self.shownKey)
    }
}

// MARK: - Root view

struct AeroKitSettingsView: View {
    @ObservedObject var generalModel: GeneralSettingsModel
    @ObservedObject var welcome: WelcomePresentation
    let welcomeFeatures: [WelcomeFeature]
    let workspacesPane: AnyView
    let windowsPane: AnyView
    let previewPane: AnyView

    @State private var selected: SettingsDestination = .general
    @State private var visited: Set<SettingsDestination> = [.general]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("AeroKit").font(.title2.bold()).padding(.horizontal, 20).padding(.top, 24)
                List(selection: $selected) {
                    ForEach(SettingsDestination.allCases) { destination in
                        Label(destination.title, systemImage: destination.icon)
                            .padding(.vertical, 7)
                            .tag(destination)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 190)
            .background(SettingsBackdrop())
            Divider()
            // Keep visited scroll views alive so each page retains its own position.
            ZStack {
                ForEach(SettingsDestination.allCases.filter { visited.contains($0) }) { destination in
                    ScrollView {
                        pane(destination)
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(28)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .opacity(selected == destination ? 1 : 0)
                    .allowsHitTesting(selected == destination)
                    .disabled(selected != destination)
                    .accessibilityHidden(selected != destination)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(\.locale, LanguagePreferences.shared.selected.locale)
        .environment(\.openSettingsDestination) { selected = $0 }
        .sheet(isPresented: $welcome.isPresented) {
            WelcomeView(model: generalModel, features: welcomeFeatures) { welcome.finish() }
                .environment(\.locale, LanguagePreferences.shared.selected.locale)
        }
        .onChange(of: selected) {
            KeyRecordingSession.shared.stop()
            visited.insert(selected)
            generalModel.refreshStatus()
        }
    }

    @ViewBuilder
    private func pane(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .general: GeneralSettingsView(model: generalModel) { welcome.isPresented = true }
        case .workspaces: workspacesPane
        case .windows: windowsPane
        case .previews: previewPane
        }
    }
}
