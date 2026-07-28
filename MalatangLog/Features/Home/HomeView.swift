import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Serving.date, order: .reverse) private var servings: [Serving]
    @Query private var stores: [Store]
    @Query(sort: \Noodle.sortOrder) private var noodles: [Noodle]

    @State private var favorites = FavoriteStoreService.shared
    var onNewRecord: () -> Void

    private var realServings: [Serving] {
        servings.filter { SampleDataService.isSample($0) == false }
    }

    private var hallOfFame: [Serving] {
        Array(
            servings
                .filter(\.isHallOfFame)
                .sorted { ($0.hallOfFameMarkedAt ?? $0.date) > ($1.hallOfFameMarkedAt ?? $1.date) }
                .prefix(5)
        )
    }

    private var recommendation: DailyRecommendation {
        DailyRecommendation.make(
            servings: realServings,
            stores: stores,
            noodles: noodles,
            favoriteStoreIDs: favorites.ids
        )
    }

    private var thisMonthServings: [Serving] {
        realServings.filter {
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
        }
    }

    private var monthlyAveragePrice: Int? {
        let prices = thisMonthServings.compactMap(\.priceYen)
        guard prices.isEmpty == false else { return nil }
        return prices.reduce(0, +) / prices.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hallOfFameCard
                    recommendationCard
                    newRecordButton
                    monthlySummaryCard
                }
                .padding(16)
            }
            .warmBackground()
            .navigationTitle("麻辣湯ログ")
            .navigationDestination(for: Serving.self) { serving in
                ServingDetailView(serving: serving)
            }
        }
    }

    private var hallOfFameCard: some View {
        SectionCard(title: "👑 殿堂入り", subtitle: "また食べたい、特別な一杯") {
            if hallOfFame.isEmpty {
                Text("記録の詳細から、お気に入りの一杯を殿堂入りにできます。")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtleText)
            } else {
                horizontalCards(hallOfFame)
            }
        }
    }

    private var recommendationCard: some View {
        SectionCard(title: "⭐ 今日のおすすめ") {
            VStack(alignment: .leading, spacing: 8) {
                Text(recommendation.message)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recommendation.reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.subtleText)
            }
        }
    }

    private var newRecordButton: some View {
        Button(action: onNewRecord) {
            Label("新しい一杯を記録", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.primary)
        .accessibilityHint("記録画面を開きます")
    }

    private var monthlySummaryCard: some View {
        SectionCard(title: "今月の記録") {
            HStack(spacing: 12) {
                monthlyMetric(
                    title: "今月",
                    value: "\(thisMonthServings.count)",
                    unit: "杯"
                )
                Divider()
                monthlyMetric(
                    title: "平均価格",
                    value: monthlyAveragePrice.map { "¥\($0.formatted())" } ?? "—",
                    unit: ""
                )
            }
            .frame(minHeight: 72)
        }
    }

    private func monthlyMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.subtleText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                if unit.isEmpty == false {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func horizontalCards(_ items: [Serving]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items, id: \.uuid) { serving in
                    NavigationLink(value: serving) {
                        ServingHighlightCard(serving: serving)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

struct DailyRecommendation {
    let message: String
    let reason: String

    static func make(
        servings: [Serving],
        stores: [Store],
        noodles: [Noodle],
        favoriteStoreIDs: Set<UUID>,
        now: Date = Date()
    ) -> DailyRecommendation {
        guard servings.isEmpty == false else {
            return DailyRecommendation(
                message: "最初の一杯を記録してみよう",
                reason: "記録が増えると、好みに合わせておすすめします。"
            )
        }

        let visitedStores = stores.filter {
            $0.servings.contains { SampleDataService.isSample($0) == false }
        }
        let favoriteStores = visitedStores.filter { favoriteStoreIDs.contains($0.uuid) }
        if let favorite = oldestVisitedStore(in: favoriteStores) {
            return DailyRecommendation(
                message: "今日は久しぶりに\n\(favorite.displayName)はどう？",
                reason: "お気に入り店舗の中から、最近行っていないお店を選びました。"
            )
        }

        if visitedStores.count >= 2,
           let oldest = oldestVisitedStore(in: visitedStores),
           let lastVisit = realLastVisit(of: oldest),
           now.timeIntervalSince(lastVisit) >= 7 * 24 * 60 * 60 {
            return DailyRecommendation(
                message: "今日は久しぶりに\n\(oldest.displayName)はどう？",
                reason: "最近行っていない店舗からおすすめしています。"
            )
        }

        let recentlyUsedNoodleIDs = Set(servings.prefix(5).flatMap { $0.noodles.map(\.uuid) })
        let previouslyUsed = noodles.filter { noodle in
            servings.contains { $0.noodles.contains(where: { $0.uuid == noodle.uuid }) }
        }
        if let noodle = previouslyUsed.first(where: { recentlyUsedNoodleIDs.contains($0.uuid) == false }) {
            return DailyRecommendation(
                message: "今日は\(noodle.name)を\n選んでみるのはどう？",
                reason: "最近選んでいない麺からおすすめしています。"
            )
        }

        if let highestRated = visitedStores.max(by: {
            ($0.averageRating ?? 0) < ($1.averageRating ?? 0)
        }) {
            return DailyRecommendation(
                message: "高評価の\n\(highestRated.displayName)はどう？",
                reason: "これまでの評価が高い店舗です。"
            )
        }

        return DailyRecommendation(
            message: "今日は新しい麻辣湯店を\n探してみよう",
            reason: "地図タブから3km圏内のお店を探せます。"
        )
    }

    private static func oldestVisitedStore(in stores: [Store]) -> Store? {
        stores.min {
            (realLastVisit(of: $0) ?? .distantPast) < (realLastVisit(of: $1) ?? .distantPast)
        }
    }

    private static func realLastVisit(of store: Store) -> Date? {
        store.servings
            .filter { SampleDataService.isSample($0) == false }
            .map(\.date)
            .max()
    }
}

// MARK: - 共通カード

struct ServingHighlightCard: View {
    let serving: Serving

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ServingThumbnail(photoID: serving.photoID)
                .frame(width: 184, height: 124)
            Text(serving.storeDisplayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Theme.text)
            Text(SampleDataService.isSample(serving) ? serving.memo : serving.orderSummary)
                .font(.caption)
                .foregroundStyle(Theme.subtleText)
                .lineLimit(2)
                .frame(height: 30, alignment: .top)
        }
        .frame(width: 184)
        .padding(10)
        .cardStyle()
    }
}

struct ServingRow: View {
    let serving: Serving

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ServingThumbnail(photoID: serving.photoID)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(serving.storeDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    StaticRatingLabel(rating: serving.rating)
                }
                Text(serving.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleText)
                Text(serving.orderSummary)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
                    .lineLimit(2)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.subtleText)
        }
        .foregroundStyle(Theme.text)
        .contentShape(Rectangle())
    }
}
