import XCTest
@testable import SwitcherFeature

@MainActor
final class AppPreferencesTests: XCTestCase {
    private let suiteName = "AppPreferencesTests"
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

    func testPreselectInheritsLegacySwitchOnReleaseAndStaysIndependent() {
        defaults.set(true, forKey: "switcher.switchOnRelease")

        XCTAssertTrue(AppPreferences(defaults: defaults).preselectNextOnOpen)

        // The inherited value is pinned at first launch: flipping the legacy
        // setting afterwards must not drag pre-selection along with it.
        defaults.set(false, forKey: "switcher.switchOnRelease")
        XCTAssertTrue(AppPreferences(defaults: defaults).preselectNextOnOpen)
    }

    func testPreselectKeepsExplicitValueOverLegacyFallback() {
        defaults.set(true, forKey: "switcher.switchOnRelease")
        defaults.set(false, forKey: "switcher.preselectNextOnOpen")

        XCTAssertFalse(AppPreferences(defaults: defaults).preselectNextOnOpen)
    }

    func testSnapshotExclusionsTrimsCasesAndDropsEmptyTokens() {
        let preferences = AppPreferences(defaults: defaults)

        preferences.snapshotExcludedApps = " 1Password ,\ncom.apple.Passwords, "
        XCTAssertEqual(preferences.snapshotExclusions, ["1password", "com.apple.passwords"])

        preferences.snapshotExcludedApps = ""
        XCTAssertEqual(preferences.snapshotExclusions, [])
    }
}
