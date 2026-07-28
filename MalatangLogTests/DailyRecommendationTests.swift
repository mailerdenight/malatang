import XCTest
@testable import MalatangLog

final class DailyRecommendationTests: XCTestCase {

    func testEmptyHistoryPromptsFirstRecord() {
        let recommendation = DailyRecommendation.make(
            servings: [],
            stores: [],
            noodles: [],
            favoriteStoreIDs: []
        )
        XCTAssertTrue(recommendation.message.contains("最初の一杯"))
    }

    func testFavoriteStoreIsRecommendedFirst() {
        let store = Store(name: "七宝麻辣湯")
        let serving = Serving(
            date: Date(timeIntervalSinceNow: -20 * 24 * 60 * 60),
            rating: 5,
            store: store
        )
        store.servings = [serving]

        let recommendation = DailyRecommendation.make(
            servings: [serving],
            stores: [store],
            noodles: [],
            favoriteStoreIDs: [store.uuid]
        )

        XCTAssertTrue(recommendation.message.contains("七宝麻辣湯"))
        XCTAssertTrue(recommendation.reason.contains("お気に入り"))
    }
}
