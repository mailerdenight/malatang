import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Serving.date, order: .reverse) private var servings: [Serving]

    @State private var showingSettings = false
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

    private var recentServings: [Serving] {
        Array(realServings.prefix(3))
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
                    monthlySummaryCard
                    recentRecordsCard
                    hallOfFameCard
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                newRecordButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) { Divider() }
            }
            .warmBackground()
            .navigationTitle("麻辣湯ログ")
            .navigationDestination(for: Serving.self) { serving in
                ServingDetailView(serving: serving)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
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

    private var recentRecordsCard: some View {
        SectionCard(title: "最近の記録", subtitle: "ホームでは直近3杯だけを表示します") {
            if recentServings.isEmpty {
                Text("最初の一杯を記録すると、ここからすぐ振り返れます。")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtleText)
            } else {
                VStack(spacing: 12) {
                    ForEach(recentServings, id: \.uuid) { serving in
                        NavigationLink(value: serving) {
                            ServingRow(serving: serving)
                        }
                        .buttonStyle(.plain)
                        if serving.uuid != recentServings.last?.uuid {
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

// MARK: - 共通カード

struct ServingHighlightCard: View {
    let serving: Serving

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ServingThumbnail(photoID: serving.photoID)
                .frame(width: 184, height: 124)
                .overlay(alignment: .topTrailing) {
                    if SampleDataService.isSample(serving) {
                        Text("sample")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.18), in: Capsule())
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
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
