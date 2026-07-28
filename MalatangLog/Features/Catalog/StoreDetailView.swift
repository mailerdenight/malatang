import SwiftUI
import SwiftData

struct StoreDetailView: View {
    @Bindable var store: Store

    private var servings: [Serving] {
        store.servings.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "店舗情報") {
                    StoreActionRow(store: store)
                }

                SectionCard(title: "実績") {
                    VStack(alignment: .leading, spacing: 10) {
                        statRow("訪問回数", "\(store.visitCount)回")
                        statRow("平均評価", store.averageRating.map { String(format: "%.1f", $0) } ?? "未評価")
                        statRow("平均価格", store.averagePrice.map { "\($0)円" } ?? "未入力")
                        statRow(
                            "最後の訪問",
                            store.lastVisit.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "なし"
                        )
                    }
                }

                SectionCard(title: "この店の記録", subtitle: "\(servings.count)件") {
                    VStack(spacing: 12) {
                        ForEach(servings, id: \.uuid) { serving in
                            NavigationLink(value: serving) {
                                ServingRow(serving: serving)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .warmBackground()
        .navigationTitle(store.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.subtleText)
            Spacer()
            Text(value).font(.body.weight(.medium))
        }
    }
}
