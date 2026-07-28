import XCTest
import SwiftData
@testable import MalatangLog

final class FrequentIngredientsTests: XCTestCase {

    private func makeIngredients(_ names: [String]) -> [Ingredient] {
        names.enumerated().map { index, name in
            Ingredient(name: name, category: .other, sortOrder: index)
        }
    }

    private func makeServing(date: Date, ingredients: [Ingredient]) -> Serving {
        Serving(date: date, ingredients: ingredients)
    }

    func testStarterListUsedWhenNoServings() {
        let ingredients = makeIngredients(["白菜", "えのき", "きくらげ", "豆腐", "牛肉", "えび", "チンゲン菜", "じゃがいも", "その他"])
        let result = FrequentIngredients.ordered(allIngredients: ingredients, servings: [])
        XCTAssertEqual(result.count, 8)
        XCTAssertEqual(result.map(\.name), SeedMaster.starterFrequentNames)
    }

    func testPinnedAlwaysComesFirst() {
        let ingredients = makeIngredients(["白菜", "えのき", "きくらげ", "豆腐", "牛肉", "えび", "チンゲン菜", "じゃがいも", "オクラ"])
        let pinned = ingredients[8]
        pinned.isPinned = true
        pinned.pinnedAt = Date()

        // オクラは一度も使っていないが、固定しているので先頭に残る
        let servings = (0..<5).map { index in
            makeServing(date: Date().addingTimeInterval(TimeInterval(-index * 3600)), ingredients: [ingredients[0], ingredients[1]])
        }

        let result = FrequentIngredients.ordered(allIngredients: ingredients, servings: servings)
        XCTAssertEqual(result.first?.name, "オクラ")
        XCTAssertEqual(result.count, 8)
    }

    func testOrderedByRecentUsageCount() {
        let ingredients = makeIngredients(["A", "B", "C"])
        let now = Date()
        let servings = [
            makeServing(date: now, ingredients: [ingredients[0], ingredients[1]]),
            makeServing(date: now.addingTimeInterval(-3600), ingredients: [ingredients[0]]),
            makeServing(date: now.addingTimeInterval(-7200), ingredients: [ingredients[0], ingredients[2]])
        ]
        let result = FrequentIngredients.ordered(allIngredients: ingredients, servings: servings)
        XCTAssertEqual(result.first?.name, "A", "使用回数が最も多い具材が先頭に来る")
        // B と C は同数(1回)なので、最終使用が新しい B が先
        XCTAssertEqual(result[1].name, "B")
        XCTAssertEqual(result[2].name, "C")
    }

    func testOnlyRecent30ServingsCountForOrdering() {
        let ingredients = makeIngredients(["旧", "新"])
        let now = Date()
        // 直近30杯は「新」だけ
        var servings = (0..<30).map { index in
            makeServing(date: now.addingTimeInterval(TimeInterval(-index * 3600)), ingredients: [ingredients[1]])
        }
        // 31杯目以降に「旧」を大量に混ぜても、直近30杯の集計には入らない
        servings += (0..<20).map { index in
            makeServing(date: now.addingTimeInterval(TimeInterval(-(index + 100) * 3600)), ingredients: [ingredients[0]])
        }
        let result = FrequentIngredients.ordered(allIngredients: ingredients, servings: servings)
        XCTAssertEqual(result.first?.name, "新")
    }

    func testHiddenIngredientsAreExcluded() {
        let ingredients = makeIngredients(["A", "B"])
        ingredients[0].isHidden = true
        let servings = [makeServing(date: Date(), ingredients: [ingredients[0], ingredients[1]])]
        let result = FrequentIngredients.ordered(allIngredients: ingredients, servings: servings)
        XCTAssertFalse(result.contains { $0.name == "A" })
        XCTAssertTrue(result.contains { $0.name == "B" })
    }
}
