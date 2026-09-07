import AppKit
import Carbon
import XCTest
@testable import AeroKitCore

@MainActor
final class CommandKeyEquivalentTests: XCTestCase {
    func testUSCommandW() throws {
        let source = try layout("com.apple.keylayout.US")
        XCTAssertTrue(try matches(event(kVK_ANSI_W, text: "w"), source: source))
        XCTAssertTrue(try matches(event(kVK_ANSI_W, text: "W", flags: [.command, .capsLock]), source: source))
        XCTAssertFalse(try matches(event(kVK_ANSI_Q, text: "q"), source: source))
    }

    func testNonLatinEventUsesASCIILayoutInsteadOfInputText() throws {
        // Simulate a Russian input event with the ASCII-capable US source
        // supplied by TIS. No input-source selection is changed by this test.
        let source = try layout("com.apple.keylayout.US")
        XCTAssertTrue(try matches(event(kVK_ANSI_W, text: "ц"), source: source))
        XCTAssertTrue(try matches(event(kVK_ANSI_W, text: ""), source: source))
    }

    func testDvorakUsesLogicalWNotANSIPosition() throws {
        let source = try layout("com.apple.keylayout.Dvorak")
        XCTAssertTrue(try matches(event(kVK_ANSI_Comma, text: "w"), source: source))
        XCTAssertFalse(try matches(event(kVK_ANSI_W, text: ","), source: source))
        // Even if raw text says W, a successful translation is authoritative.
        XCTAssertFalse(try matches(event(kVK_ANSI_W, text: "w"), source: source))
    }

    func testDvorakQwertyCommandHonorsCommandTable() throws {
        let source = try layout("com.apple.keylayout.DVORAK-QWERTYCMD")
        XCTAssertTrue(try matches(event(kVK_ANSI_W, text: ","), source: source))
        XCTAssertFalse(try matches(event(kVK_ANSI_Comma, text: "w"), source: source))
    }

    func testLayoutIsNotCachedBetweenEvents() throws {
        let us = try layout("com.apple.keylayout.US")
        let dvorak = try layout("com.apple.keylayout.Dvorak")
        let key = try event(kVK_ANSI_W, text: "ц")
        XCTAssertTrue(matches(key, source: us))
        XCTAssertFalse(matches(key, source: dvorak))
        XCTAssertTrue(matches(key, source: us))
    }

    func testOnlyCommandIsAccepted() throws {
        let source = try layout("com.apple.keylayout.US")
        let rejected: [NSEvent.ModifierFlags] = [
            [], .shift, .option, .control,
            [.command, .shift], [.command, .option], [.command, .control], [.command, .function]
        ]
        for flags in rejected {
            XCTAssertFalse(try matches(event(kVK_ANSI_W, text: "w", flags: flags), source: source))
        }
    }

    func testUnavailableLayoutFallsBackToEventCharacter() throws {
        XCTAssertTrue(try matches(event(kVK_ANSI_W, text: "w"), source: nil))
        XCTAssertTrue(try matches(event(kVK_ANSI_W, text: "W"), source: nil))
        XCTAssertFalse(try matches(event(kVK_ANSI_W, text: "ц"), source: nil))
        XCTAssertFalse(try matches(event(kVK_ANSI_W, text: ""), source: nil))
        XCTAssertFalse(try matches(event(kVK_ANSI_W, text: "w", flags: [.command, .shift]), source: nil))
    }

    private func matches(_ event: NSEvent, source: TISInputSource?) -> Bool {
        CommandKeyEquivalent.matches(event, character: "w", inputSource: source)
    }

    private func layout(_ identifier: String) throws -> TISInputSource {
        let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
        let sources = try XCTUnwrap(TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])
        return try XCTUnwrap(sources.first, "Required macOS keyboard layout unavailable: \(identifier)")
    }

    private func event(
        _ keyCode: Int,
        text: String,
        flags: NSEvent.ModifierFlags = .command
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: text,
            charactersIgnoringModifiers: text,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }
}
