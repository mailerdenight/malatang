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
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertEqual(queryValue("ll", in: url), "35.000000,139.000000")
        XCTAssertEqual(queryValue("q", in: url), "店")
    }

    func testAppleDirectionsURLIsGeneratedForQuery() throws {
        let destination = MapLauncher.Destination.query("麻辣湯 新宿")
        let url = try XCTUnwrap(MapLauncher.directionsURL(destination, provider: .apple))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertEqual(queryValue("daddr", in: url), "麻辣湯 新宿")
        XCTAssertNil(queryValue("dirflg", in: url), "移動手段は地図アプリ側で選べる")
    }

    func testGoogleMapAlwaysUsesHTTPSUniversalURL() throws {
        let destination = MapLauncher.Destination.coordinate(latitude: 35.0, longitude: 139.0, label: "店")
        let url = try XCTUnwrap(MapLauncher.mapURL(destination, provider: .google))

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertEqual(url.path, "/maps/search")
        XCTAssertEqual(queryValue("api", in: url), "1")
        XCTAssertEqual(queryValue("query", in: url), "35.000000,139.000000")
    }

    func testGoogleQueryKeepsReservedCharactersInsideSearchText() throws {
        let query = "A&B+麻辣湯? Hải Châu #1"
        let destination = MapLauncher.Destination.query(query)
        let url = try XCTUnwrap(MapLauncher.mapURL(destination, provider: .google))

        XCTAssertEqual(queryValue("query", in: url), query)
        XCTAssertTrue(url.absoluteString.contains("A%26B"))
    }

    func testDirectionsDoNotForceTravelMode() throws {
        let destination = MapLauncher.Destination.query("Malatang Da Nang")
        let url = try XCTUnwrap(MapLauncher.directionsURL(destination, provider: .google))

        XCTAssertEqual(url.path, "/maps/dir")
        XCTAssertEqual(queryValue("destination", in: url), "Malatang Da Nang")
        XCTAssertNil(queryValue("travelmode", in: url))
        XCTAssertNil(queryValue("directionsmode", in: url))
    }

    func testInvalidCoordinateFallsBackToLabelQueryForBothProviders() throws {
        let destination = MapLauncher.Destination.coordinate(
            latitude: 123,
            longitude: 456,
            label: "Malatang Da Nang"
        )

        let googleMap = try XCTUnwrap(MapLauncher.mapURL(destination, provider: .google))
        let appleMap = try XCTUnwrap(MapLauncher.mapURL(destination, provider: .apple))
        let googleDirections = try XCTUnwrap(
            MapLauncher.directionsURL(destination, provider: .google)
        )
        let appleDirections = try XCTUnwrap(
            MapLauncher.directionsURL(destination, provider: .apple)
        )

        XCTAssertEqual(queryValue("query", in: googleMap), "Malatang Da Nang")
        XCTAssertEqual(queryValue("q", in: appleMap), "Malatang Da Nang")
        XCTAssertEqual(queryValue("destination", in: googleDirections), "Malatang Da Nang")
        XCTAssertEqual(queryValue("daddr", in: appleDirections), "Malatang Da Nang")
    }

    func testDestinationIgnoresInvalidStoredCoordinate() {
        let store = Store(
            name: "座標不正店",
            address: "Da Nang",
            latitude: 100,
            longitude: 200
        )

        if case .query(let text) = MapLauncher.Destination.make(for: store) {
            XCTAssertTrue(text.contains("座標不正店"))
            XCTAssertTrue(text.contains("Da Nang"))
        } else {
            XCTFail("無効座標は店名・住所検索へフォールバックする")
        }
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
