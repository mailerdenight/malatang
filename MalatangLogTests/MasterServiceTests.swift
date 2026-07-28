import XCTest
import SwiftData
@testable import MalatangLog

final class MasterServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try AppModelContainer.make(inMemory: true)
        return ModelContext(container)
    }

    func testSeedInsertsMastersOnce() throws {
        let context = try makeContext()
        MasterService.seedIfNeeded(context)

        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        let noodles = try context.fetch(FetchDescriptor<Noodle>())
        let soups = try context.fetch(FetchDescriptor<Soup>())

        XCTAssertGreaterThanOrEqual(ingredients.count, 120, "仕様の120〜160件を満たす")
        XCTAssertLessThanOrEqual(ingredients.count, 160)
        XCTAssertGreaterThanOrEqual(noodles.count, 15)
        XCTAssertGreaterThanOrEqual(soups.count, 10)

        // 2回目は増えない
        MasterService.seedIfNeeded(context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Ingredient>()).count, ingredients.count)
    }

    func testSeedNamesAreUnique() throws {
        let context = try makeContext()
        MasterService.seedIfNeeded(context)
        let names = try context.fetch(FetchDescriptor<Ingredient>()).map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "初期マスターに同名の重複がない")
    }

    func testAddingExistingNameReturnsExisting() throws {
        let context = try makeContext()
        MasterService.seedIfNeeded(context)

        let result = MasterService.addIngredient(named: "白菜", category: .custom, in: context)
        guard case .existing(let ingredient)? = result else {
            return XCTFail("既存候補が返るはず")
        }
        XCTAssertEqual(ingredient.name, "白菜")
        XCTAssertFalse(ingredient.isCustom)
    }

    func testAddingAliasReturnsExisting() throws {
        let context = try makeContext()
        MasterService.seedIfNeeded(context)

        // 「木耳」は「きくらげ」の別名
        let result = MasterService.addIngredient(named: "木耳", category: .custom, in: context)
        guard case .existing(let ingredient)? = result else {
            return XCTFail("別名一致で既存候補が返るはず")
        }
        XCTAssertEqual(ingredient.name, "きくらげ")
    }

    func testAddingNewNameCreates() throws {
        let context = try makeContext()
        MasterService.seedIfNeeded(context)

        let result = MasterService.addIngredient(named: "テスト具材", category: .custom, in: context)
        guard case .created(let ingredient)? = result else {
            return XCTFail("新規作成されるはず")
        }
        XCTAssertTrue(ingredient.isCustom)
        XCTAssertEqual(ingredient.category, .custom)
    }

    func testRenameKeepsIdentityAndReflectsInServing() throws {
        let context = try makeContext()
        guard case .created(let ingredient)? = MasterService.addIngredient(named: "旧名", category: .custom, in: context) else {
            return XCTFail("作成失敗")
        }
        let originalUUID = ingredient.uuid
        let serving = Serving(ingredients: [ingredient])
        context.insert(serving)
        try context.save()

        XCTAssertTrue(MasterService.rename(ingredient, to: "新名"))
        XCTAssertEqual(ingredient.uuid, originalUUID, "IDは維持される")
        XCTAssertEqual(serving.ingredients.first?.name, "新名", "過去記録にも新表示名が反映される")
    }

    func testHiddenIngredientStillVisibleInPastServing() throws {
        let context = try makeContext()
        MasterService.seedIfNeeded(context)
        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        guard let target = ingredients.first else { return XCTFail("マスターがない") }

        let serving = Serving(ingredients: [target])
        context.insert(serving)
        try context.save()

        MasterService.hide(target)
        try context.save()

        XCTAssertTrue(target.isHidden)
        XCTAssertEqual(serving.ingredients.first?.name, target.name, "非表示にしても過去記録は壊れない")
    }

    func testFindOrCreateStoreReusesSameName() throws {
        let context = try makeContext()
        let first = MasterService.findOrCreateStore(name: "張亮麻辣湯", branch: "新宿店", in: context)
        let second = MasterService.findOrCreateStore(name: "張亮麻辣湯", branch: "新宿店", address: "東京都新宿区", in: context)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.uuid, second?.uuid, "同名同支店は再利用する")
        XCTAssertEqual(second?.address, "東京都新宿区", "住所は後から補完される")
    }
}
