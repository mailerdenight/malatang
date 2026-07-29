import SwiftUI
import SwiftData

struct CatalogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Serving.date, order: .reverse) private var servings: [Serving]

    @State private var query = ""
    @State private var sortOrder: CatalogSortOrder = .newest
    @State private var filter = CatalogFilter()
    @State private var showingFilters = false
    @State private var pendingDeletion: Serving?
    @State private var showingDeleteConfirmation = false
    @State private var favorites = FavoriteStoreService.shared

    private var results: [Serving] {
        let filtered = servings
            .filter { filter.matches($0, favoriteStoreIDs: favorites.ids) }
            .filter { CatalogSearch.matches($0, query: query) }
        return sortOrder.apply(to: filtered)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    controlBar

                    if servings.isEmpty {
                        EmptyStateView(
                            symbol: "list.bullet.rectangle",
                            title: "まだ記録がありません",
                            message: "一杯記録すると、ここに時系列で並びます。"
                        )
                    } else if results.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "該当する一杯がありません",
                            message: "店舗名や絞り込みを変えてみてください。"
                        )
                    } else {
                        ForEach(results, id: \.uuid) { serving in
                            NavigationLink(value: serving) {
                                ServingListCard(serving: serving)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    serving.isHallOfFame.toggle()
                                    serving.hallOfFameMarkedAt = serving.isHallOfFame ? Date() : nil
                                    try? context.save()
                                } label: {
                                    Label(
                                        serving.isHallOfFame ? "殿堂入りから外す" : "殿堂入りにする",
                                        systemImage: serving.isHallOfFame ? "crown.fill" : "crown"
                                    )
                                }
                                Button(role: .destructive) {
                                    requestDeletion(of: serving)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .warmBackground()
            .searchable(text: $query, prompt: "店舗名を検索")
            .navigationTitle("記録一覧")
            .navigationDestination(for: Serving.self) { ServingDetailView(serving: $0) }
            .sheet(isPresented: $showingFilters) {
                CatalogFilterView(filter: $filter)
            }
            .confirmationDialog(
                "この記録を削除しますか？",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("削除する", role: .destructive) {
                    if let pendingDeletion {
                        PhotoStore.shared.delete(pendingDeletion.photoID)
                        context.delete(pendingDeletion)
                        try? context.save()
                    }
                    pendingDeletion = nil
                }
                Button("やめる", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("記録と写真が消えます。取り消せません。")
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Picker("並び替え", selection: $sortOrder) {
                ForEach(CatalogSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.secondary)

            Spacer()

            Button {
                showingFilters = true
            } label: {
                Label(
                    filter.isActive ? "絞り込み中" : "絞り込み",
                    systemImage: filter.isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .font(.subheadline)
            }
            .buttonStyle(.bordered)

            Text("\(results.count)杯")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.subtleText)
        }
    }

    private func requestDeletion(of serving: Serving) {
        pendingDeletion = serving
        showingDeleteConfirmation = true
    }
}

struct ServingListCard: View {
    let serving: Serving

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ServingThumbnail(photoID: serving.photoID)
                .frame(width: 104, height: 104)
                .overlay(alignment: .topTrailing) {
                    if SampleDataService.isSample(serving) {
                        Text("sample")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.22), in: Capsule())
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(serving.storeDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    StaticRatingLabel(rating: serving.rating)
                }

                Text(serving.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)

                HStack(spacing: 12) {
                    Label(
                        serving.priceYen.map { "¥\($0.formatted())" } ?? "価格未入力",
                        systemImage: "yensign.circle"
                    )
                    Label("辛さ \(serving.spiceLevel)", systemImage: "flame.fill")
                }
                .font(.caption)
                .foregroundStyle(Theme.subtleText)

                if serving.isHallOfFame {
                    Label("殿堂入り", systemImage: "crown.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .cardStyle()
        .foregroundStyle(Theme.text)
        .contentShape(Rectangle())
    }
}

// MARK: - 並び替え

enum CatalogSortOrder: String, CaseIterable, Identifiable {
    case newest, oldest, rating, price

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "新しい順"
        case .oldest: return "古い順"
        case .rating: return "評価順"
        case .price: return "価格順"
        }
    }

    func apply(to items: [Serving]) -> [Serving] {
        switch self {
        case .newest: return items.sorted { $0.date > $1.date }
        case .oldest: return items.sorted { $0.date < $1.date }
        case .rating: return items.sorted { ($0.rating, $0.date) > ($1.rating, $1.date) }
        case .price: return items.sorted { ($0.priceYen ?? Int.max) < ($1.priceYen ?? Int.max) }
        }
    }
}

// MARK: - 検索

enum CatalogSearch {
    /// 既存の詳細検索互換性を保つ。画面上の主導線は店舗名検索。
    static func matches(_ serving: Serving, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false else { return true }

        var haystack: [String] = [serving.memo, serving.spiceNote]
        if let store = serving.store {
            haystack.append(store.displayName)
            haystack.append(store.address)
        }
        if let soup = serving.soup { haystack.append(soup.searchHaystack) }
        haystack.append(contentsOf: serving.noodles.map(\.searchHaystack))
        haystack.append(contentsOf: serving.ingredients.map(\.searchHaystack))

        return haystack.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

// MARK: - 絞り込み

struct CatalogFilter {
    var storeUUID: UUID?
    var soupUUID: UUID?
    var noodleUUID: UUID?
    var ingredientUUID: UUID?
    var minRating: Int = 0
    var minSpice: Int = 0
    var minNumbness: Int = 0
    var maximumPrice: Int?
    var favoriteOnly = false
    var usualOnly = false
    var hallOfFameOnly = false

    var isActive: Bool {
        storeUUID != nil || soupUUID != nil || noodleUUID != nil || ingredientUUID != nil
            || minRating > 0 || minSpice > 0 || minNumbness > 0 || maximumPrice != nil
            || favoriteOnly || usualOnly || hallOfFameOnly
    }

    mutating func reset() { self = CatalogFilter() }

    func matches(_ serving: Serving) -> Bool {
        matches(serving, favoriteStoreIDs: FavoriteStoreService.shared.ids)
    }

    func matches(_ serving: Serving, favoriteStoreIDs: Set<UUID>) -> Bool {
        if let storeUUID, serving.store?.uuid != storeUUID { return false }
        if let soupUUID, serving.soup?.uuid != soupUUID { return false }
        if let noodleUUID, serving.noodles.contains(where: { $0.uuid == noodleUUID }) == false { return false }
        if let ingredientUUID, serving.ingredients.contains(where: { $0.uuid == ingredientUUID }) == false { return false }
        if serving.rating < minRating { return false }
        if serving.spiceLevel < minSpice { return false }
        if serving.numbnessLevel < minNumbness { return false }
        if let maximumPrice, (serving.priceYen ?? Int.max) > maximumPrice { return false }
        if favoriteOnly {
            guard let storeID = serving.store?.uuid, favoriteStoreIDs.contains(storeID) else { return false }
        }
        if usualOnly, serving.isUsual == false { return false }
        if hallOfFameOnly, serving.isHallOfFame == false { return false }
        return true
    }
}

struct CatalogFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Store.name) private var stores: [Store]
    @Query(sort: \Soup.sortOrder) private var soups: [Soup]
    @Query(sort: \Noodle.sortOrder) private var noodles: [Noodle]
    @Query(sort: \Ingredient.sortOrder) private var ingredients: [Ingredient]

    @Binding var filter: CatalogFilter

    var body: some View {
        NavigationStack {
            Form {
                Section("評価・辛さ・価格") {
                    Stepper("評価 \(filter.minRating) 以上", value: $filter.minRating, in: 0...5)
                    Stepper("辛さ \(filter.minSpice) 以上", value: $filter.minSpice, in: 0...5)
                    Picker("価格", selection: $filter.maximumPrice) {
                        Text("すべて").tag(Int?.none)
                        Text("1,000円以下").tag(Int?.some(1_000))
                        Text("1,500円以下").tag(Int?.some(1_500))
                        Text("2,000円以下").tag(Int?.some(2_000))
                        Text("3,000円以下").tag(Int?.some(3_000))
                    }
                }

                Section("お気に入り") {
                    Toggle("お気に入り店舗だけ", isOn: $filter.favoriteOnly)
                    Toggle("殿堂入りだけ", isOn: $filter.hallOfFameOnly)
                }

                Section("店舗") {
                    Picker("店舗", selection: $filter.storeUUID) {
                        Text("すべて").tag(UUID?.none)
                        ForEach(stores, id: \.uuid) { store in
                            Text(store.displayName).tag(UUID?.some(store.uuid))
                        }
                    }
                }

                Section("レシピ") {
                    Picker("スープ", selection: $filter.soupUUID) {
                        Text("すべて").tag(UUID?.none)
                        ForEach(soups, id: \.uuid) { soup in
                            Text(soup.name).tag(UUID?.some(soup.uuid))
                        }
                    }
                    Picker("麺", selection: $filter.noodleUUID) {
                        Text("すべて").tag(UUID?.none)
                        ForEach(noodles, id: \.uuid) { noodle in
                            Text(noodle.name).tag(UUID?.some(noodle.uuid))
                        }
                    }
                    Picker("具材", selection: $filter.ingredientUUID) {
                        Text("すべて").tag(UUID?.none)
                        ForEach(ingredients.filter { $0.isHidden == false }, id: \.uuid) { ingredient in
                            Text(ingredient.name).tag(UUID?.some(ingredient.uuid))
                        }
                    }
                }

                Section {
                    Button("絞り込みを解除", role: .destructive) {
                        filter.reset()
                    }
                }
            }
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }.font(.body.weight(.semibold))
                }
            }
        }
    }
}
