import AppKit
import Carbon
import XCTest
@testable import AeroKitCore

@MainActor
final class HotKeySpecTests: XCTestCase {
    func testRecordingIgnoresInputCharacters() throws {
        let english = try XCTUnwrap(HotKeySpec.from(event: event(text: "w")))
        let russian = try XCTUnwrap(HotKeySpec.from(event: event(text: "ц")))
        XCTAssertEqual(english, russian)
        XCTAssertEqual(russian.keyCode, UInt16(kVK_ANSI_W))
        XCTAssertTrue(try russian.matches(event(text: "w")))
        XCTAssertTrue(try russian.matches(event(text: "ц")))
        XCTAssertEqual(try russian.displayKeys(inputSource: layout("com.apple.keylayout.US")), ["⌥", "W"])
    }

    func testLabelFollowsASCIILayoutWithoutRetargetingBinding() throws {
        let spec = HotKeySpec(keyCode: UInt16(kVK_ANSI_Comma), modifierRawValue: NSEvent.ModifierFlags.command.rawValue)
        let us = try layout("com.apple.keylayout.US")
        let dvorak = try layout("com.apple.keylayout.Dvorak")
        XCTAssertEqual(spec.displayKeys(inputSource: us), ["⌘", ","])
        XCTAssertEqual(spec.displayKeys(inputSource: dvorak), ["⌘", "W"])
        XCTAssertEqual(spec.displayKeys(inputSource: us), ["⌘", ","])
        XCTAssertEqual(spec.keyCode, UInt16(kVK_ANSI_Comma))
    }

    func testLabelUsesBaseCharacterNotCommandTable() throws {
        let source = try layout("com.apple.keylayout.DVORAK-QWERTYCMD")
        let spec = HotKeySpec(keyCode: UInt16(kVK_ANSI_W), modifierRawValue: NSEvent.ModifierFlags.command.rawValue)
        XCTAssertEqual(spec.displayKeys(inputSource: source), ["⌘", ","])
        XCTAssertEqual(ASCIIKeyboardLayout.character(for: spec.keyCode, command: true, inputSource: source), "w")
    }

    func testLegacyLabelIsIgnoredAndNoLongerEncoded() throws {
        let legacy = """
        {"keyCode":13,"modifierRawValue":\(NSEvent.ModifierFlags.option.rawValue),"keyLabel":"Ц"}
        """
        let spec = try JSONDecoder().decode(HotKeySpec.self, from: Data(legacy.utf8))
        XCTAssertEqual(spec.keyCode, UInt16(kVK_ANSI_W))
        XCTAssertEqual(spec.modifierFlags, .option)
        XCTAssertEqual(try spec.displayKeys(inputSource: layout("com.apple.keylayout.US")), ["⌥", "W"])
        let data = try JSONEncoder().encode(spec)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["keyCode", "modifierRawValue"])
        XCTAssertEqual(try JSONDecoder().decode(HotKeySpec.self, from: data), spec)
    }

    func testUserDefaultsRoundTrip() throws {
        let suite = "HotKeySpecTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spec = try XCTUnwrap(HotKeySpec.from(event: event(text: "ц")))
        spec.store(in: defaults, key: "hotkey")
        XCTAssertEqual(HotKeySpec.load(from: defaults, key: "hotkey"), spec)
    }

    func testSpecialKeysAndMissingLayout() {
        for (code, label) in [(kVK_Tab, "⇥"), (kVK_Escape, "⎋"), (kVK_F1, "F1"), (kVK_F20, "F20")] {
            let spec = HotKeySpec(keyCode: UInt16(code), modifierRawValue: NSEvent.ModifierFlags.option.rawValue)
            XCTAssertEqual(spec.displayKeys(inputSource: nil), ["⌥", label])
        }
        let spec = HotKeySpec(keyCode: UInt16(kVK_ANSI_W), modifierRawValue: NSEvent.ModifierFlags.option.rawValue)
        XCTAssertEqual(spec.displayKeys(inputSource: nil), ["⌥", "?"])
    }

    private func layout(_ identifier: String) throws -> TISInputSource {
        let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
        let sources = try XCTUnwrap(TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])
        return try XCTUnwrap(sources.first, "Required macOS keyboard layout unavailable: \(identifier)")
    }

    private func event(text: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: text,
            charactersIgnoringModifiers: text,
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ))
    }
}
