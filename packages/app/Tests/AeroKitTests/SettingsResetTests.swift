import XCTest
@testable import AeroKitCore
@testable import ExposeFeature
@testable import SwipeFeature
@testable import SwitcherFeature

@MainActor
final class SettingsResetTests: XCTestCase {
    func testWorkspaceKeyboardResetPreservesDisplayAndPreviewChoices() throws {
        let suite = "SettingsResetTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.gridColumns = 6
        preferences.hideEmptyWorkspaces = true
        preferences.switchOnRelease = true
        preferences.preselectNextOnOpen = true
        preferences.autoRefresh = false
        preferences.snapshotExcludedApps = "com.apple.Safari"
        preferences.resetKeyboardSettings()
        XCTAssertEqual(preferences.gridColumns, 6)
        XCTAssertTrue(preferences.hideEmptyWorkspaces)
        XCTAssertFalse(preferences.switchOnRelease)
        XCTAssertFalse(preferences.preselectNextOnOpen)
        XCTAssertFalse(preferences.autoRefresh)
        XCTAssertEqual(preferences.snapshotExclusions, ["com.apple.safari"])
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.gridColumns, 6)
        XCTAssertFalse(restored.switchOnRelease)
        preferences.resetPreviewSettings()
        XCTAssertTrue(preferences.autoRefresh)
        XCTAssertEqual(preferences.snapshotExclusions, ["com.apple.safari"])
    }

    func testWorkspaceDisplayResetPreservesKeyboardAndPreviewChoices() throws {
        let suite = "SettingsResetTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.gridColumns = 6
        preferences.hideEmptyWorkspaces = true
        preferences.switchOnRelease = true
        preferences.preselectNextOnOpen = true
        preferences.hotKey = .defaultRefresh
        preferences.autoRefresh = false
        preferences.snapshotExcludedApps = "com.apple.Safari"
        preferences.resetDisplaySettings()
        XCTAssertEqual(preferences.gridColumns, 4)
        XCTAssertFalse(preferences.hideEmptyWorkspaces)
        XCTAssertTrue(preferences.switchOnRelease)
        XCTAssertTrue(preferences.preselectNextOnOpen)
        XCTAssertEqual(preferences.hotKey, .defaultRefresh)
        XCTAssertFalse(preferences.autoRefresh)
        XCTAssertEqual(preferences.snapshotExclusions, ["com.apple.safari"])
    }

    func testWindowKeyboardResetPreservesDisplayAndGestureChoices() throws {
        let suite = "SettingsResetTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ExposePreferences(defaults: defaults)
        preferences.threeFingerSwipe = false
        preferences.groupByApp = true
        preferences.followMovedWindow = true
        preferences.windowSwitchHotKey = .defaultRefresh
        preferences.groupToggleKey = "G"
        preferences.resetKeyboardSettings()
        XCTAssertFalse(preferences.threeFingerSwipe)
        XCTAssertTrue(preferences.groupByApp)
        XCTAssertTrue(preferences.followMovedWindow)
        XCTAssertFalse(preferences.windowSwitchEnabled)
        XCTAssertNil(preferences.windowSwitchHotKey)
        XCTAssertNil(defaults.object(forKey: "expose.windowSwitchHotKey"))
        let restored = ExposePreferences(defaults: defaults)
        XCTAssertNil(restored.windowSwitchHotKey)
        XCTAssertFalse(restored.windowSwitchEnabled)
        XCTAssertEqual(preferences.groupToggleKey, "0")
        XCTAssertEqual(preferences.hotKey, ExposePreferences.defaultHotKey)
    }

    func testWindowDisplayResetPreservesKeyboardAndGestureChoices() throws {
        let suite = "SettingsResetTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ExposePreferences(defaults: defaults)
        preferences.threeFingerSwipe = false
        preferences.groupByApp = true
        preferences.followMovedWindow = true
        preferences.windowSwitchHotKey = .defaultRefresh
        preferences.groupToggleKey = "G"
        preferences.hotKey = .defaultRefresh
        preferences.resetDisplaySettings()
        XCTAssertFalse(preferences.groupByApp)
        XCTAssertFalse(preferences.followMovedWindow)
        XCTAssertFalse(preferences.threeFingerSwipe)
        XCTAssertTrue(preferences.windowSwitchEnabled)
        XCTAssertEqual(preferences.groupToggleKey, "G")
        XCTAssertEqual(preferences.hotKey, .defaultRefresh)
    }

    func testTrackpadResetPreservesWorkspaceNameDisplay() throws {
        let suite = "SettingsResetTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SwipePreferences(defaults: defaults)
        preferences.isEnabled = false
        preferences.naturalDirection = false
        preferences.wrapAround = false
        preferences.skipEmpty = false
        preferences.stepDistanceMM = 80
        preferences.showHUD = false
        preferences.resetTrackpadSettings()
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertTrue(preferences.naturalDirection)
        XCTAssertTrue(preferences.wrapAround)
        XCTAssertTrue(preferences.skipEmpty)
        XCTAssertEqual(preferences.stepDistanceMM, SwipePreferences.defaultStepDistanceMM)
        XCTAssertFalse(preferences.showHUD)
        XCTAssertFalse(SwipePreferences(defaults: defaults).showHUD)
    }

    func testWorkspaceNameDisplayResetPreservesTrackpadChoices() throws {
        let suite = "SettingsResetTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SwipePreferences(defaults: defaults)
        preferences.isEnabled = false
        preferences.naturalDirection = false
        preferences.wrapAround = false
        preferences.skipEmpty = false
        preferences.stepDistanceMM = 80
        preferences.showHUD = false
        preferences.resetDisplaySettings()
        XCTAssertTrue(preferences.showHUD)
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertFalse(preferences.naturalDirection)
        XCTAssertFalse(preferences.wrapAround)
        XCTAssertFalse(preferences.skipEmpty)
        XCTAssertEqual(preferences.stepDistanceMM, 80)
    }
}
