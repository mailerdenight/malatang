import SwiftUI
import SwiftData

/// すべての具材から選ぶ画面。カテゴリ・検索・自由追加に対応する。
struct IngredientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Ingredient.sortOrder) private var allIngredients: [Ingredient]
    @Binding var selection: [Ingredient]

    @State private var query = ""
    @State private var category: IngredientCategory?
    @State private var duplicateNotice: String?

    private var visible: [Ingredient] {
        allIngredients.filter { $0.isHidden == false || selection.contains($0) }
    }

    private var filtered: [Ingredient] {
        visible
            .filter { category == nil || $0.category == category }
            .filter { $0.matches(query) }
    }

    private var trimmedQuery: String {
        MasterService.normalize(query)
    }

    private var canAddCustom: Bool {
        guard trimmedQuery.isEmpty == false else { return false }
        return visible.contains { MasterService.isSameName($0.name, trimmedQuery) } == false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selection.isEmpty == false {
                        SectionCard(
                            title: "選択中",
                            subtitle: String(localized: "\(selection.count)件")
                        ) {
                            FlowLayout(spacing: 8) {
                                ForEach(selection, id: \.uuid) { ingredient in
                                    TagChip(title: ingredient.localizedDisplayName, isSelected: true) {
                                        toggle(ingredient)
                                    }
                                }
                            }
                        }
                    }

                    if canAddCustom {
                        Button {
                            addCustom()
                        } label: {
                            Label("「\(trimmedQuery)」を具材として追加", systemImage: "plus.circle")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }

                    if let duplicateNotice {
                        Text(duplicateNotice)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    }

                    categoryFilter

                    if filtered.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "見つかりませんでした",
                            message: "ひらがな・漢字・中国語名でも探せます。無ければ上のボタンから追加できます。"
                        )
                    } else {
                        ForEach(groupedCategories, id: \.self) { group in
                            SectionCard(title: group.displayName) {
                                FlowLayout(spacing: 8) {
                                    ForEach(filtered.filter { $0.category == group }, id: \.uuid) { ingredient in
                                        TagChip(
                                            title: ingredient.localizedDisplayName,
                                            isSelected: selection.contains(ingredient),
                                            isPinned: ingredient.isPinned
                                        ) {
                                            toggle(ingredient)
                                        }
                                        .contextMenu {
                                            ingredientMenu(ingredient)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .warmBackground()
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, prompt: "具材を検索（別名でも可）")
            .navigationTitle("具材を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var groupedCategories: [IngredientCategory] {
        IngredientCategory.allCases.filter { group in
            filtered.contains { $0.category == group }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TagChip(title: String(localized: "すべて"), isSelected: category == nil) {
                    category = nil
                }
                ForEach(IngredientCategory.allCases) { item in
                    TagChip(title: item.displayName, isSelected: category == item) {
                        category = (category == item) ? nil : item
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func ingredientMenu(_ ingredient: Ingredient) -> some View {
        Button {
            MasterService.togglePin(ingredient)
        } label: {
            Label(
                ingredient.isPinned ? "よく使う具材の固定を解除" : "よく使う具材に固定",
                systemImage: ingredient.isPinned ? "pin.slash" : "pin"
            )
        }
        Button(role: .destructive) {
            MasterService.hide(ingredient)
            selection.removeAll { $0 == ingredient }
        } label: {
            Label("一覧から非表示にする", systemImage: "eye.slash")
        }
    }

    private func toggle(_ ingredient: Ingredient) {
        if let index = selection.firstIndex(of: ingredient) {
            selection.remove(at: index)
        } else {
            selection.append(ingredient)
        }
    }

    private func addCustom() {
        guard let result = MasterService.addIngredient(named: trimmedQuery, category: .custom, in: context) else { return }
        switch result {
        case .created(let ingredient):
            duplicateNotice = nil
            if selection.contains(ingredient) == false { selection.append(ingredient) }
        case .existing(let ingredient):
            duplicateNotice = String(
                localized: "「\(ingredient.localizedDisplayName)」はすでにあります。重複しないよう既存の候補を選択しました。"
            )
            if selection.contains(ingredient) == false { selection.append(ingredient) }
        }
        query = ""
    }
}
