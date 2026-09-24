import Foundation

public enum L10n {
    @MainActor
    public static func tr(_ resource: LocalizedStringResource) -> String {
        string(resource, language: LanguagePreferences.shared.selected)
    }

    public static func string(_ resource: LocalizedStringResource, language: AppLanguage) -> String {
        let resolved = language.resolved
        let bundle = bundles[resolved] ?? resources
        return String(localized: resource.defaultValue, table: resource.table, bundle: bundle, locale: resolved.locale)
    }

    private static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "AeroKit_AeroKitCore", withExtension: "bundle"),
           let bundle = Bundle(url: url)
        {
            return bundle
        }
        return .module
    }()

    private static let bundles: [AppLanguage: Bundle] = {
        var result: [AppLanguage: Bundle] = [:]
        for language in AppLanguage.allCases where language != .system {
            if let path = resources.path(forResource: language.rawValue, ofType: "lproj"),
               let bundle = Bundle(path: path)
            {
                result[language] = bundle
            }
        }
        return result
    }()
}
