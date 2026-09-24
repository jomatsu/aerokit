import AppKit
import CoreGraphics
import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

@MainActor
final class WindowSwitcherControllerLifecycleTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "WindowSwitcherControllerLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "expose.windowSwitchEnabled")
        HotKeySpec(keyCode: KeyCode.space, modifierRawValue: NSEvent.ModifierFlags.option.rawValue)
            .store(in: defaults, key: "expose.windowSwitchHotKey")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDisabledByDefaultIgnoresCycleHotkeys() {
        defaults.set(false, forKey: "expose.windowSwitchEnabled")
        let runner = PresentationCommandRunner()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(runner.invocations.isEmpty)
        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertTrue(host.events.isEmpty)
    }

    /// v0.2.x stored only the switch; an enabled user ran on the implicit
    /// ⌥Tab and must keep it after the switch folds into the shortcut.
    func testLegacyEnabledPreferenceWithoutShortcutMigratesToOptionTab() {
        defaults.removeObject(forKey: "expose.windowSwitchHotKey")
        let preferences = ExposePreferences(defaults: defaults)
        let host = FakeSwitcherHost()
        let controller = WindowSwitcherController(
            client: PresentationCommandRunner().makeClient(),
            preferences: preferences,
            hooks: host.hooks(modifiersHeld: true, stacking: [])
        )
        controller.start()

        let optionTab = HotKeySpec(keyCode: KeyCode.tab, modifierRawValue: NSEvent.ModifierFlags.option.rawValue)
        XCTAssertEqual(preferences.windowSwitchHotKey, optionTab)
        XCTAssertEqual(host.hotKeys.registrations[.windowCycleForward]?.keyCode, UInt32(KeyCode.tab))
        XCTAssertNil(defaults.object(forKey: "expose.windowSwitchEnabled"))
        XCTAssertEqual(ExposePreferences(defaults: defaults).windowSwitchHotKey, optionTab)
    }

    func testLegacyDisabledPreferenceClearsStoredShortcut() {
        defaults.set(false, forKey: "expose.windowSwitchEnabled")
        let preferences = ExposePreferences(defaults: defaults)

        XCTAssertNil(preferences.windowSwitchHotKey)
        XCTAssertFalse(preferences.windowSwitchEnabled)
        XCTAssertNil(defaults.object(forKey: "expose.windowSwitchHotKey"))
        XCTAssertNil(defaults.object(forKey: "expose.windowSwitchEnabled"))
    }

    func testFirstShortcutAssignmentRegistersItsNewValue() {
        defaults.removeObject(forKey: "expose.windowSwitchHotKey")
        let preferences = ExposePreferences(defaults: defaults)
        let host = FakeSwitcherHost()
        let controller = WindowSwitcherController(
            client: PresentationCommandRunner().makeClient(),
            preferences: preferences,
            hooks: host.hooks(modifiersHeld: true, stacking: [])
        )
        controller.start()
        let shortcut = HotKeySpec(keyCode: KeyCode.tab, modifierRawValue: NSEvent.ModifierFlags.control.rawValue)

        preferences.windowSwitchHotKey = shortcut

        XCTAssertTrue(preferences.windowSwitchEnabled)
        XCTAssertEqual(host.hotKeys.registrations[.windowCycleForward]?.keyCode, UInt32(shortcut.keyCode))
        XCTAssertEqual(host.hotKeys.registrations[.windowCycleForward]?.modifiers, shortcut.carbonModifiers)
        let restored = ExposePreferences(defaults: defaults)
        XCTAssertEqual(restored.windowSwitchHotKey, shortcut)
        XCTAssertTrue(restored.windowSwitchEnabled)
    }

    func testDisablingDuringLoadCancelsAndUnregistersImmediately() async {
        let preferences = ExposePreferences(defaults: defaults)
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost()
        let controller = WindowSwitcherController(
            client: runner.makeClient(),
            preferences: preferences,
            hooks: host.hooks(modifiersHeld: true, stacking: [11, 12, 13])
        )
        controller.start()
        controller.handle(.windowCycleForward)

        preferences.windowSwitchHotKey = nil

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(host.hotKeys.registrations.isEmpty)
        XCTAssertEqual(Array(host.events.suffix(3)), [.dismissorEnd] + carbonOff)
        runner.release()
        await waitUntil { host.loadsFinished == 1 }
        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
    }

    func testReplacingActiveShortcutCancelsAndUsesNewRegistration() async {
        let preferences = ExposePreferences(defaults: defaults)
        let runner = populatedRunner()
        let host = FakeSwitcherHost()
        let controller = WindowSwitcherController(
            client: runner.makeClient(),
            preferences: preferences,
            hooks: host.hooks(modifiersHeld: true, stacking: [11, 12, 13])
        )
        controller.start()
        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }
        let shortcut = HotKeySpec(keyCode: KeyCode.tab, modifierRawValue: NSEvent.ModifierFlags.control.rawValue)

        preferences.windowSwitchHotKey = shortcut

        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
        XCTAssertEqual(host.hotKeys.registrations[.windowCycleForward]?.keyCode, UInt32(shortcut.keyCode))
        XCTAssertEqual(host.hotKeys.registrations[.windowCycleForward]?.modifiers, shortcut.carbonModifiers)
        preferences.windowSwitchHotKey = nil
        XCTAssertTrue(host.hotKeys.registrations.isEmpty)
        XCTAssertFalse(preferences.windowSwitchEnabled)
        XCTAssertNil(defaults.object(forKey: "expose.windowSwitchHotKey"))
    }

    func testLoadingPanelTakesKeysBeforeTheQueryReturns() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.events, [.dismissorBegin] + carbonOff)
        XCTAssertTrue(controller.isActive)

        runner.release()
        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(
            host.events,
            [.dismissorBegin] + carbonOff,
            "Carbon is released as soon as the loading panel takes keyboard input"
        )

        controller.cancelIfActive()
        XCTAssertEqual(host.events, [.dismissorBegin] + carbonOff + [.dismissorEnd] + carbonOn)
    }

    func testDismissDuringLoadDropsTheStaleResult() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.events, [.dismissorBegin] + carbonOff)
        controller.cancelIfActive()
        XCTAssertEqual(host.events, [.dismissorBegin] + carbonOff + [.dismissorEnd] + carbonOn)

        runner.release()
        await waitUntil { host.loadsFinished == 1 }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
    }

    func testQueuedCarbonRepeatsDuringLoadAreAppliedWhenTheSessionLands() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertTrue(host.isVisible, "the loading panel receives keys immediately")
        controller.handle(.windowCycleBackward)
        controller.handle(.windowCycleBackward)
        runner.release()

        await waitUntil { host.sessions.count == 1 }

        // Opening .next lands on 12; two extra previous moves wrap 12 → 11 → 13.
        XCTAssertEqual(host.sessions[0].selectedEntry?.id, 13)
        XCTAssertTrue(controller.isActive)
    }

    func testPanelRepeatsDuringLoadAreAppliedWhenTheSessionLands() async throws {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.loadingShows, 1)
        XCTAssertTrue(host.isVisible)
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.space, repeating: true)))
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.space, repeating: true)))
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.space, flags: [.option, .shift])))
        runner.release()

        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(host.sessions[0].selectedEntry?.id, 13)
        controller.cancelIfActive()
    }

    func testEscapeWhileLoadingPreventsReleaseFromCommitting() async throws {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertTrue(host.isVisible)
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.escape, flags: .option)))
        host.holdDismiss.onModifierRelease?()
        runner.release()
        await waitUntil { host.loadsFinished == 1 }

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertTrue(host.quickTapDelays.isEmpty)
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
        XCTAssertEqual(Array(host.events.suffix(4)), carbonOn)
    }

    func testReleaseDuringLoadShowsThenCommitsAfter100ms() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host, modifiersHeld: true)

        controller.handle(.windowCycleForward)
        host.holdDismiss.onModifierRelease?()
        runner.release()

        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(host.quickTapDelays, [0.1])
        XCTAssertEqual(host.hideCount, 0)

        host.fireQuickTapCommit()
        await waitUntil { host.hideCount == 1 }
        await waitUntil { runner.invocations.contains { $0.first == "focus" } }

        XCTAssertTrue(host.events.contains(.dismissorEnd))
        XCTAssertEqual(Array(host.events.suffix(4)), carbonOn)
    }

    func testQuickTapShowsBeforeTheDelayedCommit() async {
        let runner = populatedRunner()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host, modifiersHeld: false)

        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }

        XCTAssertEqual(host.quickTapDelays, [0.1], "quick-tap commit stays a 100ms delay")
        XCTAssertEqual(host.hideCount, 0)
        XCTAssertTrue(controller.isActive)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })

        host.fireQuickTapCommit()
        await waitUntil { host.hideCount == 1 }
        await waitUntil { runner.invocations.contains { $0.first == "focus" } }

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(host.sessions[0].selectedEntry?.id, 12)
    }

    func testQuickTapCommitIsDroppedIfDismissedBeforeTheDelay() async {
        let runner = populatedRunner()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host, modifiersHeld: false)

        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }
        controller.cancelIfActive()
        XCTAssertFalse(controller.isActive)

        host.fireQuickTapCommit()

        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
    }

    func testEmptyResultEndsDismissorAndReregistersCarbon() async {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = ""
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        await waitUntil { host.loadsFinished == 1 }
        await waitUntil { !controller.isActive }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.events, [.dismissorBegin] + carbonOff + [.dismissorEnd] + carbonOn)
    }

    func testListingErrorEndsDismissor() async {
        let runner = populatedRunner()
        runner.failingPrefixes = [["list-windows", "--workspace", "focused"]]
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        await waitUntil { host.loadsFinished == 1 }
        await waitUntil { !controller.isActive }

        XCTAssertEqual(host.events, [.dismissorBegin] + carbonOff + [.dismissorEnd] + carbonOn)
    }

    func testPanelKeysCycleForwardBackwardAndConsumeUnboundKeys() async throws {
        let runner = populatedRunner()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)
        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }
        let session = host.sessions[0]
        XCTAssertEqual(session.selectedEntry?.id, 12)

        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.space, repeating: true)))
        XCTAssertEqual(session.selectedEntry?.id, 13)
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.space, flags: [.option, .shift])))
        XCTAssertEqual(session.selectedEntry?.id, 12)
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.leftArrow)))
        XCTAssertEqual(session.selectedEntry?.id, 11)
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.rightArrow)))
        XCTAssertEqual(session.selectedEntry?.id, 12)
        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.tab)))
        XCTAssertEqual(session.selectedEntry?.id, 12, "unbound keys must not change the selection")
        XCTAssertEqual(host.holdDismiss.notedKeyCodes.count, 5, "panel keys must re-arm release detection")
        controller.cancelIfActive()
    }

    func testModifierReleaseCommitsTheWindowChosenWithPanelKeys() async throws {
        let runner = populatedRunner()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)
        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }
        _ = try controller.handleKey(keyEvent(KeyCode.space))

        host.holdDismiss.onModifierRelease?()

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(host.events.contains(.dismissorEnd))
        XCTAssertEqual(Array(host.events.suffix(4)), carbonOn)
        await waitUntil { runner.invocations.contains { $0 == ["focus", "--window-id", "13"] } }
    }

    func testEscapeCancelsPanelWithoutFocusingAWindow() async throws {
        let runner = populatedRunner()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)
        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }

        XCTAssertTrue(try controller.handleKey(keyEvent(KeyCode.escape)))

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
        XCTAssertEqual(Array(host.events.suffix(4)), carbonOn)
    }

    private func keyEvent(
        _ code: UInt16,
        flags: NSEvent.ModifierFlags = .option,
        repeating: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: repeating,
            keyCode: code
        ))
    }

    private var carbonOff: [SwitcherTrace] {
        [.unregister(.windowCycleForward), .unregister(.windowCycleBackward)]
    }

    private var carbonOn: [SwitcherTrace] {
        [
            .unregister(.windowCycleForward),
            .unregister(.windowCycleBackward),
            .register(.windowCycleForward),
            .register(.windowCycleBackward)
        ]
    }

    private func populatedRunner() -> PresentationCommandRunner {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = [
            presentationWindowLine(id: 11, title: "A"),
            presentationWindowLine(id: 12, title: "B"),
            presentationWindowLine(id: 13, title: "C")
        ].joined(separator: "\n")
        runner.focusedWindowOutput = presentationFocusedLine(id: 11)
        return runner
    }

    private func makeController(
        runner: PresentationCommandRunner,
        host: FakeSwitcherHost,
        modifiersHeld: Bool = true
    ) -> WindowSwitcherController {
        WindowSwitcherController(
            client: runner.makeClient(),
            preferences: ExposePreferences(defaults: defaults),
            hooks: host.hooks(
                modifiersHeld: modifiersHeld,
                stacking: [11, 12, 13]
            )
        )
    }
}

