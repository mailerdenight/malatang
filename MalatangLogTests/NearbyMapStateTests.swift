import XCTest
import MapKit
@testable import MalatangLog

final class NearbyMapStateTests: XCTestCase {
    func testDaNangIsRecognizedAsTheSameCityWithOrWithoutDiacritics() {
        XCTAssertTrue(
            MapSearchQueryPolicy.matchesGeographicName(
                "Đà Nẵng",
                candidates: ["Da Nang", "Vietnam"]
            )
        )
        XCTAssertTrue(
            MapSearchQueryPolicy.matchesGeographicName(
                "Da Nang, Vietnam",
                candidates: ["Đà Nẵng", "Việt Nam"]
            )
        )
    }

    func testStoreNameContainingAPlaceWordIsNotMistakenForACity() {
        XCTAssertFalse(
            MapSearchQueryPolicy.matchesGeographicName(
                "Paris Baguette",
                candidates: ["Paris", "France"]
            )
        )
    }

    func testAdministrativeSuffixDifferencesStillMatchTheSameCity() {
        XCTAssertTrue(
            MapSearchQueryPolicy.matchesGeographicName("東京", candidates: ["東京都"])
        )
        XCTAssertTrue(
            MapSearchQueryPolicy.matchesGeographicName("北京", candidates: ["北京市"])
        )
        XCTAssertTrue(
            MapSearchQueryPolicy.matchesGeographicName("서울", candidates: ["서울특별시"])
        )
        XCTAssertTrue(
            MapSearchQueryPolicy.matchesGeographicName("台北", candidates: ["臺北市"])
        )
    }

    func testGeocodingLocaleFollowsTheQueryScriptInsteadOfTheDeviceLanguage() {
        XCTAssertEqual(MapSearchQueryPolicy.geocodingLocale(for: "Da Nang").identifier, "en")
        XCTAssertEqual(MapSearchQueryPolicy.geocodingLocale(for: "Đà Nẵng").identifier, "en")
        XCTAssertEqual(MapSearchQueryPolicy.geocodingLocale(for: "ダナン").identifier, "ja")
        XCTAssertEqual(
            MapSearchQueryPolicy.geocodingLocale(
                for: "東京",
                preferredLanguageIdentifier: "ja"
            ).identifier,
            "ja"
        )
        XCTAssertEqual(MapSearchQueryPolicy.geocodingLocale(for: "다낭").identifier, "ko")
        XCTAssertEqual(MapSearchQueryPolicy.geocodingLocale(for: "ดานัง").identifier, "th")
    }

    func testChineseGeocodingKeepsThePreferredWritingSystem() {
        XCTAssertEqual(
            MapSearchQueryPolicy.geocodingLocale(
                for: "岘港",
                preferredLanguageIdentifier: "zh-Hans"
            ).identifier,
            "zh-Hans"
        )
        XCTAssertEqual(
            MapSearchQueryPolicy.geocodingLocale(
                for: "峴港",
                preferredLanguageIdentifier: "zh-Hant"
            ).identifier,
            "zh-Hant"
        )
    }

    func testAutomaticSearchUsesCoreAndPreferredLanguageSpellings() {
        XCTAssertEqual(
            StoreSearchService.automaticKeywords(preferredLanguageIdentifier: "th"),
            [
                "malatang", "mala tang", "麻辣烫", "麻辣燙", "麻辣湯", "หม่าล่าทั่ง"
            ]
        )
        XCTAssertEqual(
            StoreSearchService.automaticKeywords(preferredLanguageIdentifier: "ko"),
            ["malatang", "mala tang", "麻辣烫", "麻辣燙", "麻辣湯", "마라탕"]
        )
        XCTAssertEqual(
            StoreSearchService.automaticKeywords(preferredLanguageIdentifier: "de"),
            ["malatang", "mala tang", "麻辣烫", "麻辣燙", "麻辣湯"]
        )
    }

    func testExplicitKeywordIsNotExpanded() {
        XCTAssertEqual(
            StoreSearchService.keywords(for: "  lẩu mala  "),
            ["lẩu mala"]
        )
        XCTAssertEqual(
            StoreSearchService.keywords(for: "麻辣湯"),
            ["麻辣湯"]
        )
    }

    func testSearchResultIDIsStableAcrossRefreshes() {
        let first = makeResult(name: "七宝麻辣湯 渋谷店")
        let refreshed = makeResult(name: "七宝麻辣湯 渋谷店")

        XCTAssertEqual(first.id, refreshed.id)
    }

    func testSearchResultIDDistinguishesBranchesWithSameName() {
        let shibuya = makeResult(
            name: "麻辣湯",
            latitude: 35.6580,
            longitude: 139.7016
        )
        let shinjuku = makeResult(
            name: "麻辣湯",
            latitude: 35.6938,
            longitude: 139.7034
        )

        XCTAssertNotEqual(shibuya.id, shinjuku.id)
    }

    func testSearchResultIDNormalizesCaseWidthAndDiacriticsDeterministically() {
        let first = makeResult(name: "MÁLÁTANG")
        let second = makeResult(name: "malatang")

        XCTAssertEqual(first.id, second.id)
    }

