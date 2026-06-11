import XCTest
@testable import SwitcherFeature

@MainActor
final class AppPreferencesTests: XCTestCase {
    private let suiteName = "AppPreferencesTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
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
}
