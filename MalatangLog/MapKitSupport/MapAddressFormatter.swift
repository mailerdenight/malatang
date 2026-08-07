import Contacts
import CoreLocation
import Foundation
import MapKit

/// MapKit/Core Location が返す住所を、国ごとの順序を保った表示用文字列にする。
enum MapAddressFormatter {
    static func string(from placemark: MKPlacemark) -> String {
        if let postalAddress = placemark.postalAddress,
           let formatted = formatted(postalAddress) {
            return formatted
        }

        if let title = nonempty(placemark.title) {
            return title
        }

        return fallbackString(from: placemark)
    }

    static func string(from placemark: CLPlacemark) -> String {
        if let postalAddress = placemark.postalAddress,
           let formatted = formatted(postalAddress) {
            return formatted
        }

        if let name = nonempty(placemark.name) {
            return name
        }

        return fallbackString(from: placemark)
    }

    private static func formatted(_ address: CNPostalAddress) -> String? {
        nonempty(
            CNPostalAddressFormatter.string(
                from: address,
                style: .mailingAddress
            )
        )
    }

    private static func fallbackString(from placemark: CLPlacemark) -> String {
        let parts = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ]
        .compactMap(nonempty)

        var seen = Set<String>()
        let uniqueParts = parts.filter {
            seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: posixLocale)).inserted
        }
        return uniqueParts.joined(separator: ", ")
    }

    /// 郵便住所の国別の並び順は保ち、UIと外部地図URLで扱いやすい1行に畳む。
    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let singleLine = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return singleLine.isEmpty ? nil : singleLine
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
}
