import Foundation

/// 「よく使う具材」の並び順を決める純粋ロジック。
/// 仕様: 固定 → 直近30杯の使用回数の多い順 → 同数なら最終使用日時の新しい順。
///       8件に満たない場合は累計使用回数で補完する。
enum FrequentIngredients {

    static let displayCount = 8
    static let recentServingWindow = 30

    /// - Parameters:
    ///   - allIngredients: 非表示を除いた候補全体
    ///   - servings: 全記録（日付降順でなくてよい）
    ///   - starterNames: 記録が0件のときに出す代表具材
    static func ordered(
        allIngredients: [Ingredient],
        servings: [Serving],
        starterNames: [String] = SeedMaster.starterFrequentNames,
        limit: Int = displayCount
    ) -> [Ingredient] {
        let visible = allIngredients.filter { $0.isHidden == false }

        let pinned = visible
            .filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }

        // 初回（記録なし）は代表具材で埋める
        if servings.isEmpty {
            let starters = starterNames.compactMap { name in
                visible.first { MasterService.isSameName($0.name, name) }
            }
            return dedupe(pinned + starters, limit: limit)
        }

        let recent = Array(servings.sorted { $0.date > $1.date }.prefix(recentServingWindow))

        var recentCount: [UUID: Int] = [:]
        var lastUsed: [UUID: Date] = [:]
        for serving in recent {
            for ingredient in serving.ingredients {
                recentCount[ingredient.uuid, default: 0] += 1
                let current = lastUsed[ingredient.uuid] ?? .distantPast
                if serving.date > current { lastUsed[ingredient.uuid] = serving.date }
            }
        }

        var totalCount: [UUID: Int] = [:]
        for serving in servings {
            for ingredient in serving.ingredients {
                totalCount[ingredient.uuid, default: 0] += 1
                let current = lastUsed[ingredient.uuid] ?? .distantPast
                if serving.date > current { lastUsed[ingredient.uuid] = serving.date }
            }
        }

        let byRecent = visible
            .filter { (recentCount[$0.uuid] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let l = recentCount[lhs.uuid] ?? 0
                let r = recentCount[rhs.uuid] ?? 0
                if l != r { return l > r }
                let ld = lastUsed[lhs.uuid] ?? .distantPast
                let rd = lastUsed[rhs.uuid] ?? .distantPast
                if ld != rd { return ld > rd }
                return lhs.sortOrder < rhs.sortOrder
            }

        var result = dedupe(pinned + byRecent, limit: limit)
        guard result.count < limit else { return result }

        // 累計での補完
        let byTotal = visible
            .filter { (totalCount[$0.uuid] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let l = totalCount[lhs.uuid] ?? 0
                let r = totalCount[rhs.uuid] ?? 0
                if l != r { return l > r }
                return (lastUsed[lhs.uuid] ?? .distantPast) > (lastUsed[rhs.uuid] ?? .distantPast)
            }
        result = dedupe(result + byTotal, limit: limit)
        guard result.count < limit else { return result }

        // それでも足りなければ代表具材で埋める
        let starters = starterNames.compactMap { name in
            visible.first { MasterService.isSameName($0.name, name) }
        }
        return dedupe(result + starters, limit: limit)
    }

    private static func dedupe(_ items: [Ingredient], limit: Int) -> [Ingredient] {
        var seen = Set<UUID>()
        var out: [Ingredient] = []
        for item in items where seen.contains(item.uuid) == false {
            seen.insert(item.uuid)
            out.append(item)
            if out.count >= limit { break }
        }
        return out
    }

    /// 最近使った麺（記録がなければ登録順の先頭）
    static func recentNoodles(
        allNoodles: [Noodle],
        servings: [Serving],
        limit: Int = 6
    ) -> [Noodle] {
        let visible = allNoodles.filter { $0.isHidden == false }
        guard servings.isEmpty == false else {
            return Array(visible.sorted { $0.sortOrder < $1.sortOrder }.prefix(limit))
        }
        var lastUsed: [UUID: Date] = [:]
        var count: [UUID: Int] = [:]
        for serving in servings {
            for noodle in serving.noodles {
                count[noodle.uuid, default: 0] += 1
                let current = lastUsed[noodle.uuid] ?? .distantPast
                if serving.date > current { lastUsed[noodle.uuid] = serving.date }
            }
        }
        let used = visible
            .filter { (count[$0.uuid] ?? 0) > 0 }
            .sorted { (lastUsed[$0.uuid] ?? .distantPast) > (lastUsed[$1.uuid] ?? .distantPast) }
        let rest = visible
            .filter { (count[$0.uuid] ?? 0) == 0 }
            .sorted { $0.sortOrder < $1.sortOrder }
        return Array((used + rest).prefix(limit))
    }
}
