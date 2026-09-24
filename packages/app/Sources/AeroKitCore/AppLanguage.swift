import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    public var id: String {
        rawValue
    }

    @MainActor public var displayName: String {
        switch self {
        case .system: L10n.tr("System default")
        case .english: "English"
        case .japanese: "日本語"
        case .simplifiedChinese: "简体中文"
        case .korean: "한국어"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        }
    }

    public static func systemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        let supported = allCases.filter { $0 != .system }.map(\.rawValue)
        let match = Bundle.preferredLocalizations(from: supported, forPreferences: preferredLanguages).first
        return match.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    private static let systemDefault = systemLanguage()

    public var resolved: AppLanguage {
        self == .system ? Self.systemDefault : self
    }

    public var locale: Locale {
        Locale(identifier: resolved.rawValue)
    }
}

@MainActor
@Observable
public final class LanguagePreferences {
    public static let shared = LanguagePreferences()
    public static let didChange = Notification.Name("AeroKitLanguageDidChange")
    public static let defaultsKey = "app.language"

    public var selected: AppLanguage {
        didSet {
            guard selected != oldValue else { return }
            defaults.set(selected.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selected = defaults.string(forKey: Self.defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}