    func testDuplicateSearchHitsWithSmallCoordinateDriftAreMerged() {
        let first = makeResult(
            name: "Malatang House",
            address: "Hải Châu, Đà Nẵng",
            latitude: 16.0544,
            longitude: 108.2022
        )
        let repeated = makeResult(
            name: "MALATANG HOUSE",
            address: "Hải Châu, Đà Nẵng",
            latitude: 16.05445,
            longitude: 108.2022
        )

        let merged = StoreSearchService.removingDuplicates(from: [first, repeated])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, first.id)
    }

    func testNearbyDifferentNamedShopsAtSameAddressAreNotMerged() {
        let first = makeResult(
            name: "Malatang House",
            address: "Food Court, Đà Nẵng",
            latitude: 16.0544,
            longitude: 108.2022
        )
        let neighbor = makeResult(
            name: "Mala Kitchen",
            address: "Food Court, Đà Nẵng",
            latitude: 16.05441,
            longitude: 108.2022
        )

        XCTAssertEqual(
            StoreSearchService.removingDuplicates(from: [first, neighbor]).count,
            2
        )
    }

    func testSameNamedShopsFartherThanToleranceAreNotMerged() {
        let first = makeResult(
            name: "Malatang",
            latitude: 16.0544,
            longitude: 108.2022
        )
        let separateBranch = makeResult(
            name: "Malatang",
            latitude: 16.0554,
            longitude: 108.2022
        )

        XCTAssertEqual(
            StoreSearchService.removingDuplicates(from: [first, separateBranch]).count,
            2
        )
    }

    func testWorldScaleRegionIsClampedToTwentyFiveKilometerRadius() {
        let worldScale = region(
            latitude: 16.0544,
            longitude: 108.2022,
            latitudeDelta: 10,
            longitudeDelta: 10
        )
        let clamped = StoreSearchService.clampedRegion(worldScale)
        let center = CLLocation(
            latitude: clamped.center.latitude,
            longitude: clamped.center.longitude
        )
        let north = CLLocation(
            latitude: clamped.center.latitude + clamped.span.latitudeDelta / 2,
            longitude: clamped.center.longitude
        )
        let east = CLLocation(
            latitude: clamped.center.latitude,
            longitude: clamped.center.longitude + clamped.span.longitudeDelta / 2
        )

        XCTAssertLessThanOrEqual(
            StoreSearchService.searchRadius(for: worldScale),
            StoreSearchService.maximumSearchDistance
        )
        XCTAssertLessThanOrEqual(center.distance(from: north), 25_500)
        XCTAssertLessThanOrEqual(center.distance(from: east), 25_500)
    }

    func testSelectionResolvesAfterResultsAreRefreshed() throws {
        let selected = makeResult(name: "双子麻辣湯")
        let refreshed = makeResult(name: "双子麻辣湯")

        let resolved = try XCTUnwrap(
            NearbyMapSelectionPolicy.selectedResult(
                id: selected.id,
                in: [refreshed]
            )
        )

        XCTAssertEqual(resolved.id, selected.id)
    }

    func testSmallCameraAdjustmentDoesNotTriggerSearch() {
        let previous = region(
            latitude: 35.6580,
            longitude: 139.7016,
            latitudeDelta: 0.05,
            longitudeDelta: 0.05
        )
        let current = region(
            latitude: 35.6581,
            longitude: 139.7017,
            latitudeDelta: 0.05,
            longitudeDelta: 0.05
        )

        XCTAssertFalse(
            NearbyMapSearchPolicy.hasMeaningfulMapChange(
                from: previous,
                to: current
            )
        )
    }

    func testUserScaleChangeTriggersSearch() {
        let previous = region(
            latitude: 35.6580,
            longitude: 139.7016,
            latitudeDelta: 0.05,
            longitudeDelta: 0.05
        )
        let current = region(
            latitude: 35.6580,
            longitude: 139.7016,
            latitudeDelta: 0.08,
            longitudeDelta: 0.08
        )

        XCTAssertTrue(
            NearbyMapSearchPolicy.hasMeaningfulMapChange(
                from: previous,
                to: current
            )
        )
    }

    func testVisibleRegionContainsDaNangCoordinateButNotTokyo() {
        let daNangRegion = region(
            latitude: 16.0544,
            longitude: 108.2022,
            latitudeDelta: 0.08,
            longitudeDelta: 0.08
        )

        XCTAssertTrue(
            NearbyMapSearchPolicy.contains(
                CLLocationCoordinate2D(latitude: 16.0610, longitude: 108.2100),
                in: daNangRegion
            )
        )
        XCTAssertFalse(
            NearbyMapSearchPolicy.contains(
                CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016),
                in: daNangRegion
            )
        )
    }

    func testVisibleRegionHandlesInternationalDateLine() {
        let dateLineRegion = region(
            latitude: -17.7134,
            longitude: 179.98,
            latitudeDelta: 0.2,
            longitudeDelta: 0.2
        )

        XCTAssertTrue(
            NearbyMapSearchPolicy.contains(
                CLLocationCoordinate2D(latitude: -17.72, longitude: -179.98),
                in: dateLineRegion
            )
        )
    }

    private func makeResult(
        name: String,
        address: String = "東京都",
        latitude: Double = 35.6580,
        longitude: Double = 139.7016
    ) -> StoreSearchResult {
        StoreSearchResult(
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude
        )
    }

    private func region(
        latitude: Double,
        longitude: Double,
        latitudeDelta: Double,
        longitudeDelta: Double
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }
}
