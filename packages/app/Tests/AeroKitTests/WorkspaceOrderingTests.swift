import XCTest
@testable import AeroKitCore

final class WorkspaceOrderingTests: XCTestCase {
    func testListedNamesComeFirstInPriorityOrder() {
        let sorted = WorkspaceOrdering.sorted(
            ["1", "10", "2", "E", "Q", "W"],
            priority: ["Q", "W", "E"]
        )
        XCTAssertEqual(sorted, ["Q", "W", "E", "1", "2", "10"])
    }

    func testEmptyPrioritySortsNaturally() {
        XCTAssertEqual(
            WorkspaceOrdering.sorted(["10", "2", "1"], priority: []),
            ["1", "2", "10"]
        )
    }

    func testPriorityNamesWithoutWorkspaceAreIgnored() {
        XCTAssertEqual(
            WorkspaceOrdering.sorted(["1", "2"], priority: ["Z", "2"]),
            ["2", "1"]
        )
    }
}

final class KeyComboDisplayTests: XCTestCase {
    func testModifierAndKeySymbols() {
        XCTAssertEqual(KeyComboDisplay.symbols("alt-1"), "⌥1")
        XCTAssertEqual(KeyComboDisplay.symbols("alt-shift-q"), "⌥⇧Q")
        XCTAssertEqual(KeyComboDisplay.symbols("cmd-ctrl-left"), "⌘⌃←")
    }

    func testMultiCharacterKeysPassThrough() {
        XCTAssertEqual(KeyComboDisplay.symbols("alt-f13"), "⌥f13")
    }
}

@MainActor
final class WorkspaceOrderStoreTests: XCTestCase {
    private let suiteName = "WorkspaceOrderStoreTests"
    private var defaults: UserDefaults!

    /// Async overrides: they inherit the class's MainActor isolation, which
    /// the newer SDK requires for touching MainActor-isolated state.
    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFallsBackToDefaultOrder() {
        XCTAssertEqual(WorkspaceOrderStore(defaults: defaults).order, WorkspaceOrderStore.defaultOrder)
    }

    func testOrderPersists() {
        WorkspaceOrderStore(defaults: defaults).order = ["W", "Q", "1"]
        XCTAssertEqual(WorkspaceOrderStore(defaults: defaults).order, ["W", "Q", "1"])
    }
}
