import Foundation
import SwiftData
import UIKit

enum SampleDataService {
    static let sampleServingUUID = UUID(uuidString: "32E361C9-60F1-47BB-83C5-933AB3625CA3")!
    static let sampleLatitude = 35.681236
    static let sampleLongitude = 139.767125
    static let sampleAddress = "東京都千代田区丸の内1丁目 東京駅"
    private static let didSeedKey = "didSeedLegendaryBowlV11"

    static func isSample(_ serving: Serving) -> Bool {
        serving.uuid == sampleServingUUID
    }

    /// v1.1を初めて開いたときだけサンプルを追加する。削除後は再生成しない。
    static func seedIfNeeded(_ context: ModelContext) {
        updateExistingSampleLocation(in: context)
        guard UserDefaults.standard.bool(forKey: didSeedKey) == false else { return }

        let existing = (try? context.fetch(FetchDescriptor<Serving>())) ?? []
        if existing.contains(where: isSample) {
            UserDefaults.standard.set(true, forKey: didSeedKey)
            return
        }

        let store = MasterService.findOrCreateStore(name: "Legendary Bowl", in: context)
        store?.address = sampleAddress
        store?.latitude = sampleLatitude
        store?.longitude = sampleLongitude
        let soups = (try? context.fetch(FetchDescriptor<Soup>())) ?? []
        let soup = soups.first { $0.name == "麻辣スープ" } ?? soups.first
        let noodle = addedNoodle(named: "龍口春雨", context: context)

        let requestedIngredients: [(name: String, lookup: String, category: IngredientCategory)] = [
            ("ラム肉", "ラム肉", .meat),
            ("牛肉", "牛肉", .meat),
            ("サーカス団子", "サーカス団子", .ball),
            ("キクラゲ", "きくらげ", .mushroom),
            ("白キクラゲ", "白きくらげ", .mushroom),
            ("湯葉", "湯葉", .soy),
            ("豆腐皮", "豆腐皮", .soy),
            ("エビ団子", "エビ団子", .ball),
            ("うずら卵", "うずら卵", .eggDairy),
            ("レンコン", "レンコン", .root),
            ("えのき", "えのき", .mushroom),
            ("チンゲンサイ", "チンゲン菜", .leafy),
            ("小松菜", "小松菜", .leafy),
            ("ブロッコリー", "ブロッコリー", .root),
            ("じゃがいも", "じゃがいも", .root)
        ]
        let ingredients = requestedIngredients.compactMap {
            addedIngredient(named: $0.lookup, category: $0.category, context: context)
        }

        let photoID = UIImage(named: "LegendaryBowl").flatMap(PhotoStore.shared.save)
        let sample = Serving(
            uuid: sampleServingUUID,
            date: Date(),
            photoID: photoID,
            spiceLevel: 4,
            numbnessLevel: 3,
            spiceNote: "辛さ4",
            priceYen: 1_780,
            rating: 5,
            memo: "世界一食べたくなる麻辣湯",
            store: store,
            soup: soup,
            noodles: noodle.map { [$0] } ?? [],
            ingredients: ingredients
        )
        sample.isHallOfFame = true
        sample.hallOfFameMarkedAt = Date()
        context.insert(sample)

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: didSeedKey)
        } catch {
            PhotoStore.shared.delete(photoID)
        }
    }

    /// 旧バージョンで作成済みのサンプルも、曖昧な店名検索ではなく東京駅を指すようにする。
    private static func updateExistingSampleLocation(in context: ModelContext) {
        let servings = (try? context.fetch(FetchDescriptor<Serving>())) ?? []
        guard let store = servings.first(where: isSample)?.store else { return }

        let needsUpdate = store.address != sampleAddress
            || store.latitude != sampleLatitude
            || store.longitude != sampleLongitude
        guard needsUpdate else { return }

        store.address = sampleAddress
        store.latitude = sampleLatitude
        store.longitude = sampleLongitude
        try? context.save()
    }

    private static func addedNoodle(named name: String, context: ModelContext) -> Noodle? {
        guard let result = MasterService.addNoodle(named: name, in: context) else { return nil }
        switch result {
        case .created(let item), .existing(let item): return item
        }
    }

    private static func addedIngredient(
        named name: String,
        category: IngredientCategory,
        context: ModelContext
    ) -> Ingredient? {
        guard let result = MasterService.addIngredient(named: name, category: category, in: context) else {
            return nil
        }
        switch result {
        case .created(let item), .existing(let item): return item
        }
    }
}
