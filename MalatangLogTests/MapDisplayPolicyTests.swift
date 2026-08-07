import XCTest
@testable import MalatangLog

final class MapDisplayPolicyTests: XCTestCase {
    func testSavedCoordinateStoreAppearsWithoutSearchResult() {
        let store = Store(
            name: "Lẩu Malatang",
            address: "Đà Nẵng, Việt Nam",
            latitude: 16.0544,
            longitude: 108.2022
        )

        let results = MapDisplayPolicy.mergedResults(
            searchResults: [],
            savedStores: [store]
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Lẩu Malatang")
        XCTAssertEqual(results.first?.latitude, 16.0544)
        XCTAssertEqual(results.first?.longitude, 108.2022)
    }

    func testSavedStoreDoesNotDuplicateMatchingSearchResult() {
        let store = Store(
            name: "Lẩu Malatang",
            address: "Đà Nẵng, Việt Nam",
            latitude: 16.0544,
            longitude: 108.2022
        )
        let searchResult = StoreSearchResult(
            name: "Lẩu Malatang",
            address: "Đà Nẵng, Việt Nam",
            latitude: 16.05442,
            longitude: 108.20222
        )

        let results = MapDisplayPolicy.mergedResults(
            searchResults: [searchResult],
            savedStores: [store]
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, searchResult.id)
    }

    func testSavedStoreWithoutValidCoordinateIsNotPlacedOnMap() {
        let store = Store(
            name: "店名だけ",
            latitude: 95,
            longitude: 108.2022
        )

        let results = MapDisplayPolicy.mergedResults(
            searchResults: [],
            savedStores: [store]
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testDuplicateSavedStoresDoNotCreateDuplicateMapIdentifiers() {
        let first = Store(
            name: "Malatang House",
            latitude: 16.0544,
            longitude: 108.2022
        )
        let duplicate = Store(
            name: "Malatang House",
            latitude: 16.0544,
            longitude: 108.2022
        )

        let results = MapDisplayPolicy.mergedResults(
            searchResults: [],
            savedStores: [first, duplicate]
        )

        XCTAssertEqual(results.count, 1)
    }
}
