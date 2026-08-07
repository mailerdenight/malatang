import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Environment(CurrencySettings.self) private var currencySettings
    @Query private var servings: [Serving]
    @Query private var stores: [Store]

    private var realServings: [Serving] {
        servings.filter { SampleDataService.isSample($0) == false }
    }

    private var baseCurrencyCode: String {
        currencySettings.baseCurrencyCode(for: servings)
    }

    private var summary: AnalyticsSummary {
        let visitedStoreCount = stores.filter {
            $0.servings.contains { SampleDataService.isSample($0) == false }
        }.count
        return AnalyticsSummary(
            servings: realServings,
            storeCount: visitedStoreCount,
            currencyCode: baseCurrencyCode
        )
    }

    private var hasEnoughData: Bool { realServings.count >= 3 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    numbersCard

                    if hasEnoughData == false {
                        SectionCard(title: "グラフ") {
                            EmptyStateView(
                                symbol: "chart.bar",
                                title: "記録が増えると表示されます",
                                message: String(
                                    localized: "3杯目からグラフが出ます。（今 \(realServings.count)杯）"
                                )
                            )
                        }
                    } else {
                        rankingCard(
                            title: "よく使う具材 トップ10",
                            items: summary.topIngredients
                        )
                        rankingCard(title: "麺の利用回数", items: summary.noodleCounts)
                        rankingCard(title: "スープの利用回数", items: summary.soupCounts)
                        distributionCard(title: "辛さの分布", counts: summary.spiceDistribution, symbol: "flame.fill")
                        distributionCard(title: "痺れの分布", counts: summary.numbnessDistribution, symbol: "bolt.fill")
                    }
                }
                .padding(16)
            }
            .warmBackground()
            .navigationTitle("分析")
        }
    }

    private var numbersCard: some View {
        SectionCard(title: "これまでの記録") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                statTile("総杯数", "\(summary.totalCount)", "杯")
                statTile("訪問店舗数", "\(summary.storeCount)", "店")
                statTile(
                    "平均価格",
                    summary.averagePrice.map { currencySettings.format($0, code: baseCurrencyCode) } ?? "—",
                    ""
                )
                statTile("今月の杯数", "\(summary.thisMonthCount)", "杯")
            }
        }
    }

    private func statTile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(Theme.subtleText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(LocalizedStringKey(unit))
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rankingCard(title: String, items: [AnalyticsSummary.CountedItem]) -> some View {
        if items.isEmpty == false {
            SectionCard(title: title) {
                let maximum = items.map(\.count).max() ?? 1
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Text(verbatim: item.name)
                                .font(.subheadline)
                                .frame(width: 96, alignment: .leading)
                                .lineLimit(1)
                            BarView(ratio: Double(item.count) / Double(maximum), color: Theme.primary)
                            Text("\(item.count)回")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.subtleText)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "\(item.name) \(item.count)回"))
                    }
                }
            }
        }
    }

    private func distributionCard(title: String, counts: [Int], symbol: String) -> some View {
        SectionCard(title: title) {
            let maximum = counts.max() ?? 1
            VStack(spacing: 8) {
                ForEach(0..<counts.count, id: \.self) { level in
                    HStack(spacing: 10) {
                        HStack(spacing: 2) {
                            Text("\(level)")
                                .font(.subheadline.monospacedDigit())
                            Image(systemName: symbol)
                                .font(.caption2)
                                .foregroundStyle(Theme.primary)
                        }
                        .frame(width: 44, alignment: .leading)
                        BarView(ratio: maximum == 0 ? 0 : Double(counts[level]) / Double(maximum), color: Theme.secondary)
                        Text("\(counts[level])杯")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.subtleText)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("レベル\(level) \(counts[level])杯")
                }
            }
        }
    }
}

struct BarView: View {
    let ratio: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.hairline)
                Capsule()
                    .fill(color.opacity(0.75))
                    .frame(width: max(proxy.size.width * min(max(ratio, 0), 1), ratio > 0 ? 6 : 0))
            }
        }
        .frame(height: 12)
    }
}

// MARK: - 集計

struct AnalyticsSummary {

    struct CountedItem: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
    }

    let totalCount: Int
    let storeCount: Int
    let averagePrice: Int?
    let thisMonthCount: Int
    let topIngredients: [CountedItem]
    let noodleCounts: [CountedItem]
    let soupCounts: [CountedItem]
    let spiceDistribution: [Int]
    let numbnessDistribution: [Int]

    init(
        servings: [Serving],
        storeCount: Int,
        currencyCode: String = AppCurrency.defaultCode()
    ) {
        totalCount = servings.count
        self.storeCount = storeCount

        let prices = servings
            .filter { $0.currencyCode == currencyCode }
            .compactMap(\.priceYen)
        averagePrice = prices.isEmpty ? nil : prices.reduce(0, +) / prices.count

        let calendar = Calendar.current
        let now = Date()
        thisMonthCount = servings.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count

        topIngredients = Self.rank(
            servings.flatMap { $0.ingredients.map(\.localizedDisplayName) },
            limit: 10
        )
        noodleCounts = Self.rank(
            servings.flatMap { $0.noodles.map(\.localizedDisplayName) },
            limit: 20
        )
        soupCounts = Self.rank(
            servings.compactMap { $0.soup?.localizedDisplayName },
            limit: 20
        )

        var spice = Array(repeating: 0, count: 6)
        var numbness = Array(repeating: 0, count: 6)
        for serving in servings {
            if (0...5).contains(serving.spiceLevel) { spice[serving.spiceLevel] += 1 }
            if (0...5).contains(serving.numbnessLevel) { numbness[serving.numbnessLevel] += 1 }
        }
        spiceDistribution = spice
        numbnessDistribution = numbness
    }

    private static func rank(_ names: [String], limit: Int) -> [CountedItem] {
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return counts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(limit)
            .map { CountedItem(name: $0.key, count: $0.value) }
    }
}
