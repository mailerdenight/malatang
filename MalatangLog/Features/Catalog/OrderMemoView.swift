import SwiftUI
import SwiftData

/// 店頭で見る画面。写真・評価・分析は出さず、注文に必要な情報だけを大きく出す。
struct OrderMemoView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let serving: Serving

    @State private var showingDuplicateEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                bigRow(
                    label: "スープ",
                    value: serving.soup?.localizedDisplayName ?? String(localized: "未設定")
                )
                levelRow
                if serving.spiceNote.isEmpty == false {
                    bigRow(label: "店の表記", value: serving.spiceNote)
                }
                bigRow(
                    label: "麺",
                    value: serving.noodles.isEmpty
                        ? String(localized: "未設定")
                        : AppLocalization.list(serving.noodles.map(\.localizedDisplayName))
                )
                ingredientBlock
                actions
            }
            .padding(20)
        }
        .warmBackground()
        .navigationTitle("注文メモ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDuplicateEditor) {
            RecordEditorView(mode: .duplicate(serving))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: serving.storeDisplayName)
                .font(Theme.title(26))
                .foregroundStyle(Theme.text)
            Text("\(serving.date.formatted(date: .abbreviated, time: .omitted)) の一杯")
                .font(.footnote)
                .foregroundStyle(Theme.subtleText)
        }
    }

    private func bigRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
            Text(verbatim: value)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var levelRow: some View {
        HStack(spacing: 24) {
            levelColumn(title: "辛さ", value: serving.spiceLevel, symbol: "flame.fill")
            levelColumn(title: "痺れ", value: serving.numbnessLevel, symbol: "bolt.fill")
            Spacer(minLength: 0)
        }
    }

    private func levelColumn(title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.primary)
                Text("\(value)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("/ 5")
                    .font(.body)
                    .foregroundStyle(Theme.subtleText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "\(AppLocalization.string(title)) 5段階中\(value)")
        )
    }

    private var ingredientBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("具材 \(serving.ingredients.count)件")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
            if serving.ingredients.isEmpty {
                Text("なし")
                    .font(.system(size: 26, weight: .semibold))
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(serving.ingredients, id: \.uuid) { ingredient in
                        Text(verbatim: ingredient.localizedDisplayName)
                            .font(.system(size: 22, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let store = serving.store {
                Menu {
                    Button {
                        MapLauncher.openMap(.make(for: store), using: .google)
                    } label: {
                        Label(
                            MapLauncher.isGoogleMapsInstalled ? "Googleマップ" : "Googleマップ（Webで開く）",
                            systemImage: "globe.asia.australia"
                        )
                    }
                    Button {
                        MapLauncher.openMap(.make(for: store), using: .apple)
                    } label: {
                        Label("Appleマップ", systemImage: "map")
                    }
                    Divider()
                    Button {
                        MapLauncher.openDirections(.make(for: store), using: .apple)
                    } label: {
                        Label("Appleマップで経路", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                } label: {
                    Label("地図で店へ", systemImage: "map")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            Button {
                showingDuplicateEditor = true
            } label: {
                Label("今日の記録を作成", systemImage: "plus.square.on.square")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)

            Text("元の記録はそのまま残ります。日時だけ今日に更新した新しい記録を作ります。")
                .font(.caption)
                .foregroundStyle(Theme.subtleText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
