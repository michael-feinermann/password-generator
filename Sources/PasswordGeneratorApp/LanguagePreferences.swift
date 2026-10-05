import Foundation

/// Stores the language choice without persisting generator configuration.
@MainActor
protocol LanguagePreferences {
    func loadLanguage() -> AppLanguage
    func saveLanguage(_ language: AppLanguage)
}

@MainActor
final class UserDefaultsLanguagePreferences: LanguagePreferences {
    static let languageKey = "preferredLanguage"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadLanguage() -> AppLanguage {
        guard let value = defaults.object(forKey: Self.languageKey) as? String,
              let language = AppLanguage(rawValue: value) else { return .english }
        return language
    }

    func saveLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.languageKey)
    }
}
