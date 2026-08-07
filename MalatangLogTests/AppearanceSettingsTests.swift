import XCTest
import Observation
@testable import MalatangLog

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    func testNewInstallDefaultsToLightAndBlossom() throws {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppearanceSettings(defaults: defaults)

        XCTAssertEqual(settings.preference, .light)
        XCTAssertEqual(settings.theme, .blossom)
    }

    func testStoredPreferenceIsLoadedAndChangesArePersisted() throws {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            AppearancePreference.dark.rawValue,
            forKey: AppearanceSettings.storageKey
        )

        let settings = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(settings.preference.rawValue, AppearancePreference.dark.rawValue)

        settings.preference = .light
        XCTAssertEqual(
            defaults.string(forKey: AppearanceSettings.storageKey),
            AppearancePreference.light.rawValue
        )
    }

    func testLegacySystemPreferenceMigratesToLight() throws {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("system", forKey: AppearanceSettings.storageKey)

        let settings = AppearanceSettings(defaults: defaults)

        XCTAssertEqual(settings.preference, .light)
    }

    func testThemeIsLoadedAndPersisted() throws {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppTheme.ocean.rawValue, forKey: AppearanceSettings.themeStorageKey)

        let settings = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(settings.theme, .ocean)

        settings.theme = .sunshine
        XCTAssertEqual(
            defaults.string(forKey: AppearanceSettings.themeStorageKey),
            AppTheme.sunshine.rawValue
        )
    }

    func testPreferenceChangeNotifiesTheAppImmediately() throws {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppearanceSettings(defaults: defaults)
        let changeExpectation = expectation(description: "外観設定の変更を通知する")

        withObservationTracking {
            _ = settings.preferredColorScheme
        } onChange: {
            changeExpectation.fulfill()
        }

        settings.preference = .dark

        wait(for: [changeExpectation], timeout: 1)
    }
}
