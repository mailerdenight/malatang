import Contacts
import CoreLocation
import MapKit
import XCTest
@testable import MalatangLog

final class MapAddressFormatterTests: XCTestCase {
    func testVietnamesePostalAddressUsesSystemFormattingWithoutNewlines() {
        let address = CNMutablePostalAddress()
        address.street = "36 Bạch Đằng"
        address.subLocality = "Hải Châu 1"
        address.city = "Đà Nẵng"
        address.country = "Việt Nam"
        address.isoCountryCode = "VN"
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 16.0678, longitude: 108.2208),
            postalAddress: address
        )

        let formatted = MapAddressFormatter.string(from: placemark)

        XCTAssertTrue(formatted.contains("36 Bạch Đằng"))
        XCTAssertTrue(formatted.contains("Đà Nẵng"))
        XCTAssertFalse(formatted.contains("\n"))
    }

    func testCLPlacemarkOverloadCanFormatReverseGeocoderResult() {
        let address = CNMutablePostalAddress()
        address.street = "1-1 Chiyoda"
        address.city = "Chiyoda City"
        address.state = "Tokyo"
        address.postalCode = "100-0001"
        address.country = "Japan"
        address.isoCountryCode = "JP"
        let mapPlacemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 35.6852, longitude: 139.7528),
            postalAddress: address
        )
        let locationPlacemark: CLPlacemark = mapPlacemark

        let formatted = MapAddressFormatter.string(from: locationPlacemark)

        XCTAssertTrue(formatted.contains("Chiyoda"))
        XCTAssertTrue(formatted.contains("100-0001"))
        XCTAssertFalse(formatted.contains("\n"))
    }
}
