import Foundation
import SwiftData
import UIKit

/// 入力中の下書き。保存するまでモデルには一切触れないので、キャンセルで記録が汚れない。
@Observable
final class ServingDraft {

    var date: Date = Date()
    var newPhoto: UIImage?
    /// 既存記録を編集するときの現在の写真ID
    var existingPhotoID: String?
    var removePhoto = false

    var store: Store?
    var soup: Soup?
    var spiceLevel: Int = 0
    var numbnessLevel: Int = 0
    var spiceNote: String = ""
    var noodles: [Noodle] = []
    var ingredients: [Ingredient] = []

    var priceText: String = ""
    var weightText: String = ""
    var pricePer100gText: String = ""
    var soupSurchargeText: String = ""
    var rating: Int = 0
    var memo: String = ""

    var richness: Int = 0
    var oiliness: Int = 0
    var sesameNote: Int = 0
    var herbalNote: Int = 0
    var sourness: Int = 0
    var garlic: Int = 0
    var cilantro: Int = 0

    /// 保存を試みたあとだけエラーを出す（初回表示でいきなり赤くしない）
    var didAttemptSave = false

    init() {}

    // MARK: - 既存記録から

    static func from(_ serving: Serving, resettingForToday: Bool) -> ServingDraft {
        let draft = ServingDraft()
        draft.date = resettingForToday ? Date() : serving.date
        draft.existingPhotoID = resettingForToday ? nil : serving.photoID
        draft.store = serving.store
        draft.soup = serving.soup
        draft.spiceLevel = serving.spiceLevel
        draft.numbnessLevel = serving.numbnessLevel
        draft.spiceNote = serving.spiceNote
        draft.noodles = serving.noodles
        draft.ingredients = serving.ingredients
        draft.priceText = serving.priceYen.map(String.init) ?? ""
        draft.weightText = serving.totalWeightGrams.map(String.init) ?? ""
        draft.pricePer100gText = serving.pricePer100gYen.map(String.init) ?? ""
        draft.soupSurchargeText = serving.soupSurchargeYen.map(String.init) ?? ""
        draft.rating = resettingForToday ? 0 : serving.rating
        draft.memo = resettingForToday ? "" : serving.memo
        draft.richness = serving.richness
        draft.oiliness = serving.oiliness
        draft.sesameNote = serving.sesameNote
        draft.herbalNote = serving.herbalNote
        draft.sourness = serving.sourness
        draft.garlic = serving.garlic
        draft.cilantro = serving.cilantro
        return draft
    }

    // MARK: - 検証

    var soupError: String? {
        guard didAttemptSave, soup == nil else { return nil }
        return "スープを選んでください。"
    }

    var noodleError: String? {
        guard didAttemptSave, noodles.isEmpty else { return nil }
        return "麺を選んでください。麺を入れていないときは「麺なし」を選びます。"
    }

    var priceError: String? {
        guard priceText.isEmpty == false else { return nil }
        guard let value = Int(priceText) else { return "価格は数字で入力してください。" }
        guard (0...99_999).contains(value) else { return "価格は0〜99,999円の範囲で入力してください。" }
        return nil
    }

    var memoError: String? {
        memo.count > 1_000 ? "メモは1,000文字以内で入力してください。（現在\(memo.count)文字）" : nil
    }

    var isValid: Bool {
        soup != nil && noodles.isEmpty == false && priceError == nil && memoError == nil
    }

    // MARK: - 数値

    private func intValue(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else { return nil }
        return Int(trimmed)
    }

    // MARK: - 反映

    /// 新規作成。写真の保存に失敗しても、写真なしの記録として保存を続ける。
    func makeServing() -> Serving {
        let serving = Serving(date: date)
        apply(to: serving)
        return serving
    }

    func apply(to serving: Serving) {
        serving.date = date

        if removePhoto {
            PhotoStore.shared.delete(serving.photoID)
            serving.photoID = nil
        }
        if let newPhoto {
            let oldID = serving.photoID
            if let savedID = PhotoStore.shared.save(newPhoto) {
                serving.photoID = savedID
                if let oldID, oldID != savedID { PhotoStore.shared.delete(oldID) }
            }
            // 保存に失敗した場合は既存写真を維持し、記録自体は続行する
        } else if removePhoto == false, serving.photoID == nil, let existingPhotoID {
            serving.photoID = existingPhotoID
        }

        serving.store = store
        serving.soup = soup
        serving.spiceLevel = spiceLevel
        serving.numbnessLevel = numbnessLevel
        serving.spiceNote = spiceNote
        serving.noodles = noodles
        serving.ingredients = ingredients
        serving.priceYen = intValue(priceText)
        serving.totalWeightGrams = intValue(weightText)
        serving.pricePer100gYen = intValue(pricePer100gText)
        serving.soupSurchargeYen = intValue(soupSurchargeText)
        serving.rating = rating
        serving.memo = memo
        serving.richness = richness
        serving.oiliness = oiliness
        serving.sesameNote = sesameNote
        serving.herbalNote = herbalNote
        serving.sourness = sourness
        serving.garlic = garlic
        serving.cilantro = cilantro
        serving.updatedAt = Date()
    }
}
