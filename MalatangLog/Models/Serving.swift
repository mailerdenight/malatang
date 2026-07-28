import Foundation
import SwiftData

/// 一杯の記録。アプリの中心となるモデル。
@Model
final class Serving {
    /// バックアップの突合に使う不変ID。永続IDとは別に保持する。
    var uuid: UUID = UUID()
    var date: Date = Date()
    /// PhotoStore が管理するファイルID。写真なしは nil。
    var photoID: String?

    /// 0〜5
    var spiceLevel: Int = 0
    /// 0〜5。辛さとは独立。
    var numbnessLevel: Int = 0
    /// 店舗独自の辛さ表記（例: 中辛、3辣）。任意。
    var spiceNote: String = ""

    /// 税込合計。未入力は nil。
    var priceYen: Int?
    /// 具材の合計g。未入力は nil。
    var totalWeightGrams: Int?
    /// 100gあたり単価。未入力は nil。
    var pricePer100gYen: Int?
    /// スープ追加料金。未入力は nil。
    var soupSurchargeYen: Int?

    /// 1〜5。0は未評価。
    var rating: Int = 0
    var memo: String = ""

    /// いつもの一杯（手動指定）
    var isUsual: Bool = false
    var usualMarkedAt: Date?
    /// 殿堂入り（手動指定）
    var isHallOfFame: Bool = false
    var hallOfFameMarkedAt: Date?

    // 味の詳細（0 = 未設定、1〜5）
    var richness: Int = 0
    var oiliness: Int = 0
    var sesameNote: Int = 0
    var herbalNote: Int = 0
    var sourness: Int = 0
    var garlic: Int = 0
    var cilantro: Int = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var store: Store?
    var soup: Soup?
    var noodles: [Noodle] = []
    var ingredients: [Ingredient] = []

    init(
        uuid: UUID = UUID(),
        date: Date = Date(),
        photoID: String? = nil,
        spiceLevel: Int = 0,
        numbnessLevel: Int = 0,
        spiceNote: String = "",
        priceYen: Int? = nil,
        totalWeightGrams: Int? = nil,
        pricePer100gYen: Int? = nil,
        soupSurchargeYen: Int? = nil,
        rating: Int = 0,
        memo: String = "",
        store: Store? = nil,
        soup: Soup? = nil,
        noodles: [Noodle] = [],
        ingredients: [Ingredient] = []
    ) {
        self.uuid = uuid
        self.date = date
        self.photoID = photoID
        self.spiceLevel = spiceLevel
        self.numbnessLevel = numbnessLevel
        self.spiceNote = spiceNote
        self.priceYen = priceYen
        self.totalWeightGrams = totalWeightGrams
        self.pricePer100gYen = pricePer100gYen
        self.soupSurchargeYen = soupSurchargeYen
        self.rating = rating
        self.memo = memo
        self.store = store
        self.soup = soup
        self.noodles = noodles
        self.ingredients = ingredients
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension Serving {
    /// 注文メモに出す一行サマリー。
    var orderSummary: String {
        var parts: [String] = []
        if let soup { parts.append(soup.name) }
        parts.append("辛さ\(spiceLevel)・痺れ\(numbnessLevel)")
        if noodles.isEmpty == false {
            parts.append(noodles.map(\.name).joined(separator: "＋"))
        }
        if ingredients.isEmpty == false {
            parts.append(ingredients.map(\.name).joined(separator: "、"))
        }
        return parts.joined(separator: " / ")
    }

    var storeDisplayName: String {
        guard let store else { return "店舗未設定" }
        return store.displayName
    }

    /// 「この一杯をもう一度」用の複製。日時のみ現在に更新し、元データには一切触れない。
    func duplicatedForToday() -> Serving {
        let copy = Serving(
            uuid: UUID(),
            date: Date(),
            photoID: nil,                 // 写真は引き継がない（今日の一杯は今日撮る）
            spiceLevel: spiceLevel,
            numbnessLevel: numbnessLevel,
            spiceNote: spiceNote,
            priceYen: priceYen,
            totalWeightGrams: totalWeightGrams,
            pricePer100gYen: pricePer100gYen,
            soupSurchargeYen: soupSurchargeYen,
            rating: 0,                    // 評価は引き継がない
            memo: "",
            store: store,
            soup: soup,
            noodles: noodles,
            ingredients: ingredients
        )
        copy.richness = richness
        copy.oiliness = oiliness
        copy.sesameNote = sesameNote
        copy.herbalNote = herbalNote
        copy.sourness = sourness
        copy.garlic = garlic
        copy.cilantro = cilantro
        return copy
    }
}
