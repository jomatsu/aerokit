import XCTest
@testable import AeroKitCore

final class CurrentAppScreenCaptureRegistrationTests: XCTestCase {
    func testResetUsesScopedTccutilArgumentsForDevBundleID() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects()

        _ = register(runner: runner, effects: effects)

        XCTAssertEqual(runner.calls, [
            FakeCommandRunner.Call(
                executable: "/usr/bin/tccutil",
                arguments: ["reset", "ScreenCapture", sampleDevBundleID]
            )
        ])
    }

    func testAlreadyGrantedDoesNotResetOrPrompt() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects(granted: true)

        let outcome = register(runner: runner, effects: effects)

        XCTAssertEqual(outcome, .alreadyGranted)
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(effects.requestCount, 0)
        XCTAssertEqual(effects.openSettingsCount, 0)
    }

    func testAlreadyGrantedDoesNotNeedAppIdentity() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects(granted: true)

        let outcome = register(runner: runner, identity: nil, effects: effects)

        XCTAssertEqual(outcome, .alreadyGranted)
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(effects.requestCount, 0)
    }

    func testMissingAppIdentityDoesNotInvokeUnscopedReset() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects()

        let outcome = register(runner: runner, identity: nil, effects: effects)

        XCTAssertEqual(outcome, .failed(.missingAppIdentity))
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(effects.requestCount, 0)
        XCTAssertEqual(effects.openSettingsCount, 0)
    }

    func testEmptyBundleIdentifierDoesNotInvokeUnscopedReset() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects()
        let identity = CurrentAppScreenCaptureRegistration.Identity(
            bundleIdentifier: "  ",
            displayName: "AeroKit Dev"
        )

        let outcome = register(runner: runner, identity: identity, effects: effects)

        XCTAssertEqual(outcome, .failed(.missingAppIdentity))
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(effects.requestCount, 0)
    }

    func testNonAppBundleIsNotAValidIdentity() {
        XCTAssertNil(
            CurrentAppScreenCaptureRegistration.Identity.fromRunningApp(
                pathExtension: "xctest",
                bundleIdentifier: sampleDevBundleID,
                displayName: "AeroKit Dev"
            )
        )
        XCTAssertNil(
            CurrentAppScreenCaptureRegistration.Identity.fromRunningApp(
                pathExtension: "app",
                bundleIdentifier: "",
                displayName: "AeroKit Dev"
            )
        )
        XCTAssertNil(
            CurrentAppScreenCaptureRegistration.Identity.fromRunningApp(
                pathExtension: "app",
                bundleIdentifier: nil,
                displayName: "AeroKit Dev"
            )
        )
        XCTAssertEqual(
            CurrentAppScreenCaptureRegistration.Identity.fromRunningApp(
                pathExtension: "app",
                bundleIdentifier: " \(sampleDevBundleID) ",
                displayName: " AeroKit Dev "
            ),
            CurrentAppScreenCaptureRegistration.Identity(
                bundleIdentifier: sampleDevBundleID,
                displayName: "AeroKit Dev"
            )
        )
    }

    func testResetFailureDoesNotRequestAccess() {
        let runner = FakeCommandRunner(error: ProcessRunnerError.nonZeroExit(
            executable: "/usr/bin/tccutil",
            arguments: ["reset", "ScreenCapture", sampleDevBundleID],
            result: ProcessResult(standardOutput: "", standardError: "denied", terminationStatus: 1)
        ))
        let effects = PermissionEffects()

        let outcome = register(runner: runner, effects: effects)

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(effects.requestCount, 0)
        XCTAssertEqual(effects.openSettingsCount, 0)
        guard case .failed(.resetFailed) = outcome else {
            return XCTFail("Expected resetFailed, got \(outcome)")
        }
        XCTAssertNotEqual(outcome, .completed(granted: true))
        XCTAssertNotEqual(outcome, .alreadyGranted)
    }

    func testResetTimeoutDoesNotRequestAccess() {
        let runner = FakeCommandRunner(error: ProcessRunnerError.timedOut(
            executable: "/usr/bin/tccutil",
            arguments: ["reset", "ScreenCapture", sampleDevBundleID],
            timeout: 10
        ))
        let effects = PermissionEffects()

        let outcome = register(runner: runner, effects: effects)

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(effects.requestCount, 0)
        XCTAssertEqual(effects.openSettingsCount, 0)
        guard case .failed(.resetFailed) = outcome else {
            return XCTFail("Expected resetFailed, got \(outcome)")
        }
    }

    func testSuccessfulResetIssuesExactlyOneRequest() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects()

        _ = register(runner: runner, effects: effects)

        XCTAssertEqual(effects.requestCount, 1)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testSuccessfulResetDoesNotReportGrantedWhenAccessDenied() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects()

        let outcome = register(runner: runner, effects: effects)

        XCTAssertEqual(outcome, .completed(granted: false))
        XCTAssertEqual(effects.openSettingsCount, 1)
        XCTAssertFalse(effects.granted)
    }

    func testOpensSettingsOnlyWhenStillUngranted() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects(requestReturns: true)

        let outcome = register(runner: runner, effects: effects)

        XCTAssertEqual(outcome, .completed(granted: true))
        XCTAssertEqual(effects.requestCount, 1)
        XCTAssertEqual(effects.openSettingsCount, 0)
    }

    func testPreflightAfterRequestCanCompleteGranted() {
        let runner = FakeCommandRunner()
        let effects = PermissionEffects(grantOnRequest: true)

        let outcome = register(runner: runner, effects: effects)

        XCTAssertEqual(outcome, .completed(granted: true))
        XCTAssertEqual(effects.requestCount, 1)
        XCTAssertEqual(effects.openSettingsCount, 0)
        XCTAssertEqual(runner.calls.count, 1)
    }

    private func register(
        runner: FakeCommandRunner,
        identity: CurrentAppScreenCaptureRegistration.Identity? = sampleDevIdentity,
        effects: PermissionEffects
    ) -> CurrentAppScreenCaptureRegistration.Outcome {
        let reset = CurrentAppScreenCaptureRegistration.resetCurrentApp(
            runner: runner,
            identity: identity
        ) { effects.granted }
        return CurrentAppScreenCaptureRegistration.complete(
            after: reset,
            isGranted: { effects.granted },
            requestAccess: { effects.request() },
            openSettings: { effects.openSettings() }
        )
    }
}

private let sampleDevBundleID = "com.nasubikun.aerokit.dev"
private let sampleDevIdentity = CurrentAppScreenCaptureRegistration.Identity(
    bundleIdentifier: sampleDevBundleID,
    displayName: "AeroKit Dev"
)

// MARK: - Test doubles

private final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    private(set) var calls: [Call] = []
    private let error: (any Error)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        if let error {
            throw error
        }
        return ProcessResult(standardOutput: "", standardError: "", terminationStatus: 0)
    }
}

private final class PermissionEffects: @unchecked Sendable {
    var granted: Bool
    var requestReturns: Bool
    var grantOnRequest: Bool
    private(set) var requestCount = 0
    private(set) var openSettingsCount = 0

    init(granted: Bool = false, requestReturns: Bool = false, grantOnRequest: Bool = false) {
        self.granted = granted
        self.requestReturns = requestReturns
        self.grantOnRequest = grantOnRequest
    }

    func request() -> Bool {
        requestCount += 1
        if grantOnRequest {
            granted = true
        }
        return requestReturns
    }

    func openSettings() {
        openSettingsCount += 1
    }
}
