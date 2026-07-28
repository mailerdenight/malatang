import Foundation
import UIKit

/// アプリ内地図は使わず、Googleマップ／Appleマップを外部起動する。
enum MapLauncher {

    enum Destination {
        case coordinate(latitude: Double, longitude: Double, label: String)
        case query(String)

        static func make(for store: Store) -> Destination {
            if let latitude = store.latitude, let longitude = store.longitude {
                return .coordinate(latitude: latitude, longitude: longitude, label: store.displayName)
            }
            let query = [store.displayName, store.address]
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
            return .query(query.isEmpty ? store.name : query)
        }
    }

    enum Provider: String, CaseIterable, Identifiable {
        case google
        case apple

        var id: String { rawValue }

        var title: String {
            switch self {
            case .google: return "Googleマップ"
            case .apple: return "Appleマップ"
            }
        }

        var symbol: String {
            switch self {
            case .google: return "globe.asia.australia"
            case .apple: return "map"
            }
        }
    }

    /// Googleマップアプリが入っているか。未インストールでも Web にフォールバックできる。
    static var isGoogleMapsInstalled: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - 地図で開く

    static func openMap(_ destination: Destination, using provider: Provider) {
        guard let url = mapURL(destination, provider: provider) else { return }
        UIApplication.shared.open(url)
    }

    static func openDirections(_ destination: Destination, using provider: Provider) {
        guard let url = directionsURL(destination, provider: provider) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - URL 生成

    static func mapURL(_ destination: Destination, provider: Provider) -> URL? {
        switch provider {
        case .google:
            switch destination {
            case let .coordinate(latitude, longitude, _):
                let app = "comgooglemaps://?q=\(latitude),\(longitude)&center=\(latitude),\(longitude)&zoom=17"
                let web = "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)"
                return preferred(appURL: app, webURL: web)
            case let .query(text):
                let encoded = encode(text)
                let app = "comgooglemaps://?q=\(encoded)"
                let web = "https://www.google.com/maps/search/?api=1&query=\(encoded)"
                return preferred(appURL: app, webURL: web)
            }
        case .apple:
            switch destination {
            case let .coordinate(latitude, longitude, label):
                return URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(encode(label))")
            case let .query(text):
                return URL(string: "http://maps.apple.com/?q=\(encode(text))")
            }
        }
    }

    static func directionsURL(_ destination: Destination, provider: Provider) -> URL? {
        switch provider {
        case .google:
            switch destination {
            case let .coordinate(latitude, longitude, _):
                let app = "comgooglemaps://?daddr=\(latitude),\(longitude)&directionsmode=transit"
                let web = "https://www.google.com/maps/dir/?api=1&destination=\(latitude),\(longitude)"
                return preferred(appURL: app, webURL: web)
            case let .query(text):
                let encoded = encode(text)
                let app = "comgooglemaps://?daddr=\(encoded)&directionsmode=transit"
                let web = "https://www.google.com/maps/dir/?api=1&destination=\(encoded)"
                return preferred(appURL: app, webURL: web)
            }
        case .apple:
            switch destination {
            case let .coordinate(latitude, longitude, _):
                return URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=r")
            case let .query(text):
                return URL(string: "http://maps.apple.com/?daddr=\(encode(text))&dirflg=r")
            }
        }
    }

    private static func preferred(appURL: String, webURL: String) -> URL? {
        if isGoogleMapsInstalled, let url = URL(string: appURL) {
            return url
        }
        return URL(string: webURL)
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