private enum SwitcherTrace: Equatable {
    case dismissorBegin
    case dismissorEnd
    case unregister(HotKeyRole)
    case register(HotKeyRole)
}

@MainActor
private final class FakeSwitcherHost {
    let holdDismiss = FakeHoldDismiss()
    let hotKeys = RecordingHotKeys()
    var events: [SwitcherTrace] = []
    var isVisible = false
    var loadingShows = 0
    var sessions: [WindowCycleSession] = []
    var hideCount = 0
    var loadsFinished = 0
    var quickTapDelays: [TimeInterval] = []
    private var pendingCommit: [() -> Void] = []

    init() {
        holdDismiss.host = self
        hotKeys.host = self
    }

    func fireQuickTapCommit() {
        let work = pendingCommit
        pendingCommit = []
        for item in work {
            item()
        }
    }

    func hooks(
        modifiersHeld: Bool,
        stacking: [CGWindowID]
    ) -> WindowSwitcherControllerHooks {
        WindowSwitcherControllerHooks(
            windowBounds: { [:] },
            stacking: { stacking },
            resolveScreen: { PresentationScreenResolver.screen(for: $0) },
            isVisible: { [weak self] in self?.isVisible ?? false },
            showLoading: { [weak self] _ in
                self?.loadingShows += 1
                self?.isVisible = true
            },
            show: { [weak self] session, _, _ in
                self?.sessions.append(session)
                self?.isVisible = true
            },
            hide: { [weak self] in
                self?.hideCount += 1
                self?.isVisible = false
            },
            modifiersHeld: { _ in modifiersHeld },
            makeHoldDismiss: { [weak self] _, _ in
                guard let self else {
                    return FakeHoldDismiss()
                }
                return holdDismiss
            },
            hotKeys: hotKeys,
            scheduleQuickTapCommit: { [weak self] delay, work in
                self?.quickTapDelays.append(delay)
                self?.pendingCommit.append(work)
            },
            presentationQueryFinished: { [weak self] in
                self?.loadsFinished += 1
            },
            capturesPreviews: false
        )
    }
}

@MainActor
private final class FakeHoldDismiss: HoldToCommitDismissing {
    weak var host: FakeSwitcherHost?
    var onModifierRelease: (() -> Void)?
    var notedKeyCodes: [UInt16] = []

    func beginSession() {
        host?.events.append(.dismissorBegin)
    }

    func endSession() {
        host?.events.append(.dismissorEnd)
    }

    func noteKeyEvent(_ event: NSEvent) {
        notedKeyCodes.append(event.keyCode)
    }
}

@MainActor
private final class RecordingHotKeys: WindowSwitcherHotKeyRegistering {
    weak var host: FakeSwitcherHost?
    var registrations: [HotKeyRole: (keyCode: UInt32, modifiers: UInt32)] = [:]

    func register(_ role: HotKeyRole, keyCode: UInt32, modifiers: UInt32) throws {
        host?.events.append(.register(role))
        registrations[role] = (keyCode, modifiers)
    }

    func unregister(_ role: HotKeyRole) {
        host?.events.append(.unregister(role))
        registrations.removeValue(forKey: role)
    }
}
