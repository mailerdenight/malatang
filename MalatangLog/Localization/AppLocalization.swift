import Foundation

enum AppLocalization {
    static let supportedLanguageCodes = [
        "en", "ja", "vi", "ko", "zh-Hans", "zh-Hant", "th", "de", "id"
    ]

    /// 動的なキーを翻訳する。未登録キーは原文を返すため、既存データを壊さない。
    static func string(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func masterName(
        _ storedName: String,
        isCustom: Bool,
        bundle: Bundle = .main
    ) -> String {
        isCustom ? storedName : string(storedName, bundle: bundle)
    }

    static func list(_ values: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = preferredLocale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    static var preferredLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// 言語だけでなく文字体系も含めて表示するため、簡体字と繁体字を区別できる。
    static func displayName(for languageIdentifier: String) -> String {
        Locale(identifier: languageIdentifier)
            .localizedString(forIdentifier: languageIdentifier)
            ?? languageIdentifier
    }

    static func bundle(for languageCode: String, in parent: Bundle = .main) -> Bundle? {
        guard let path = parent.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
