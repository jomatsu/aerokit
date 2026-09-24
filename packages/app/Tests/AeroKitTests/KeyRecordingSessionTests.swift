import AppKit
import Combine
import XCTest
@testable import AeroKitCore

@MainActor
final class KeyRecordingSessionTests: XCTestCase {
    func testStartingAnotherRecorderCancelsPreviousAndIgnoresStaleStop() {
        let session = KeyRecordingSession()
        let first = UUID()
        let second = UUID()
        var changes: [String] = []
        var globalChanges: [Bool] = []
        let subscription = session.recordingChanged.sink { globalChanges.append($0) }
        defer { subscription.cancel() }
        session.start(
            id: first,
            containsClick: { _ in true },
            onRecordingChanged: { changes.append("first:\($0)") },
            record: { _ in nil }
        )
        session.start(
            id: second,
            containsClick: { _ in true },
            onRecordingChanged: { changes.append("second:\($0)") },
            record: { _ in nil }
        )
        session.stop(id: first)
        XCTAssertEqual(session.activeID, second)
        session.stop()
        session.stop()
        XCTAssertEqual(changes, ["first:true", "first:false", "second:true", "second:false"])
        XCTAssertEqual(globalChanges, [true, false, true, false])
    }

    func testRejectedKeyShowsErrorAndEscapeCancelsWithoutRecording() throws {
        let session = KeyRecordingSession()
        var attempts = 0
        session.start(id: UUID(), containsClick: { _ in true }, onRecordingChanged: { _ in }, record: { _ in
            attempts += 1
            return "Use a modifier"
        })
        XCTAssertTrue(try session.handle(key(code: 0, characters: "a")))
        XCTAssertEqual(session.errorMessage, "Use a modifier")
        XCTAssertNotNil(session.activeID)
        XCTAssertTrue(try session.handle(key(code: 53, characters: "\u{1B}")))
        XCTAssertNil(session.activeID)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(attempts, 1)
    }

    func testSuccessfulKeyEndsSessionAndPassesLaterKeysThrough() throws {
        let session = KeyRecordingSession()
        var changes: [Bool] = []
        let subscription = session.recordingChanged.sink { changes.append($0) }
        defer { subscription.cancel() }
        session.start(id: UUID(), containsClick: { _ in true }, onRecordingChanged: { _ in }, record: { _ in nil })
        let event = try key(code: 0, characters: "a")
        XCTAssertTrue(session.handle(event))
        XCTAssertNil(session.activeID)
        XCTAssertFalse(session.handle(event))
        XCTAssertEqual(changes, [true, false])
    }

    func testOutsideClickCancelsAndInsideClickPreservesSession() throws {
        let session = KeyRecordingSession()
        var inside = true
        session.start(id: UUID(), containsClick: { _ in inside }, onRecordingChanged: { _ in }, record: { _ in nil })
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        XCTAssertFalse(session.handle(click))
        XCTAssertNotNil(session.activeID)
        inside = false
        XCTAssertFalse(session.handle(click))
        XCTAssertNil(session.activeID)
    }

    private func key(code: UInt16, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        ))
    }
}
