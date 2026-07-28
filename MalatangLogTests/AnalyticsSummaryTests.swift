import XCTest
@testable import MalatangLog

final class AnalyticsSummaryTests: XCTestCase {

    func testSummaryComputesBasics() {
        let hakusai = Ingredient(name: "白菜", category: .leafy)
        let enoki = Ingredient(name: "えのき", category: .mushroom)
        let harusame = Noodle(name: "春雨")
        let malatang = Soup(name: "麻辣スープ")

        let servings = [
            Serving(spiceLevel: 3, numbnessLevel: 2, priceYen: 1_000, soup: malatang, noodles: [harusame], ingredients: [hakusai, enoki]),
            Serving(spiceLevel: 3, numbnessLevel: 1, priceYen: 1_400, soup: malatang, noodles: [harusame], ingredients: [hakusai]),
            Serving(spiceLevel: 5, numbnessLevel: 5, soup: malatang, noodles: [harusame], ingredients: [hakusai])
        ]

        let summary = AnalyticsSummary(servings: servings, storeCount: 2)
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.storeCount, 2)
        XCTAssertEqual(summary.averagePrice, 1_200, "価格未入力の記録は平均から除く")
        XCTAssertEqual(summary.topIngredients.first?.name, "白菜")
        XCTAssertEqual(summary.topIngredients.first?.count, 3)
        XCTAssertEqual(summary.noodleCounts.first?.count, 3)
        XCTAssertEqual(summary.soupCounts.first?.name, "麻辣スープ")
        XCTAssertEqual(summary.spiceDistribution[3], 2)
        XCTAssertEqual(summary.spiceDistribution[5], 1)
        XCTAssertEqual(summary.numbnessDistribution[1], 1)
        XCTAssertEqual(summary.spiceDistribution.count, 6)
    }

    func testEmptyInputIsSafe() {
        let summary = AnalyticsSummary(servings: [], storeCount: 0)
        XCTAssertEqual(summary.totalCount, 0)
        XCTAssertNil(summary.averagePrice)
        XCTAssertTrue(summary.topIngredients.isEmpty)
        XCTAssertEqual(summary.spiceDistribution, [0, 0, 0, 0, 0, 0])
    }
}
