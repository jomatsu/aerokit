import AppKit

/// The app the user was in before AeroKit came to the front. "This app's
/// windows" means that app whenever AeroKit's own settings window holds
/// focus — for example after clicking Try — never AeroKit itself.
@MainActor
public final class PreviousApplicationTracker {
    public struct Application: Equatable, Sendable {
        public var bundleIdentifier: String
        public var pid: Int32
    }

    public private(set) var application: Application?
    private var observer: (any NSObjectProtocol)?

    public init() {}

    public func start() {
        record(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.record(app) }
        }
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        application = Application(bundleIdentifier: app.bundleIdentifier ?? "", pid: app.processIdentifier)
    }
}
