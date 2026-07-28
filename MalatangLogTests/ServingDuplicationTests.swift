import XCTest
import SwiftData
@testable import MalatangLog

final class ServingDuplicationTests: XCTestCase {

    func testDuplicateDoesNotMutateOriginal() throws {
        let soup = Soup(name: "麻辣スープ")
        let noodle = Noodle(name: "春雨")
        let ingredient = Ingredient(name: "白菜", category: .leafy)
        let store = Store(name: "テスト店")

        let original = Serving(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            spiceLevel: 3,
            numbnessLevel: 2,
            priceYen: 1_180,
            rating: 5,
            memo: "最高だった",
            store: store,
            soup: soup,
            noodles: [noodle],
            ingredients: [ingredient]
        )
        original.photoID = "photo-1"
        original.isHallOfFame = true

        let copy = original.duplicatedForToday()

        XCTAssertNotEqual(copy.uuid, original.uuid, "複製は別IDになる")
        XCTAssertEqual(original.date, Date(timeIntervalSince1970: 1_700_000_000), "元の日時は変わらない")
        XCTAssertEqual(original.rating, 5, "元の評価は変わらない")
        XCTAssertEqual(original.memo, "最高だった")
        XCTAssertEqual(original.photoID, "photo-1")
        XCTAssertTrue(original.isHallOfFame)

        XCTAssertEqual(copy.spiceLevel, 3)
        XCTAssertEqual(copy.numbnessLevel, 2)
        XCTAssertEqual(copy.soup?.name, "麻辣スープ")
        XCTAssertEqual(copy.noodles.map(\.name), ["春雨"])
        XCTAssertEqual(copy.ingredients.map(\.name), ["白菜"])
        XCTAssertEqual(copy.store?.name, "テスト店")
        XCTAssertNil(copy.photoID, "写真は引き継がない")
        XCTAssertEqual(copy.rating, 0, "評価はリセット")
        XCTAssertEqual(copy.memo, "")
        XCTAssertFalse(copy.isHallOfFame, "殿堂入りは引き継がない")
        XCTAssertTrue(abs(copy.date.timeIntervalSinceNow) < 5, "日時は現在に更新される")
    }

    func testDraftValidation() {
        let draft = ServingDraft()
        draft.didAttemptSave = true
        XCTAssertFalse(draft.isValid)
        XCTAssertNotNil(draft.soupError)
        XCTAssertNotNil(draft.noodleError)

        draft.soup = Soup(name: "白湯")
        draft.noodles = [Noodle(name: "麺なし")]
        XCTAssertTrue(draft.isValid)
        XCTAssertNil(draft.soupError)
        XCTAssertNil(draft.noodleError)

        draft.priceText = "100000"
        XCTAssertNotNil(draft.priceError)
        XCTAssertFalse(draft.isValid)

        draft.priceText = "1180"
        XCTAssertNil(draft.priceError)

        draft.memo = String(repeating: "あ", count: 1_001)
        XCTAssertNotNil(draft.memoError)
        XCTAssertFalse(draft.isValid)
    }
}
