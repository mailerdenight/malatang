import XCTest
@testable import MalatangLog

@MainActor
final class CurrencySettingsTests: XCTestCase {
    func testDefaultCurrencyFollowsPreferredLanguage() {
        XCTAssertEqual(AppCurrency.defaultCode(for: ["ja"]), "JPY")
        XCTAssertEqual(AppCurrency.defaultCode(for: ["ko"]), "KRW")
        XCTAssertEqual(AppCurrency.defaultCode(for: ["vi"]), "VND")
        XCTAssertEqual(AppCurrency.defaultCode(for: ["zh-Hans"]), "CNY")
        XCTAssertEqual(AppCurrency.defaultCode(for: ["zh-Hant"]), "TWD")
        XCTAssertEqual(AppCurrency.defaultCode(for: ["en"]), "USD")
    }

    func testStoredCurrencyIsLoadedAndPersisted() throws {
        let suiteName = "CurrencySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppCurrency.jpy.rawValue, forKey: CurrencySettings.storageKey)

        let settings = CurrencySettings(defaults: defaults)
        XCTAssertEqual(settings.defaultCurrencyCode, AppCurrency.jpy.rawValue)

        settings.defaultCurrencyCode = AppCurrency.vnd.rawValue
        XCTAssertEqual(
            defaults.string(forKey: CurrencySettings.storageKey),
            AppCurrency.vnd.rawValue
        )
    }

    func testInitialCurrencyIsPersistedOnFirstLaunch() throws {
        let suiteName = "CurrencySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = CurrencySettings(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: CurrencySettings.storageKey),
            settings.defaultCurrencyCode
        )
    }

    func testInitialConfirmationIsNeededUntilConfirmedOrLocked() throws {
        let suiteName = "CurrencySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = CurrencySettings(defaults: defaults)

        XCTAssertTrue(settings.needsInitialConfirmation(servings: []))

        settings.didConfirmDefaultCurrency = true
        XCTAssertFalse(settings.needsInitialConfirmation(servings: []))

        settings.didConfirmDefaultCurrency = false
        let serving = Serving(priceYen: 1_200, currencyCode: AppCurrency.jpy.rawValue)
        XCTAssertFalse(settings.needsInitialConfirmation(servings: [serving]))
    }

    func testBaseCurrencyUsesFirstRealRecordWhenRecordsExist() throws {
        let suiteName = "CurrencySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppCurrency.jpy.rawValue, forKey: CurrencySettings.storageKey)
        let settings = CurrencySettings(defaults: defaults)
        let first = Serving(priceYen: 90_000, currencyCode: AppCurrency.vnd.rawValue)
        first.createdAt = Date(timeIntervalSince1970: 10)
        let second = Serving(priceYen: 1_200, currencyCode: AppCurrency.jpy.rawValue)
        second.createdAt = Date(timeIntervalSince1970: 20)

        XCTAssertTrue(settings.isLocked(by: [first, second]))
        XCTAssertEqual(
            settings.baseCurrencyCode(for: [second, first]),
            AppCurrency.vnd.rawValue
        )
    }

    func testRecordKeepsItsCurrencyWhenDefaultChanges() throws {
        let serving = Serving(priceYen: 1_200, currencyCode: AppCurrency.jpy.rawValue)
        let draft = ServingDraft.from(serving, resettingForToday: false)

        XCTAssertEqual(draft.currencyCode, AppCurrency.jpy.rawValue)

        draft.currencyCode = AppCurrency.vnd.rawValue
        draft.apply(to: serving)

        XCTAssertEqual(serving.currencyCode, AppCurrency.vnd.rawValue)
    }
}
