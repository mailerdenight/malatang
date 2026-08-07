import Foundation
import SwiftData

/// 具材カテゴリ。麺・主食は Noodle として独立させている。
enum IngredientCategory: String, CaseIterable, Codable, Identifiable {
    case meat = "肉類"
    case seafood = "海鮮"
    case leafy = "葉物野菜"
    case root = "根菜・その他野菜"
    case mushroom = "きのこ"
    case soy = "豆腐・大豆製品"
    case ball = "練り物・団子"
    case eggDairy = "卵・乳製品"
    case other = "餃子・餅・その他"
    case custom = "自分で追加"

    var id: String { rawValue }
    var displayName: String { AppLocalization.string(rawValue) }
}

@Model
final class Ingredient {
    var uuid: UUID = UUID()
    var name: String = ""
    /// ひらがな読み。検索用。
    var reading: String = ""
    /// 中国語名・言い換えなど。検索用。
    var aliases: [String] = []
    var categoryRaw: String = IngredientCategory.other.rawValue
    /// ユーザーが自由追加した項目
    var isCustom: Bool = false
    /// 候補一覧から隠す（過去記録との参照整合性を守るため物理削除はしない）
    var isHidden: Bool = false
    /// 「よく使う具材」の先頭に固定
    var isPinned: Bool = false
    var pinnedAt: Date?
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(inverse: \Serving.ingredients)
    var servings: [Serving] = []

    init(
        uuid: UUID = UUID(),
        name: String,
        reading: String = "",
        aliases: [String] = [],
        category: IngredientCategory = .other,
        isCustom: Bool = false,
        sortOrder: Int = 0
    ) {
        self.uuid = uuid
        self.name = name
        self.reading = reading
        self.aliases = aliases
        self.categoryRaw = category.rawValue
        self.isCustom = isCustom
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

extension Ingredient {
    var localizedDisplayName: String {
        AppLocalization.masterName(name, isCustom: isCustom)
    }

    var category: IngredientCategory {
        get { IngredientCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// 検索対象文字列（表示名・読み・別名）
    var searchHaystack: String {
        ([name, localizedDisplayName, reading] + aliases).joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.isEmpty == false else { return true }
        return searchHaystack.localizedCaseInsensitiveContains(q)
    }
}
