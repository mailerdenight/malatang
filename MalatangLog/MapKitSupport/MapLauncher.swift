import Foundation
import CoreLocation
import UIKit

/// 保存した店舗をGoogleマップ／Appleマップで外部表示する。
enum MapLauncher {

    enum Destination {
        case coordinate(latitude: Double, longitude: Double, label: String)
        case query(String)

        static func make(for store: Store) -> Destination {
            if let latitude = store.latitude,
               let longitude = store.longitude,
               CLLocationCoordinate2DIsValid(
                   CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
               ) {
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
            case .google: return String(localized: "Googleマップ")
            case .apple: return String(localized: "Appleマップ")
            }
        }

        var symbol: String {
            switch self {
            case .google: return "globe.asia.australia"
            case .apple: return "map"
            }
        }
    }

    /// 表示名の切り替え用。起動自体はアプリの有無に依存しないHTTPS URLを使う。
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
            case let .coordinate(latitude, longitude, label):
                guard let coordinate = coordinateString(latitude: latitude, longitude: longitude) else {
                    return mapURL(.query(label), provider: provider)
                }
                return googleURL(
                    path: "/maps/search/",
                    queryItems: [
                        URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: "query", value: coordinate)
                    ]
                )
            case let .query(text):
                return googleURL(
                    path: "/maps/search/",
                    queryItems: [
                        URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: "query", value: text)
                    ]
                )
            }
        case .apple:
            switch destination {
            case let .coordinate(latitude, longitude, label):
                guard let coordinate = coordinateString(latitude: latitude, longitude: longitude) else {
                    return mapURL(.query(label), provider: provider)
                }
                return appleURL(queryItems: [
                    URLQueryItem(name: "ll", value: coordinate),
                    URLQueryItem(name: "q", value: label)
                ])
            case let .query(text):
                return appleURL(queryItems: [URLQueryItem(name: "q", value: text)])
            }
        }
    }

    static func directionsURL(_ destination: Destination, provider: Provider) -> URL? {
        switch provider {
        case .google:
            switch destination {
            case let .coordinate(latitude, longitude, label):
                guard let coordinate = coordinateString(latitude: latitude, longitude: longitude) else {
                    return directionsURL(.query(label), provider: provider)
                }
                return googleURL(
                    path: "/maps/dir/",
                    queryItems: [
                        URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: "destination", value: coordinate)
                    ]
                )
            case let .query(text):
                return googleURL(
                    path: "/maps/dir/",
                    queryItems: [
                        URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: "destination", value: text)
                    ]
                )
            }
        case .apple:
            switch destination {
            case let .coordinate(latitude, longitude, label):
                guard let coordinate = coordinateString(latitude: latitude, longitude: longitude) else {
                    return directionsURL(.query(label), provider: provider)
                }
                return appleURL(queryItems: [
                    URLQueryItem(name: "daddr", value: coordinate)
                ])
            case let .query(text):
                return appleURL(queryItems: [
                    URLQueryItem(name: "daddr", value: text)
                ])
            }
        }
    }

    private static func googleURL(
        path: String,
        queryItems: [URLQueryItem]
    ) -> URL? {
        makeHTTPSURL(host: "www.google.com", path: path, queryItems: queryItems)
    }

    private static func appleURL(queryItems: [URLQueryItem]) -> URL? {
        makeHTTPSURL(host: "maps.apple.com", path: "/", queryItems: queryItems)
    }

    private static func makeHTTPSURL(
        host: String,
        path: String,
        queryItems: [URLQueryItem]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    private static func coordinateString(
        latitude: Double,
        longitude: Double
    ) -> String? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return String(
            format: "%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            latitude,
            longitude
        )
    }
}
