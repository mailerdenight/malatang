import SwiftUI
import SwiftData

enum RecordEditorMode {
    case create
    case edit(Serving)
    /// 「この一杯をもう一度」からの複製。元記録は変更しない。
    case duplicate(Serving)
}

struct RecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Soup.sortOrder) private var soups: [Soup]
    @Query(sort: \Noodle.sortOrder) private var noodles: [Noodle]
    @Query(sort: \Ingredient.sortOrder) private var ingredients: [Ingredient]
    @Query private var servings: [Serving]

    let mode: RecordEditorMode
    let initialStore: Store?

    @State private var draft = ServingDraft()
    @State private var isPrepared = false
    @State private var showingStorePicker = false
    @State private var showingIngredientPicker = false
    @State private var showingDetails = false
    @State private var showingDeleteConfirm = false
    @State private var showingSavedAnimation = false
    @State private var newSoupName = ""
    @State private var newNoodleName = ""
    @State private var masterNotice: String?

    init(mode: RecordEditorMode, initialStore: Store? = nil) {
        self.mode = mode
        self.initialStore = initialStore
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "新しい一杯"
        case .edit: return "記録を編集"
        case .duplicate: return "今日の記録を作成"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        basicsCard
                        soupCard
                        levelsCard
                        noodleCard
                        ingredientCard
                        detailsCard
                        if isEditing { deleteButton }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)

                if showingSavedAnimation {
                    SteamOverlay()
                        .transition(.opacity)
                }
            }
            .warmBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(.body.weight(.semibold))
                }
            }
            .sheet(isPresented: $showingStorePicker) {
                StorePickerView(selection: $draft.store)
            }
            .sheet(isPresented: $showingIngredientPicker) {
                IngredientPickerView(selection: $draft.ingredients)
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
        .task {
            guard isPrepared == false else { return }
            isPrepared = true
            switch mode {
            case .create:
                draft = ServingDraft()
                draft.store = initialStore
                draft.soup = soups.first { $0.isHidden == false }
            case .edit(let serving):
                draft = ServingDraft.from(serving, resettingForToday: false)
            case .duplicate(let serving):
                draft = ServingDraft.from(serving, resettingForToday: true)
            }
        }
    }

    // MARK: - 基本

    private var basicsCard: some View {
        SectionCard(title: "基本", subtitle: "必須はスープ・辛さ・痺れ・麺の4つだけ") {
            HStack(alignment: .top, spacing: 16) {
                PhotoInputTile(draft: draft)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("日時", systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subtleText)
                        DatePicker("", selection: $draft.date, in: ...Date())
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .font(.subheadline)
                    }

                    Button {
                        showingStorePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "storefront")
                            Text(draft.store?.displayName ?? "店舗を選ぶ（任意）")
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .frame(minHeight: Theme.minTapTarget)
                        .foregroundStyle(draft.store == nil ? Theme.subtleText : Theme.text)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - スープ

    private var soupCard: some View {
        SectionCard(title: "スープ", subtitle: "必須") {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 8) {
                    ForEach(soups.filter { $0.isHidden == false || $0 == draft.soup }, id: \.uuid) { soup in
                        TagChip(title: soup.name, isSelected: draft.soup == soup) {
                            draft.soup = soup
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("スープを追加", text: $newSoupName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit { addSoup() }
                    Button("追加") { addSoup() }
                        .buttonStyle(.bordered)
                        .disabled(MasterService.normalize(newSoupName).isEmpty)
                }
                fieldError(draft.soupError)
                noticeText
            }
        }
    }

    // MARK: - 辛さ・痺れ

    private var levelsCard: some View {
        SectionCard(title: "辛さと痺れ", subtitle: "必須。別々に記録します") {
            VStack(alignment: .leading, spacing: 16) {
                LevelSelector(title: "辛さ", symbol: "flame.fill", value: $draft.spiceLevel)
                LevelSelector(title: "痺れ", symbol: "bolt.fill", value: $draft.numbnessLevel)
                TextField("店舗の辛さ表記（例：中辛、3辣）", text: $draft.spiceNote)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - 麺

    private var noodleCard: some View {
        SectionCard(title: "麺", subtitle: "必須。複数選べます。入れないときは「麺なし」") {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 8) {
                    ForEach(orderedNoodles, id: \.uuid) { noodle in
                        TagChip(title: noodle.name, isSelected: draft.noodles.contains(noodle)) {
                            toggleNoodle(noodle)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("麺を追加", text: $newNoodleName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit { addNoodle() }
                    Button("追加") { addNoodle() }
                        .buttonStyle(.bordered)
                        .disabled(MasterService.normalize(newNoodleName).isEmpty)
                }
                fieldError(draft.noodleError)
            }
        }
    }

    private var orderedNoodles: [Noodle] {
        let recent = FrequentIngredients.recentNoodles(
            allNoodles: noodles,
            servings: servings,
            limit: noodles.count
        )
        let selected = draft.noodles.filter { recent.contains($0) == false }
        return selected + recent
    }

    // MARK: - 具材

    private var frequentIngredients: [Ingredient] {
        FrequentIngredients.ordered(allIngredients: ingredients, servings: servings)
    }

    private var ingredientCard: some View {
        SectionCard(title: "よく使う具材", subtitle: "使うほど並び替わります。長押しで固定・非表示") {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8) {
                    ForEach(frequentIngredients, id: \.uuid) { ingredient in
                        TagChip(
                            title: ingredient.name,
                            isSelected: draft.ingredients.contains(ingredient),
                            isPinned: ingredient.isPinned
                        ) {
                            toggleIngredient(ingredient)
                        }
                        .contextMenu {
                            Button {
                                MasterService.togglePin(ingredient)
                            } label: {
                                Label(
                                    ingredient.isPinned ? "固定を解除" : "よく使う具材に固定",
                                    systemImage: ingredient.isPinned ? "pin.slash" : "pin"
                                )
                            }
                            Button(role: .destructive) {
                                MasterService.hide(ingredient)
                                draft.ingredients.removeAll { $0 == ingredient }
                            } label: {
                                Label("一覧から非表示にする", systemImage: "eye.slash")
                            }
                        }
                    }
                }

                Button {
                    showingIngredientPicker = true
                } label: {
                    Label("すべての具材から選ぶ", systemImage: "square.grid.3x3")
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.bordered)

                if draft.ingredients.isEmpty == false {
                    Divider().overlay(Theme.hairline)
                    Text("選択中 \(draft.ingredients.count)件")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleText)
                    FlowLayout(spacing: 8) {
                        ForEach(draft.ingredients, id: \.uuid) { ingredient in
                            TagChip(title: ingredient.name, isSelected: true) {
                                toggleIngredient(ingredient)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 詳細

    private var detailsCard: some View {
        SectionCard(title: "詳細（任意）", subtitle: "価格・重量・評価・メモ・味の詳細") {
            DisclosureGroup(isExpanded: $showingDetails) {
                VStack(alignment: .leading, spacing: 14) {
                    numberField(title: "価格（税込・円）", text: $draft.priceText, error: draft.priceError)
                    numberField(title: "合計重量（g）", text: $draft.weightText, error: nil)
                    numberField(title: "100gあたり単価（円）", text: $draft.pricePer100gText, error: nil)
                    numberField(title: "スープ追加料金（円）", text: $draft.soupSurchargeText, error: nil)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("評価").font(.subheadline.weight(.semibold))
                        StarRatingView(rating: $draft.rating)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("メモ").font(.subheadline.weight(.semibold))
                        TextEditor(text: $draft.memo)
                            .frame(minHeight: 90)
                            .padding(6)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
                        fieldError(draft.memoError)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("味の詳細").font(.subheadline.weight(.semibold))
                        LevelSelector(title: "濃さ", symbol: "circle.fill", value: $draft.richness)
                        LevelSelector(title: "油", symbol: "drop.fill", value: $draft.oiliness)
                        LevelSelector(title: "胡麻感", symbol: "circle.grid.2x2.fill", value: $draft.sesameNote)
                        LevelSelector(title: "薬膳感", symbol: "leaf.fill", value: $draft.herbalNote)
                        LevelSelector(title: "酸味", symbol: "sparkles", value: $draft.sourness)
                        LevelSelector(title: "にんにく", symbol: "flame", value: $draft.garlic)
                        LevelSelector(title: "香菜", symbol: "leaf", value: $draft.cilantro)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text(showingDetails ? "詳細を閉じる" : "詳細を開く")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(minHeight: Theme.minTapTarget)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label("この記録を削除", systemImage: "trash")
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.bordered)
        .tint(Theme.primary)
    }

    // MARK: - 部品

    private func numberField(title: String, text: Binding<String>, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField("未入力可", text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            fieldError(error)
        }
    }

    @ViewBuilder
    private func fieldError(_ message: String?) -> some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var noticeText: some View {
        if let masterNotice {
            Text(masterNotice)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
    }

    // MARK: - 操作

    private func toggleNoodle(_ noodle: Noodle) {
        if let index = draft.noodles.firstIndex(of: noodle) {
            draft.noodles.remove(at: index)
        } else {
            draft.noodles.append(noodle)
        }
    }

    private func toggleIngredient(_ ingredient: Ingredient) {
        if let index = draft.ingredients.firstIndex(of: ingredient) {
            draft.ingredients.remove(at: index)
        } else {
            draft.ingredients.append(ingredient)
        }
    }

    private func addSoup() {
        guard let result = MasterService.addSoup(named: newSoupName, in: context) else { return }
        switch result {
        case .created(let soup):
            draft.soup = soup
            masterNotice = nil
        case .existing(let soup):
            draft.soup = soup
            masterNotice = "「\(soup.name)」はすでにあります。既存の候補を選びました。"
        }
        newSoupName = ""
    }

    private func addNoodle() {
        guard let result = MasterService.addNoodle(named: newNoodleName, in: context) else { return }
        switch result {
        case .created(let noodle):
            if draft.noodles.contains(noodle) == false { draft.noodles.append(noodle) }
        case .existing(let noodle):
            if draft.noodles.contains(noodle) == false { draft.noodles.append(noodle) }
            masterNotice = "「\(noodle.name)」はすでにあります。既存の候補を選びました。"
        }
        newNoodleName = ""
    }

    private func save() {
        draft.didAttemptSave = true
        guard draft.isValid else { return }

        switch mode {
        case .create, .duplicate:
            let serving = draft.makeServing()
            context.insert(serving)
        case .edit(let serving):
            draft.apply(to: serving)
        }

        do {
            try context.save()
        } catch {
            // 保存に失敗した場合は画面を閉じない（入力内容を失わせない）
            masterNotice = "保存に失敗しました。もう一度お試しください。"
            return
        }

        withAnimation { showingSavedAnimation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            dismiss()
        }
    }

    private func deleteServing() {
        guard case .edit(let serving) = mode else { return }
        PhotoStore.shared.delete(serving.photoID)
        context.delete(serving)
        try? context.save()
        dismiss()
    }
}
