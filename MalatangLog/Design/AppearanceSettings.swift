import SwiftUI
import Observation

@MainActor
@Observable
final class AppearanceSettings {
    static let storageKey = "appearancePreference"
    static let themeStorageKey = "colorTheme"
    static let shared = AppearanceSettings()

    private let defaults: UserDefaults

    var preference: AppearancePreference {
        didSet {
            defaults.set(preference.rawValue, forKey: Self.storageKey)
        }
    }

    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeStorageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: Self.storageKey)
        preference = AppearancePreference(rawValue: storedValue ?? "")
            ?? AppearancePreference.light
        let storedTheme = defaults.string(forKey: Self.themeStorageKey)
        theme = AppTheme(rawValue: storedTheme ?? "")
            ?? AppTheme.blossom
    }

    var preferredColorScheme: ColorScheme {
        preference.colorScheme
    }
}
