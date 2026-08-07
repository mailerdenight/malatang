import XCTest
@testable import MalatangLog

final class LocalizationTests: XCTestCase {
    func testAppAdvertisesEverySupportedLanguage() {
        XCTAssertEqual(
            Set(AppLocalization.supportedLanguageCodes),
            Set(Bundle.main.localizations).intersection(AppLocalization.supportedLanguageCodes)
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String,
            "en"
        )
    }

    func testEveryCatalogHasTheSameCompleteKeySet() throws {
        let japanese = try strings(for: "ja")

        XCTAssertGreaterThanOrEqual(japanese.count, 566)
        XCTAssertTrue(japanese.allSatisfy { $0.key == $0.value })

        for languageCode in translatedLanguageCodes {
            let table = try strings(for: languageCode)
            XCTAssertEqual(
                Set(table.keys),
                Set(japanese.keys),
                "\(languageCode) has a different localization key set"
            )
            XCTAssertTrue(
                table.allSatisfy { key, value in
                    key.isEmpty ? value.isEmpty : value.isEmpty == false
                },
                "\(languageCode) contains an empty localization"
            )
        }
    }

    func testNonChineseCatalogsHaveNoUnexpectedJapaneseFallbackValues() throws {
        let languageInvariantKeys: Set<String> = [
            "", "/ 5", "sample", "%lld%@", "%@ %lld%@", "%lld / %lld",
            "%@ %lld", "%lld", "¥%@", "0"
        ]

        for languageCode in ["en", "vi", "ko", "th", "de", "id"] {
            let table = try strings(for: languageCode)
            let untranslated = table.compactMap { key, value in
                key == value && languageInvariantKeys.contains(key) == false ? key : nil
            }
            XCTAssertTrue(
                untranslated.isEmpty,
                "\(languageCode) contains Japanese fallback values: \(untranslated)"
            )
        }
    }

    func testAllBuiltInMasterNamesAreTranslated() throws {
        let builtInNames = SeedMaster.ingredients.flatMap { $0.1.map(\.name) }
            + SeedMaster.noodles.map(\.name)
            + SeedMaster.soups.map(\.name)
        let categoryNames = IngredientCategory.allCases.map(\.rawValue)

        for languageCode in translatedLanguageCodes {
            let table = try strings(for: languageCode)
            let missing = (builtInNames + categoryNames).filter { key in
                guard let value = table[key] else { return true }
                return value.isEmpty
            }
            XCTAssertTrue(
                missing.isEmpty,
                "\(languageCode) missing master translations: \(missing)"
            )
        }
    }

    func testCriticalWorldAndMapFlowsAreTranslated() throws {
        let keys = [
            "ホーム", "アルバム", "地図", "分析", "設定",
            "言語", "アプリの言語", "言語設定を開く",
            "端末の優先言語に自動で合わせます。変更はiPhoneの設定で行えます。",
            "近くの麻辣湯", "店名・都市名で検索", "このエリアを検索",
            "この場所に店舗を追加", "表示範囲に店舗が見つかりませんでした",
            "位置情報の設定を開く", "Googleマップ", "Appleマップ",
            "店舗を保存できませんでした", "記録する", "バックアップと復元",
            "世界一食べたくなる麻辣湯",
            SampleDataService.sampleAddress,
            "記録データは端末内に保存します。地図検索・経路表示・購入確認にはAppleや選択した地図サービスとの通信を使います。"
        ]

        for languageCode in translatedLanguageCodes {
            let table = try strings(for: languageCode)
            let allowsSharedHanTerm = languageCode.hasPrefix("zh")
            let untranslated = keys.filter { key in
                guard let value = table[key] else { return true }
                return value == key && allowsSharedHanTerm == false
            }
            XCTAssertTrue(
                untranslated.isEmpty,
                "\(languageCode) untranslated critical keys: \(untranslated)"
            )
        }
    }

