import XCTest
import SwiftData
@testable import MalatangLog

final class CatalogSearchTests: XCTestCase {

    private func sampleServing() -> Serving {
        let store = Store(name: "楊国福麻辣湯", branch: "池袋店", address: "東京都豊島区")
        let soup = Soup(name: "麻辣スープ", aliases: ["麻辣湯"])
        let noodle = Noodle(name: "寛粉", reading: "かんふん", aliases: ["板春雨", "太春雨"])
        let ingredient = Ingredient(name: "きくらげ", reading: "きくらげ", aliases: ["木耳", "黒木耳"], category: .mushroom)
        let serving = Serving(
            spiceLevel: 3, numbnessLevel: 2, memo: "痺れ強め",
            store: store, soup: soup, noodles: [noodle], ingredients: [ingredient]
        )
        return serving
    }

    func testSearchMatchesStoreName() {
        XCTAssertTrue(CatalogSearch.matches(sampleServing(), query: "池袋"))
    }

    func testSearchMatchesIngredientName() {
        XCTAssertTrue(CatalogSearch.matches(sampleServing(), query: "きくらげ"))
    }

    func testSearchMatchesChineseAlias() {
        XCTAssertTrue(CatalogSearch.matches(sampleServing(), query: "木耳"), "中国語の別名でも見つかる")
    }

    func testSearchMatchesNoodleAlias() {
        XCTAssertTrue(CatalogSearch.matches(sampleServing(), query: "板春雨"))
    }

    func testSearchMatchesMemo() {
        XCTAssertTrue(CatalogSearch.matches(sampleServing(), query: "痺れ"))
    }

    func testSearchRejectsUnrelated() {
        XCTAssertFalse(CatalogSearch.matches(sampleServing(), query: "ラーメン二郎"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(CatalogSearch.matches(sampleServing(), query: "   "))
    }

    func testFilterByHallOfFame() {
        var filter = CatalogFilter()
        filter.hallOfFameOnly = true
        let serving = sampleServing()
        XCTAssertFalse(filter.matches(serving))
        serving.isHallOfFame = true
        XCTAssertTrue(filter.matches(serving))
    }

    func testFilterByMinimumSpice() {
        var filter = CatalogFilter()
        filter.minSpice = 4
        XCTAssertFalse(filter.matches(sampleServing()))
        filter.minSpice = 3
        XCTAssertTrue(filter.matches(sampleServing()))
    }

    func testFilterByRatingPriceAndFavoriteStore() {
        let serving = sampleServing()
        serving.rating = 4
        serving.priceYen = 1_780
        let storeID = serving.store!.uuid

        var filter = CatalogFilter()
        filter.minRating = 4
        filter.maximumPrice = 2_000
        filter.favoriteOnly = true

        XCTAssertTrue(filter.matches(serving, favoriteStoreIDs: [storeID]))
        XCTAssertFalse(filter.matches(serving, favoriteStoreIDs: []))

        filter.maximumPrice = 1_500
        XCTAssertFalse(filter.matches(serving, favoriteStoreIDs: [storeID]))
    }

    func testSortByPricePutsUnpricedLast() {
        let cheap = Serving(priceYen: 800)
        let expensive = Serving(priceYen: 1_500)
        let unknown = Serving()
        let sorted = CatalogSortOrder.price.apply(to: [unknown, expensive, cheap])
        XCTAssertEqual(sorted.map(\.priceYen), [800, 1_500, nil])
    }
}
