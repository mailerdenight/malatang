import SwiftUI
import SwiftData

struct ServingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencySettings.self) private var currencySettings

    @Bindable var serving: Serving

    @State private var showingEditor = false
    @State private var showingOrderMemo = false
    @State private var showingDeleteConfirm = false

    /// いつもの一杯は店舗ごとに最大3件
    private var usualCountForStore: Int {
        guard let store = serving.store else { return 0 }
        return store.servings.filter { $0.isUsual && $0.uuid != serving.uuid }.count
    }

    private var canMarkUsual: Bool {
        serving.isUsual || serving.store == nil || usualCountForStore < 3
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoSection
                reproduceButton
                storeCard
                orderCard
                if serving.rating > 0 || serving.memo.isEmpty == false { impressionCard }
                if hasNumbers { numbersCard }
                if hasTasteDetail { tasteCard }
                markButtons
                editDeleteButtons
            }
            .padding(16)
        }
        .warmBackground()
        .navigationTitle(serving.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            RecordEditorView(mode: .edit(serving))
        }
        .navigationDestination(isPresented: $showingOrderMemo) {
            OrderMemoView(serving: serving)
        }
        .confirmationDialog(
            "この記録を削除しますか？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) { deleteServing() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("記録と写真が消えます。取り消せません。")
        }
    }

    // MARK: - セクション

    private var photoSection: some View {
        ServingThumbnail(photoID: serving.photoID)
            .frame(height: 220)
    }

    private var reproduceButton: some View {
        Button {
            showingOrderMemo = true
        } label: {
            Label("この一杯をもう一度", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.primary)
    }

    @ViewBuilder
    private var storeCard: some View {
        if let store = serving.store {
            SectionCard(title: "店舗") {
                StoreActionRow(store: store)
            }
        }
    }

    private var orderCard: some View {
        SectionCard(title: "注文内容") {
            VStack(alignment: .leading, spacing: 12) {
                labeledRow(
                    "スープ",
                    serving.soup?.localizedDisplayName ?? String(localized: "未設定")
                )
                HStack(spacing: 20) {
                    levelBadge(title: "辛さ", value: serving.spiceLevel, symbol: "flame.fill")
                    levelBadge(title: "痺れ", value: serving.numbnessLevel, symbol: "bolt.fill")
                }
                if serving.spiceNote.isEmpty == false {
                    labeledRow("店の表記", serving.spiceNote)
                }
                labeledRow(
                    "麺",
                    serving.noodles.isEmpty
                        ? String(localized: "未設定")
                        : AppLocalization.list(serving.noodles.map(\.localizedDisplayName))
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("具材").font(.caption).foregroundStyle(Theme.subtleText)
                    if serving.ingredients.isEmpty {
                        Text("なし").font(.body)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(serving.ingredients, id: \.uuid) { ingredient in
                                Text(verbatim: ingredient.localizedDisplayName)
                                    .font(.footnote)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.secondary.opacity(0.10), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private var impressionCard: some View {
        SectionCard(title: "感想") {
            VStack(alignment: .leading, spacing: 10) {
                if serving.rating > 0 {
                    StarRatingView(rating: .constant(serving.rating), isEditable: false, size: 20)
                }
                if serving.memo.isEmpty == false {
                    Text(SampleDataService.displayMemo(for: serving))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hasNumbers: Bool {
        serving.priceYen != nil || serving.totalWeightGrams != nil
            || serving.pricePer100gYen != nil || serving.soupSurchargeYen != nil
    }

    private var numbersCard: some View {
        SectionCard(title: "価格・重量") {
            VStack(alignment: .leading, spacing: 8) {
                if let price = serving.priceYen {
                    labeledRow("価格", currencySettings.format(price, code: serving.currencyCode))
                }
                if let weight = serving.totalWeightGrams { labeledRow("重量", "\(weight)g") }
                if let unit = serving.pricePer100gYen {
                    labeledRow("100g単価", currencySettings.format(unit, code: serving.currencyCode))
                }
                if let surcharge = serving.soupSurchargeYen {
                    labeledRow("スープ追加", currencySettings.format(surcharge, code: serving.currencyCode))
                }
            }
        }
    }

    private var tasteValues: [(String, Int)] {
        [
            ("濃さ", serving.richness), ("油", serving.oiliness), ("胡麻感", serving.sesameNote),
            ("薬膳感", serving.herbalNote), ("酸味", serving.sourness),
            ("にんにく", serving.garlic), ("香菜", serving.cilantro)
        ].filter { $0.1 > 0 }
    }

    private var hasTasteDetail: Bool { tasteValues.isEmpty == false }

    private var tasteCard: some View {
        SectionCard(title: "味の詳細") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tasteValues, id: \.0) { item in
                    labeledRow(item.0, "\(item.1) / 5")
                }
            }
        }
    }

    private var markButtons: some View {
        SectionCard(title: "この一杯の位置づけ") {
            VStack(spacing: 10) {
                Button {
                    toggleUsual()
                } label: {
                    Label(
                        serving.isUsual ? "いつもの一杯を解除" : "いつもの一杯に指定",
                        systemImage: serving.isUsual ? "bookmark.fill" : "bookmark"
                    )
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.bordered)
                .disabled(canMarkUsual == false)

                if canMarkUsual == false {
                    Text("この店舗の「いつもの一杯」は3件までです。ほかの指定を解除してください。")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleText)
                }

                Button {
                    toggleHallOfFame()
                } label: {
                    Label(
                        serving.isHallOfFame ? "殿堂入りを解除" : "殿堂入りに指定",
                        systemImage: serving.isHallOfFame ? "crown.fill" : "crown"
                    )
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
        }
    }

    private var editDeleteButtons: some View {
        VStack(spacing: 10) {
            Button {
                showingEditor = true
            } label: {
                Label("編集する", systemImage: "pencil")
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("削除する", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.bordered)
            .tint(Theme.primary)
        }
    }

    // MARK: - 部品

    private func labeledRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.subtleText)
            Text(verbatim: value).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelBadge(title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(Theme.subtleText)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { level in
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(level <= value ? Theme.primary : Theme.subtleText.opacity(0.3))
                }
                Text("\(value)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.subtleText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "\(AppLocalization.string(title)) 5段階中\(value)")
        )
    }

    // MARK: - 操作

    private func toggleUsual() {
        serving.isUsual.toggle()
        serving.usualMarkedAt = serving.isUsual ? Date() : nil
        try? context.save()
    }

    private func toggleHallOfFame() {
        serving.isHallOfFame.toggle()
        serving.hallOfFameMarkedAt = serving.isHallOfFame ? Date() : nil
        try? context.save()
    }

    private func deleteServing() {
        PhotoStore.shared.delete(serving.photoID)
        context.delete(serving)
        try? context.save()
        dismiss()
    }
}

// MARK: - 店舗の地図行

struct StoreActionRow: View {
    let store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayName)
                        .font(.body.weight(.semibold))
                    if store.address.isEmpty == false {
                        Text(verbatim: SampleDataService.displayAddress(for: store))
                            .font(.caption)
                            .foregroundStyle(Theme.subtleText)
                            .lineLimit(1)
                    } else {
                        Text("住所は未登録（店名で検索します）")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleText)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    mapMenu(title: "地図", symbol: "map", isDirections: false)
                    mapMenu(title: "経路", symbol: "arrow.triangle.turn.up.right.diamond", isDirections: true)
                }
            }
        }
    }

    private func mapMenu(title: String, symbol: String, isDirections: Bool) -> some View {
        Menu {
            if MapLauncher.isGoogleMapsInstalled {
                Button {
                    open(.google, isDirections: isDirections)
                } label: {
                    Label(MapLauncher.Provider.google.title, systemImage: MapLauncher.Provider.google.symbol)
                }
            } else {
                Button {
                    open(.google, isDirections: isDirections)
                } label: {
                    Label("Googleマップ（Webで開く）", systemImage: MapLauncher.Provider.google.symbol)
                }
            }
            Button {
                open(.apple, isDirections: isDirections)
            } label: {
                Label(MapLauncher.Provider.apple.title, systemImage: MapLauncher.Provider.apple.symbol)
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(LocalizedStringKey(title)).font(.caption2)
            }
            .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
            .background(Theme.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(
            String(localized: "\(store.displayName)を\(AppLocalization.string(title))で開く")
        )
    }

    private func open(_ provider: MapLauncher.Provider, isDirections: Bool) {
        let destination = MapLauncher.Destination.make(for: store)
        if isDirections {
            MapLauncher.openDirections(destination, using: provider)
        } else {
            MapLauncher.openMap(destination, using: provider)
        }
    }
}