    func testPermissionAndAppNameLocalizationsAreBundled() throws {
        for languageCode in AppLocalization.supportedLanguageCodes {
            let bundle = try XCTUnwrap(AppLocalization.bundle(for: languageCode))
            let displayName = bundle.localizedString(
                forKey: "CFBundleDisplayName",
                value: nil,
                table: "InfoPlist"
            )
            XCTAssertFalse(displayName.isEmpty, "\(languageCode) has no app name")
            XCTAssertNotEqual(displayName, "CFBundleDisplayName")

            for permissionKey in [
                "NSCameraUsageDescription",
                "NSLocationWhenInUseUsageDescription",
                "NSPhotoLibraryUsageDescription"
            ] {
                let permission = bundle.localizedString(
                    forKey: permissionKey,
                    value: nil,
                    table: "InfoPlist"
                )
                XCTAssertFalse(permission.isEmpty)
                XCTAssertNotEqual(permission, permissionKey)
            }
        }
    }

    func testFormatPlaceholdersMatchAcrossLanguages() throws {
        let japanese = try strings(for: "ja")

        for languageCode in translatedLanguageCodes {
            let table = try strings(for: languageCode)
            for key in japanese.keys where key.contains("%") {
                XCTAssertEqual(
                    placeholders(in: table[key] ?? ""),
                    placeholders(in: key),
                    "\(languageCode) placeholders differ for \(key)"
                )
            }
        }
    }

    func testSimplifiedAndTraditionalChineseHaveDistinctLanguageNames() {
        let simplified = AppLocalization.displayName(for: "zh-Hans")
        let traditional = AppLocalization.displayName(for: "zh-Hant")

        XCTAssertNotEqual(simplified, traditional)
        XCTAssertNotEqual(simplified, "zh-Hans")
        XCTAssertNotEqual(traditional, "zh-Hant")
    }

    func testChineseDeviceRegionsChooseTheMatchingWritingSystem() {
        let available = ["en", "zh-Hans", "zh-Hant"]

        XCTAssertEqual(
            Bundle.preferredLocalizations(from: available, forPreferences: ["zh-CN"]).first,
            "zh-Hans"
        )
        XCTAssertEqual(
            Bundle.preferredLocalizations(from: available, forPreferences: ["zh-TW"]).first,
            "zh-Hant"
        )
        XCTAssertEqual(
            Bundle.preferredLocalizations(from: available, forPreferences: ["zh-SG"]).first,
            "zh-Hans"
        )
        XCTAssertEqual(
            Bundle.preferredLocalizations(from: available, forPreferences: ["zh-HK"]).first,
            "zh-Hant"
        )
        XCTAssertEqual(
            Bundle.preferredLocalizations(from: available, forPreferences: ["zh-MO"]).first,
            "zh-Hant"
        )
    }

    func testChineseCatalogsUseProductMeaningAndTaiwanTerminology() throws {
        let expectedTerms: [String: [String: String]] = [
            "zh-Hans": [
                "麻辣湯ログ": "麻辣烫记录",
                "ホーム": "首页",
                "記録": "记录",
                "店舗": "店铺",
                "辛さ": "辣度",
                "痺れ": "麻度",
                "保存": "保存",
                "バックアップと復元": "备份与恢复"
            ],
            "zh-Hant": [
                "麻辣湯ログ": "麻辣燙紀錄",
                "ホーム": "首頁",
                "記録": "紀錄",
                "店舗": "店家",
                "辛さ": "辣度",
                "痺れ": "麻度",
                "保存": "儲存",
                "バックアップと復元": "備份與還原"
            ]
        ]

        for (languageCode, expected) in expectedTerms {
            let table = try strings(for: languageCode)
            for (key, value) in expected {
                XCTAssertEqual(table[key], value, "\(languageCode) term differs for \(key)")
            }
        }
    }

    func testCustomMasterNameIsNeverTranslated() throws {
        let englishBundle = try XCTUnwrap(
            AppLocalization.bundle(for: "en")
        )

        XCTAssertEqual(
            AppLocalization.masterName("白菜", isCustom: true, bundle: englishBundle),
            "白菜"
        )
        XCTAssertNotEqual(
            AppLocalization.masterName("白菜", isCustom: false, bundle: englishBundle),
            "白菜"
        )
    }

