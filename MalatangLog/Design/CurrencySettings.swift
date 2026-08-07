import Foundation
import Observation

enum AppCurrency: String, CaseIterable, Identifiable {
    case jpy = "JPY"
    case usd = "USD"
    case cny = "CNY"
    case twd = "TWD"
    case hkd = "HKD"
    case krw = "KRW"
    case vnd = "VND"
    case thb = "THB"
    case idr = "IDR"
    case eur = "EUR"

    var id: String { rawValue }

    var title: String { "\(rawValue) \(symbol)" }

    var symbol: String {
        switch self {
        case .jpy, .cny: return "¥"
        case .usd: return "$"
        case .twd: return "NT$"
        case .hkd: return "HK$"
        case .krw: return "₩"
        case .vnd: return "₫"
        case .thb: return "฿"
        case .idr: return "Rp"
        case .eur: return "€"
        }
    }

    var systemImage: String {
        switch self {
        case .jpy, .cny: return "yensign.circle"
        case .usd: return "dollarsign.circle"
        case .eur: return "eurosign.circle"
        default: return "creditcard"
        }
    }

    var locale: Locale {
        switch self {
        case .jpy: return Locale(identifier: "ja_JP")
        case .usd: return Locale(identifier: "en_US")
        case .cny: return Locale(identifier: "zh_CN")
        case .twd: return Locale(identifier: "zh_TW")
        case .hkd: return Locale(identifier: "zh_HK")
        case .krw: return Locale(identifier: "ko_KR")
        case .vnd: return Locale(identifier: "vi_VN")
        case .thb: return Locale(identifier: "th_TH")
        case .idr: return Locale(identifier: "id_ID")
        case .eur: return Locale(identifier: "de_DE")
        }
    }

    static func defaultCode(
        for preferredLocalizations: [String] = Bundle.main.preferredLocalizations
    ) -> String {
        let language = preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        if language.hasPrefix("ja") { return AppCurrency.jpy.rawValue }
        if language.hasPrefix("ko") { return AppCurrency.krw.rawValue }
        if language.hasPrefix("vi") { return AppCurrency.vnd.rawValue }
        if language.hasPrefix("th") { return AppCurrency.thb.rawValue }
        if language.hasPrefix("id") { return AppCurrency.idr.rawValue }
        if language.hasPrefix("de") { return AppCurrency.eur.rawValue }
        if language.hasPrefix("zh-Hant") || language.hasPrefix("zh_TW") || language.hasPrefix("zh-HK") {
            return AppCurrency.twd.rawValue
        }
        if language.hasPrefix("zh") { return AppCurrency.cny.rawValue }
        return AppCurrency.usd.rawValue
    }

    static func normalizedCode(_ code: String?) -> String {
        guard let code, let currency = AppCurrency(rawValue: code) else {
            return defaultCode()
        }
        return currency.rawValue
    }

    static func format(_ amount: Int, code: String) -> String {
        let currency = AppCurrency(rawValue: code) ?? AppCurrency(rawValue: defaultCode()) ?? .jpy
        return amount.formatted(
            .currency(code: currency.rawValue)
                .locale(currency.locale)
                .precision(.fractionLength(0))
        )
    }
}

@MainActor
@Observable
final class CurrencySettings {
    static let storageKey = "defaultCurrencyCode"
    static let confirmationStorageKey = "didConfirmDefaultCurrency"
    static let shared = CurrencySettings()

    private let defaults: UserDefaults

    var defaultCurrencyCode: String {
        didSet {
            defaults.set(AppCurrency.normalizedCode(defaultCurrencyCode), forKey: Self.storageKey)
        }
    }

    var didConfirmDefaultCurrency: Bool {
        didSet {
            defaults.set(didConfirmDefaultCurrency, forKey: Self.confirmationStorageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultCurrencyCode = AppCurrency.normalizedCode(
            defaults.string(forKey: Self.storageKey)
        )
        didConfirmDefaultCurrency = defaults.bool(forKey: Self.confirmationStorageKey)
        defaults.set(defaultCurrencyCode, forKey: Self.storageKey)
    }

    var defaultCurrency: AppCurrency {
        AppCurrency(rawValue: defaultCurrencyCode) ?? .jpy
    }

    func isLocked(by servings: [Serving]) -> Bool {
        servings.contains { SampleDataService.isSample($0) == false }
    }

    func needsInitialConfirmation(servings: [Serving]) -> Bool {
        didConfirmDefaultCurrency == false && isLocked(by: servings) == false
    }

    func baseCurrencyCode(for servings: [Serving]) -> String {
        servings
            .filter { SampleDataService.isSample($0) == false }
            .sorted { ($0.createdAt, $0.date) < ($1.createdAt, $1.date) }
            .first
            .map { AppCurrency.normalizedCode($0.currencyCode) }
            ?? defaultCurrencyCode
    }

    func format(_ amount: Int, code: String? = nil) -> String {
        AppCurrency.format(amount, code: code ?? defaultCurrencyCode)
    }
}
