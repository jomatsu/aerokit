import AppKit
import XCTest
@testable import AeroKitCore
@testable import SwitcherFeature

@MainActor
final class EscapeShortcutTests: XCTestCase {
    func testOnlyBareEscapeCancelsRecording() throws {
        XCTAssertTrue(try KeyCode.isBareEscape(event(flags: [])))
        XCTAssertTrue(try KeyCode.isBareEscape(event(flags: [.capsLock])))
        for flags: NSEvent.ModifierFlags in [
            .option,
            .command,
            .control,
            .shift,
            [.option, .shift],
            [.option, .capsLock]
        ] {
            XCTAssertFalse(try KeyCode.isBareEscape(event(flags: flags)))
        }
        XCTAssertFalse(try KeyCode.isBareEscape(event(code: KeyCode.tab, flags: [])))
    }

    func testModifiedEscapeCanBeRecordedAsHotKey() throws {
        for flags: NSEvent.ModifierFlags in [.option, .command, .control, [.option, .capsLock]] {
            let key = try event(flags: flags)
            XCTAssertFalse(KeyCode.isBareEscape(key))
            let spec = try XCTUnwrap(HotKeySpec.from(event: key))
            XCTAssertEqual(spec.keyCode, KeyCode.escape)
            XCTAssertTrue(spec.matches(key))
            XCTAssertEqual(spec.displayKeys.last, "⎋")
        }
    }

    func testBareAndShiftOnlyEscapeRemainInvalidGlobalHotKeys() throws {
        XCTAssertNil(try HotKeySpec.from(event: event(flags: [])))
        XCTAssertNil(try HotKeySpec.from(event: event(flags: .shift)))
    }

    func testOptionEscapeCyclesAndShiftReverses() throws {
        try withOverlay { overlay, _ in
            var moves: [SelectionMove] = []
            var cancels = 0
            overlay.onMove = { moves.append($0) }
            overlay.onCancel = { cancels += 1 }
            XCTAssertTrue(try overlay.handleKey(event(flags: .option)))
            XCTAssertTrue(try overlay.handleKey(event(flags: [.option, .shift])))
            XCTAssertTrue(try overlay.handleKey(event(flags: [.option, .capsLock])))
            XCTAssertEqual(moves, [.next, .previous, .next])
            XCTAssertEqual(cancels, 0)
        }
    }

    func testBareEscapeCancelsEvenWhenEscapeIsTrigger() throws {
        try withOverlay { overlay, preferences in
            // After releasing Option, the overlay can stay open in this mode.
            preferences.switchOnRelease = false
            var cancels = 0
            overlay.onCancel = { cancels += 1 }
            overlay.onMove = { _ in XCTFail("Bare Escape must not cycle") }
            XCTAssertTrue(try overlay.handleKey(event(flags: [])))
            XCTAssertTrue(try overlay.handleKey(event(flags: .capsLock)))
            XCTAssertEqual(cancels, 2)
        }
    }

    func testEscapeWithoutTriggerModifierDoesNotCycle() throws {
        try withOverlay { overlay, _ in
            var cancels = 0
            overlay.onCancel = { cancels += 1 }
            overlay.onMove = { _ in XCTFail("The configured Option modifier is missing") }
            XCTAssertTrue(try overlay.handleKey(event(flags: .shift)))
            XCTAssertTrue(try overlay.handleKey(event(flags: .control)))
            XCTAssertEqual(cancels, 2)
        }
    }

    func testEscapeStillCancelsWithDefaultTrigger() throws {
        try withOverlay { overlay, preferences in
            preferences.hotKey = .default
            var cancels = 0
            overlay.onCancel = { cancels += 1 }
            overlay.onMove = { _ in XCTFail("Escape is not the trigger") }
            XCTAssertTrue(try overlay.handleKey(event(flags: .option)))
            XCTAssertTrue(try overlay.handleKey(event(flags: [])))
            XCTAssertEqual(cancels, 2)
        }
    }

    func testEscapeRefreshShortcutStillWorks() throws {
        try withOverlay { overlay, preferences in
            preferences.refreshShortcut = HotKeySpec(
                keyCode: KeyCode.escape,
                modifierRawValue: NSEvent.ModifierFlags.command.rawValue
            )
            var refreshes = 0
            overlay.onReloadSnapshots = { refreshes += 1 }
            overlay.onCancel = { XCTFail("Modified Escape should refresh") }
            overlay.onMove = { _ in XCTFail("Modified Escape should refresh") }
            XCTAssertTrue(try overlay.handleKey(event(flags: .command)))
            XCTAssertEqual(refreshes, 1)
        }
    }

    private func withOverlay(_ body: (SwiftUIOverlay, AppPreferences) throws -> Void) throws {
        let suite = "EscapeShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.hotKey = HotKeySpec(
            keyCode: KeyCode.escape,
            modifierRawValue: NSEvent.ModifierFlags.option.rawValue
        )
        let overlay = SwiftUIOverlay(configuration: SwitcherConfiguration(), preferences: preferences)
        try body(overlay, preferences)
    }

    private func event(code: UInt16 = KeyCode.escape, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: code
        ))
    }
}
