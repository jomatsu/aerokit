import CoreGraphics
import Foundation

private let log = AppLog(category: "core")

/// Explicit Screen Recording authorization-recovery attempt for the running app,
/// scoped to its bundle identifier.
///
/// Reset clears authorization; neither reset nor opening Settings guarantees
/// that this running build is registered or granted. Reset happens at most once
/// per Grant Access press, before that request — never after a denial, and
/// never without a bundle identifier.
public enum CurrentAppScreenCaptureRegistration {
    public struct Identity: Equatable, Sendable {
        public let bundleIdentifier: String
        public let displayName: String

        public init(bundleIdentifier: String, displayName: String) {
            self.bundleIdentifier = bundleIdentifier
            self.displayName = displayName
        }

        /// The running bundle when it is a real `.app` with a nonempty identifier.
        /// Dev and release IDs are read from the process, never inferred.
        public static func fromRunningBundle(_ bundle: Bundle = .main) -> Self? {
            fromRunningApp(
                pathExtension: bundle.bundleURL.pathExtension,
                bundleIdentifier: bundle.bundleIdentifier,
                displayName: displayName(in: bundle)
            )
        }

        /// Name shown in Settings so AeroKit and AeroKit Dev stay distinguishable.
        public static func runningDisplayName(_ bundle: Bundle = .main) -> String {
            if let identity = fromRunningBundle(bundle) {
                return identity.displayName
            }
            let name = displayName(in: bundle).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "this app" : name
        }

        static func fromRunningApp(
            pathExtension: String,
            bundleIdentifier: String?,
            displayName: String
        ) -> Self? {
            guard pathExtension == "app" else {
                return nil
            }
            let identifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !identifier.isEmpty else {
                return nil
            }
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self(
                bundleIdentifier: identifier,
                displayName: name.isEmpty ? identifier : name
            )
        }

        static func displayName(in bundle: Bundle) -> String {
            for key in ["CFBundleDisplayName", kCFBundleNameKey as String] {
                if let value = bundle.object(forInfoDictionaryKey: key) as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
            return bundle.bundleURL.deletingPathExtension().lastPathComponent
        }
    }

    public enum ResetOutcome: Equatable, Sendable {
        case alreadyGranted
        /// `tccutil reset` ran for this app. This is not a Screen Recording grant.
        case succeeded
        case failed(Failure)
    }

    public enum Outcome: Equatable, Sendable {
        case alreadyGranted
        /// Reset ran (when needed) and one request was issued. `granted` is the
        /// live access state — never implied by a successful reset alone.
        case completed(granted: Bool)
        case failed(Failure)
    }

    public enum Failure: Equatable, Sendable {
        case missingAppIdentity
        case resetFailed
    }

    /// TCC reset only. Call from `BlockingWork`; do not prompt here.
    public static func resetCurrentApp() -> ResetOutcome {
        resetCurrentApp(
            runner: ProcessRunner(),
            identity: Identity.fromRunningBundle()
        ) { ScreenCapturePermission.isGranted }
    }

    public static func resetCurrentApp(
        runner: any CommandRunning,
        identity: Identity?,
        isGranted: @Sendable () -> Bool
    ) -> ResetOutcome {
        if isGranted() {
            return .alreadyGranted
        }

        let bundleIdentifier = identity?.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundleIdentifier.isEmpty else {
            log.error(
                "ScreenCapture reset skipped: running bundle is not an .app with a nonempty identifier"
            )
            return .failed(.missingAppIdentity)
        }

        do {
            _ = try runner.run(
                "/usr/bin/tccutil",
                arguments: ["reset", "ScreenCapture", bundleIdentifier]
            )
        } catch {
            log.error("tccutil reset ScreenCapture \(bundleIdentifier) failed: \(error)")
            return .failed(.resetFailed)
        }

        return .succeeded
    }

    /// Issues `CGRequestScreenCaptureAccess` after a successful reset.
    /// A failed reset must not reach a request.
    @MainActor
    public static func complete(after reset: ResetOutcome) -> Outcome {
        complete(
            after: reset,
            isGranted: { ScreenCapturePermission.isGranted },
            requestAccess: { CGRequestScreenCaptureAccess() },
            openSettings: { ScreenCapturePermission.openSettings() }
        )
    }

    public static func complete(
        after reset: ResetOutcome,
        isGranted: () -> Bool,
        requestAccess: () -> Bool,
        openSettings: () -> Void
    ) -> Outcome {
        switch reset {
        case .alreadyGranted:
            return .alreadyGranted
        case let .failed(failure):
            return .failed(failure)
        case .succeeded:
            let granted = requestAccess() || isGranted()
            if !granted {
                openSettings()
            }
            return .completed(granted: granted)
        }
    }
}
