import Observation
import XCTest
@testable import AeroKitCore

@MainActor
final class LocalizationTests: XCTestCase {
    func testSelectionPersistsAndInvalidValueFallsBackToSystem() throws {
        let suite = "LocalizationTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LanguagePreferences(defaults: defaults)
        XCTAssertEqual(preferences.selected, .system)
        preferences.selected = .japanese
        XCTAssertEqual(LanguagePreferences(defaults: defaults).selected, .japanese)
        defaults.set("unsupported-language", forKey: LanguagePreferences.defaultsKey)
        XCTAssertEqual(LanguagePreferences(defaults: defaults).selected, .system)
    }

    func testRegionalSystemLanguagesResolveToSupportedCatalogs() {
        XCTAssertEqual(AppLanguage.systemLanguage(preferredLanguages: ["ja-JP"]), .japanese)
        XCTAssertEqual(AppLanguage.systemLanguage(preferredLanguages: ["es-MX"]), .spanish)
        XCTAssertEqual(AppLanguage.systemLanguage(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.systemLanguage(preferredLanguages: ["it-IT", "de-DE"]), .german)
        XCTAssertEqual(AppLanguage.systemLanguage(preferredLanguages: ["zz"]), .english)
    }

    func testExplicitLanguageOverridesProcessLocale() {
        XCTAssertEqual(L10n.string("Language", language: .japanese), "言語")
        XCTAssertEqual(L10n.string("Language", language: .english), "Language")
        XCTAssertEqual(L10n.string("Language", language: .german), "Sprache")
    }

    func testInterpolatedValuesArePreservedInEveryLanguage() {
        let count = 37
        let name = "My App 日本語 & 100%"
        for language in AppLanguage.allCases where language != .system {
            let countText = L10n.string("\(count) apps excluded", language: language)
            XCTAssertTrue(countText.contains("37"), "\(language): \(countText)")
            XCTAssertFalse(countText.contains("%lld"))
            let appText = L10n.string("Exclude \(name) from saved previews", language: language)
            XCTAssertTrue(appText.contains(name), "\(language): \(appText)")
            XCTAssertFalse(appText.contains("%@"))
        }
    }

    func testResourceIsTranslatedAtDisplayTime() {
        let resource: LocalizedStringResource = "Language"
        let previous = LanguagePreferences.shared.selected
        defer { LanguagePreferences.shared.selected = previous }
        LanguagePreferences.shared.selected = .english
        XCTAssertEqual(L10n.tr(resource), "Language")
        LanguagePreferences.shared.selected = .japanese
        XCTAssertEqual(L10n.tr(resource), "言語")
    }

    func testJapaneseNavigationUsesFamiliarSettingCategories() {
        let names: [(LocalizedStringResource, String)] = [
            ("General", "一般"),
            ("Workspaces", "ワークスペース"),
            ("Windows", "ウインドウ"),
            ("Preview Images", "プレビュー画像")
        ]
        for (name, translated) in names {
            XCTAssertEqual(L10n.string(name, language: .japanese), translated)
        }
    }

    func testJapaneseRetainsModeNames() {
        let names: [LocalizedStringResource] = [
            "Natural", "Reversed"
        ]
        for name in names {
            XCTAssertEqual(L10n.string(name, language: .japanese), name.key)
        }
    }
}