    func testEnglishPluralRulesUseSingularAndPluralForms() throws {
        let bundle = try XCTUnwrap(AppLocalization.bundle(for: "en"))

        XCTAssertEqual(localizedCount("%lld杯", count: 1, bundle: bundle), "1 bowl")
        XCTAssertEqual(localizedCount("%lld杯", count: 2, bundle: bundle), "2 bowls")
        XCTAssertEqual(localizedCount("%lld店を表示", count: 1, bundle: bundle), "1 store shown")
        XCTAssertEqual(localizedCount("%lld店を表示", count: 2, bundle: bundle), "2 stores shown")
    }

    func testGermanPluralRulesUseSingularAndPluralForms() throws {
        let bundle = try XCTUnwrap(AppLocalization.bundle(for: "de"))

        XCTAssertEqual(localizedCount("%lld杯", count: 1, bundle: bundle), "1 Portion")
        XCTAssertEqual(localizedCount("%lld杯", count: 2, bundle: bundle), "2 Portionen")
        XCTAssertEqual(
            localizedCount("%lld店を表示", count: 1, bundle: bundle),
            "1 Restaurant angezeigt"
        )
        XCTAssertEqual(
            localizedCount("%lld店を表示", count: 2, bundle: bundle),
            "2 Restaurants angezeigt"
        )
    }

    func testEveryEnglishAndGermanPluralRuleFormatsCommonCounts() throws {
        let englishRules = try stringsdict(for: "en")
        let germanRules = try stringsdict(for: "de")

        XCTAssertEqual(englishRules.count, 11)
        XCTAssertEqual(Set(englishRules.keys), Set(germanRules.keys))

        for languageCode in ["en", "de"] {
            let bundle = try XCTUnwrap(AppLocalization.bundle(for: languageCode))
            for key in englishRules.keys {
                for count in [0, 1, 2] {
                    let value = localizedCount(key, count: count, bundle: bundle)
                    XCTAssertFalse(value.isEmpty, "\(languageCode) returned an empty plural for \(key)")
                    XCTAssertNotEqual(value, key, "\(languageCode) did not apply plural rules for \(key)")
                    XCTAssertTrue(
                        value.contains(String(count)),
                        "\(languageCode) plural omitted count \(count) for \(key): \(value)"
                    )
                }
            }
        }
    }

    private func strings(for languageCode: String) throws -> [String: String] {
        let bundle = try XCTUnwrap(AppLocalization.bundle(for: languageCode))
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "Localizable",
                withExtension: "strings"
            )
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String]
        )
    }

    private var translatedLanguageCodes: [String] {
        AppLocalization.supportedLanguageCodes.filter { $0 != "ja" }
    }

    private func stringsdict(for languageCode: String) throws -> [String: Any] {
        let bundle = try XCTUnwrap(AppLocalization.bundle(for: languageCode))
        let url = try XCTUnwrap(
            bundle.url(forResource: "Localizable", withExtension: "stringsdict")
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
    }

    private func placeholders(in value: String) -> [String] {
        let expression = try! NSRegularExpression(
            pattern: #"%([0-9]+\$)?(@|lld|ld|d|f)"#
        )
        let range = NSRange(value.startIndex..., in: value)
        let tokens = expression.matches(in: value, range: range).compactMap { match
            -> (position: Int?, type: String)? in
            guard let typeRange = Range(match.range(at: 2), in: value) else { return nil }
            let type = "%" + String(value[typeRange])
            let position: Int?
            if let positionRange = Range(match.range(at: 1), in: value) {
                position = Int(value[positionRange].dropLast())
            } else {
                position = nil
            }
            return (position, type)
        }
        guard tokens.contains(where: { $0.position != nil }) else {
            return tokens.map(\.type)
        }
        guard tokens.allSatisfy({ $0.position != nil }) else {
            return ["<mixed positional placeholders>"]
        }
        return tokens.sorted { ($0.position ?? 0) < ($1.position ?? 0) }.map(\.type)
    }

    private func localizedCount(_ key: String, count: Int, bundle: Bundle) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        let languageCode = URL(fileURLWithPath: bundle.bundlePath)
            .deletingPathExtension()
            .lastPathComponent
        return String(
            format: format,
            locale: Locale(identifier: languageCode),
            arguments: [Int64(count)]
        )
    }
}
