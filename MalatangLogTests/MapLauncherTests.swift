import XCTest
@testable import MalatangLog

final class MapLauncherTests: XCTestCase {

    func testDestinationUsesCoordinateWhenAvailable() {
        let store = Store(name: "テスト店", branch: "本店", address: "東京都", latitude: 35.68, longitude: 139.76)
        if case .coordinate(let latitude, let longitude, let label) = MapLauncher.Destination.make(for: store) {
            XCTAssertEqual(latitude, 35.68, accuracy: 0.0001)
            XCTAssertEqual(longitude, 139.76, accuracy: 0.0001)
            XCTAssertEqual(label, "テスト店 本店")
        } else {
            XCTFail("座標があるときは coordinate になる")
        }
    }

    func testDestinationFallsBackToQuery() {
        let store = Store(name: "座標なし店", address: "大阪市北区")
        if case .query(let text) = MapLauncher.Destination.make(for: store) {
            XCTAssertTrue(text.contains("座標なし店"))
            XCTAssertTrue(text.contains("大阪市北区"))
        } else {
            XCTFail("座標がないときは query になる")
        }
    }

    func testDestinationWorksWithNameOnly() {
        let store = Store(name: "店名だけ")
        if case .query(let text) = MapLauncher.Destination.make(for: store) {
            XCTAssertEqual(text, "店名だけ")
        } else {
            XCTFail("店名だけでも query になる")
        }
    }

    func testAppleMapURLIsGeneratedForCoordinate() throws {
        let destination = MapLauncher.Destination.coordinate(latitude: 35.0, longitude: 139.0, label: "店")
        let url = try XCTUnwrap(MapLauncher.mapURL(destination, provider: .apple))
        XCTAssertTrue(url.absoluteString.contains("maps.apple.com"))
        XCTAssertTrue(url.absoluteString.contains("35.0,139.0"))
    }

    func testAppleDirectionsURLIsGeneratedForQuery() throws {
        let destination = MapLauncher.Destination.query("麻辣湯 新宿")
        let url = try XCTUnwrap(MapLauncher.directionsURL(destination, provider: .apple))
        XCTAssertTrue(url.absoluteString.contains("daddr="))
    }

    func testGoogleURLFallsBackToWebWhenAppMissing() throws {
        // シミュレータには Googleマップ が入っていないため、Web URL が返る
        let destination = MapLauncher.Destination.coordinate(latitude: 35.0, longitude: 139.0, label: "店")
        let url = try XCTUnwrap(MapLauncher.mapURL(destination, provider: .google))
        if MapLauncher.isGoogleMapsInstalled {
            XCTAssertEqual(url.scheme, "comgooglemaps")
        } else {
            XCTAssertTrue(url.absoluteString.hasPrefix("https://www.google.com/maps"))
        }
    }
}
