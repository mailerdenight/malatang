import Foundation
import SwiftData

/// 具材・麺・スープのマスター投入と、自由追加・非表示・改名の窓口。
enum MasterService {

    // MARK: - 初期投入

    /// 空のストアにだけ初期マスターを入れる。既存データがある場合は何もしない。
    static func seedIfNeeded(_ context: ModelContext) {
        seedIngredientsIfNeeded(context)
        seedNoodlesIfNeeded(context)
        seedSoupsIfNeeded(context)
        try? context.save()
    }

    private static func seedIngredientsIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        guard existing.isEmpty else { return }
        var order = 0
        for (category, seeds) in SeedMaster.ingredients {
            for seed in seeds {
                let item = Ingredient(
                    name: seed.name,
                    reading: seed.reading,
                    aliases: seed.aliases,
                    category: category,
                    isCustom: false,
                    sortOrder: order
                )
                order += 1
                context.insert(item)
            }
        }
    }

    private static func seedNoodlesIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Noodle>())) ?? []
        guard existing.isEmpty else { return }
        for (index, seed) in SeedMaster.noodles.enumerated() {
            context.insert(
                Noodle(
                    name: seed.name,
                    reading: seed.reading,
                    aliases: seed.aliases,
                    isCustom: false,
                    sortOrder: index
                )
            )
        }
    }

    private static func seedSoupsIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Soup>())) ?? []
        guard existing.isEmpty else { return }
        for (index, seed) in SeedMaster.soups.enumerated() {
            context.insert(
                Soup(
                    name: seed.name,
                    reading: seed.reading,
                    aliases: seed.aliases,
                    isCustom: false,
                    sortOrder: index
                )
            )
        }
    }

    // MARK: - 自由追加（重複防止つき）

    enum AddResult<T> {
        /// 新規に作成した
        case created(T)
        /// 同名（または別名一致）の既存項目が見つかったので、それを返した
        case existing(T)
    }

    static func addIngredient(
        named rawName: String,
        category: IngredientCategory,
        in context: ModelContext
    ) -> AddResult<Ingredient>? {
        let name = normalize(rawName)
        guard name.isEmpty == false else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        if let hit = all.first(where: { isSameName($0.name, name) || $0.aliases.contains(where: { isSameName($0, name) }) }) {
            // 非表示だった場合は候補に戻す
            if hit.isHidden { hit.isHidden = false }
            return .existing(hit)
        }
        let maxOrder = all.map(\.sortOrder).max() ?? 0
        let item = Ingredient(
            name: name,
            reading: "",
            aliases: [],
            category: category,
            isCustom: true,
            sortOrder: maxOrder + 1
        )
        context.insert(item)
        return .created(item)
    }

    static func addNoodle(named rawName: String, in context: ModelContext) -> AddResult<Noodle>? {
        let name = normalize(rawName)
        guard name.isEmpty == false else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Noodle>())) ?? []
        if let hit = all.first(where: { isSameName($0.name, name) || $0.aliases.contains(where: { isSameName($0, name) }) }) {
            if hit.isHidden { hit.isHidden = false }
            return .existing(hit)
        }
        let item = Noodle(name: name, isCustom: true, sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(item)
        return .created(item)
    }

    static func addSoup(named rawName: String, in context: ModelContext) -> AddResult<Soup>? {
        let name = normalize(rawName)
        guard name.isEmpty == false else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Soup>())) ?? []
        if let hit = all.first(where: { isSameName($0.name, name) || $0.aliases.contains(where: { isSameName($0, name) }) }) {
            if hit.isHidden { hit.isHidden = false }
            return .existing(hit)
        }
        let item = Soup(name: name, isCustom: true, sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(item)
        return .created(item)
    }

    // MARK: - 非表示・改名

    /// 物理削除はしない。過去記録の参照整合性を守るため常に非表示で処理する。
    static func hide(_ ingredient: Ingredient) {
        ingredient.isHidden = true
        ingredient.isPinned = false
        ingredient.pinnedAt = nil
    }

    static func unhide(_ ingredient: Ingredient) {
        ingredient.isHidden = false
    }

    /// ユーザー追加項目のみ改名可。IDは維持されるので過去記録にも新しい表示名が反映される。
    @discardableResult
    static func rename(_ ingredient: Ingredient, to rawName: String) -> Bool {
        guard ingredient.isCustom else { return false }
        let name = normalize(rawName)
        guard name.isEmpty == false else { return false }
        ingredient.name = name
        return true
    }

    static func togglePin(_ ingredient: Ingredient) {
        ingredient.isPinned.toggle()
        ingredient.pinnedAt = ingredient.isPinned ? Date() : nil
    }

    // MARK: - 店舗

    /// 同名・同支店の店舗があれば再利用する。
    static func findOrCreateStore(
        name rawName: String,
        branch: String = "",
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        in context: ModelContext
    ) -> Store? {
        let name = normalize(rawName)
        guard name.isEmpty == false else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Store>())) ?? []
        if let hit = all.first(where: { isSameName($0.name, name) && isSameName($0.branch, branch) }) {
            // 座標・住所は後から取得できたときだけ補完する（既存値は消さない）
            if hit.address.isEmpty, address.isEmpty == false { hit.address = address }
            if hit.latitude == nil, let latitude { hit.latitude = latitude }
            if hit.longitude == nil, let longitude { hit.longitude = longitude }
            return hit
        }
        let store = Store(
            name: name,
            branch: normalize(branch),
            address: address,
            latitude: latitude,
            longitude: longitude
        )
        context.insert(store)
        return store
    }

    // MARK: - 正規化

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{3000}", with: " ")
    }

    static func isSameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
