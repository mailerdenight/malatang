import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var servings: [Serving]
    @Query(sort: \Ingredient.sortOrder) private var ingredients: [Ingredient]

    @State private var copiedNotice = false
    @AppStorage("appearancePreference") private var appearancePreference = AppearancePreference.light.rawValue

    private var hiddenIngredients: [Ingredient] {
        ingredients.filter(\.isHidden)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "表示") {
                    Picker("外観", selection: $appearancePreference) {
                        ForEach(AppearancePreference.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SectionCard(title: "データ") {
                    NavigationLink {
                        BackupView()
                    } label: {
                        settingsRow("バックアップと復元", systemImage: "externaldrive")
                    }
                    .buttonStyle(.plain)
                }

                if hiddenIngredients.isEmpty == false {
                    SectionCard(title: "非表示にした具材", subtitle: "\(hiddenIngredients.count)件。過去の記録には表示され続けます") {
                        FlowLayout(spacing: 8) {
                            ForEach(hiddenIngredients, id: \.uuid) { ingredient in
                                TagChip(title: ingredient.name) {
                                    MasterService.unhide(ingredient)
                                    try? context.save()
                                }
                            }
                        }
                    }
                }

                SectionCard(title: "プライバシー", subtitle: "この端末の中だけで完結します") {
                    VStack(alignment: .leading, spacing: 8) {
                        privacyLine("氏名・メールアドレス・広告識別子は取得しません。")
                        privacyLine("アカウント登録も、独自サーバーへの送信もありません。")
                        privacyLine("位置情報は店舗検索と経路表示のときだけ使い、常時追跡はしません。")
                        privacyLine("行動分析SDKは入れていません。")
                    }
                }

                SectionCard(title: "不具合の報告", subtitle: "料理・店舗・写真の内容は含みません") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(diagnosticsText)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.subtleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))

                        Button {
                            UIPasteboard.general.string = diagnosticsText
                            copiedNotice = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedNotice = false }
                        } label: {
                            Label(copiedNotice ? "コピーしました" : "不具合報告用テキストをコピー", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SectionCard(title: "アプリについて") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("バージョン").foregroundStyle(Theme.subtleText)
                            Spacer()
                            Text(AppInfo.versionString)
                        }
                        .font(.subheadline)
                        Text("麻辣湯ログ｜最高の一杯を、もう忘れない。")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleText)
                    }
                }
            }
            .padding(16)
        }
        .warmBackground()
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var diagnosticsText: String {
        """
        麻辣湯ログ 不具合報告
        アプリ: \(AppInfo.versionString)
        OS: iOS \(UIDevice.current.systemVersion)
        端末種別: \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        記録件数: \(servings.count)
        写真枚数: \(servings.compactMap(\.photoID).count)
        """
    }

    private func settingsRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.subtleText)
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
