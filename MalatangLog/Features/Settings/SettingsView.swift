import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(CurrencySettings.self) private var currencySettings
    @Query private var servings: [Serving]
    @Query(sort: \Ingredient.sortOrder) private var ingredients: [Ingredient]

    @State private var showingUnlimitedAccess = false
    @State private var restoreMessage: String?

    private var hiddenIngredients: [Ingredient] {
        ingredients.filter(\.isHidden)
    }

    private var realServings: [Serving] {
        servings.filter { SampleDataService.isSample($0) == false }
    }

    private var isCurrencyLocked: Bool {
        currencySettings.isLocked(by: servings)
    }

    private var baseCurrencyCode: String {
        currencySettings.baseCurrencyCode(for: servings)
    }

    private var visitedStoreCount: Int {
        Set<UUID>(
            realServings.compactMap { $0.store?.uuid }
        ).count
    }

    var body: some View {
        @Bindable var appearanceSettings = appearanceSettings
        @Bindable var currencySettings = currencySettings

        List {
            Section("テーマ") {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(AppTheme.allCases) { theme in
                        themeCard(theme, appearanceSettings: appearanceSettings)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Text("明るさ")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $appearanceSettings.preference) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(verbatim: preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .accessibilityLabel("明るさ")
                }
            }

            Section {
                if isCurrencyLocked {
                    HStack {
                        Label("既定の通貨", systemImage: "creditcard")
                        Spacer()
                        Text(verbatim: AppCurrency(rawValue: baseCurrencyCode)?.title ?? baseCurrencyCode)
                            .foregroundStyle(Theme.subtleText)
                    }
                } else {
                    Picker("既定の通貨", selection: $currencySettings.defaultCurrencyCode) {
                        ForEach(AppCurrency.allCases) { currency in
                            Text(verbatim: currency.title).tag(currency.rawValue)
                        }
                    }
                }
            } header: {
                Text("通貨")
            } footer: {
                if isCurrencyLocked {
                    Text("記録があるため通貨は変更できません。最初に設定した通貨がこのアプリの基準通貨になります。")
                } else {
                    Text("最初の記録を保存する前だけ変更できます。初期値は端末の言語から自動設定します。")
                }
            }

            purchaseSection

            Section("その他") {
                NavigationLink {
                    BackupView()
                } label: {
                    Label("バックアップと復元", systemImage: "externaldrive")
                }
            }

            if hiddenIngredients.isEmpty == false {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(hiddenIngredients, id: \.uuid) { ingredient in
                            TagChip(title: ingredient.localizedDisplayName) {
                                MasterService.unhide(ingredient)
                                try? context.save()
                            }
                        }
                    }
                } header: {
                    Text("非表示にした具材")
                } footer: {
                    Text("\(hiddenIngredients.count)件。過去の記録には表示され続けます。")
                }
            }

            Section("このアプリについて") {
                HStack {
                    Text("バージョン")
                        .font(.subheadline)
                    Spacer()
                    Text(AppInfo.shortVersionString)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleText)
                }
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Text("プライバシーポリシー")
                        .font(.subheadline)
                }
                NavigationLink {
                    HelpView()
                } label: {
                    Text("ヘルプ・使い方")
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(appearanceSettings.preferredColorScheme)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingUnlimitedAccess) {
            UnlimitedAccessView(visitedStoreCount: visitedStoreCount)
        }
        .alert(
            "購入の復元",
            isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if $0 == false { restoreMessage = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private func themeCard(
        _ theme: AppTheme,
        appearanceSettings: AppearanceSettings
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appearanceSettings.theme = theme
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.backgroundColor)
                        .frame(height: 64)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    appearanceSettings.theme == theme
                                        ? theme.primaryColor
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(theme.primaryColor)
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(theme.secondaryColor)
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(theme.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }

                HStack(spacing: 4) {
                    if appearanceSettings.theme == theme {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(theme.primaryColor)
                    }
                    Text(verbatim: theme.title)
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(theme.title)
        .accessibilityValue(appearanceSettings.theme == theme ? "選択中" : "")
    }

    private var purchaseSection: some View {
        Section {
            HStack {
                Label(
                    purchaseManager.isUnlocked ? "無制限版をご利用中です" : "無料版",
                    systemImage: purchaseManager.isUnlocked ? "checkmark.seal.fill" : "storefront"
                )
                .font(.subheadline)
                .foregroundStyle(purchaseManager.isUnlocked ? Theme.secondary : Theme.text)
                Spacer()
                if purchaseManager.isUnlocked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.secondary)
                        .fontWeight(.semibold)
                } else {
                    Text("\(min(visitedStoreCount, StoreAccessPolicy.freeStoreLimit)) / \(StoreAccessPolicy.freeStoreLimit)店舗")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.subtleText)
                }
            }

            if purchaseManager.isUnlocked == false {
                Button {
                    showingUnlimitedAccess = true
                } label: {
                    HStack {
                        Label("買い切りで無制限にする", systemImage: "infinity")
                            .foregroundStyle(Theme.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleText)
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                Task {
                    let restored = await purchaseManager.restore()
                    restoreMessage = restored
                        ? String(localized: "無制限版の購入を復元しました。")
                        : String(localized: "このApple Accountで復元できる購入はありませんでした。")
                }
            } label: {
                HStack(spacing: 8) {
                    if purchaseManager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(purchaseManager.isLoading ? "購入を確認しています…" : "購入を復元する")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primary)
                }
            }
            .disabled(purchaseManager.isLoading)
        } header: {
            Text("利用プラン")
        } footer: {
            if purchaseManager.isUnlocked {
                Text("店舗数・記録数・バックアップの上限はありません。")
            } else {
                let remaining = StoreAccessPolicy.remainingFreeStores(
                    visitedStoreCount: visitedStoreCount
                )
                Text(
                    remaining > 0
                        ? "あと\(remaining)店舗を無料で記録できます。"
                        : "既存店舗への記録追加、閲覧、編集は引き続き無料です。バックアップは無制限版で使えます。"
                )
            }
        }
    }

}

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                privacyLine("氏名・メールアドレス・広告識別子は取得しません。")
                privacyLine("アカウント登録も、独自サーバーへの送信もありません。")
                privacyLine("位置情報は店舗検索と経路表示のときだけ使い、常時追跡はしません。")
                privacyLine("行動分析SDKは入れていません。")
                privacyLine("購入はAppleのStoreKitが処理し、カード情報をアプリで取得しません。")
            } footer: {
                Text("記録データは端末内に保存します。地図検索・経路表示・購入確認にはAppleや選択した地図サービスとの通信を使います。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
            Text(verbatim: AppLocalization.string(text))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HelpView: View {
    var body: some View {
        List {
            helpSection(
                title: "一杯を記録する",
                text: "ホームの「記録する」から、店舗・写真・辛さ・具材・価格などを保存できます。入力していない項目があっても記録できます。"
            )
            helpSection(
                title: "お店を地図で探す",
                text: "地図タブのピンを選ぶと、店舗情報の確認、お気に入り登録、その店舗での記録作成ができます。"
            )
            helpSection(
                title: "過去の一杯を見る",
                text: "アルバムでは月別の写真を、分析では記録数やよく選ぶ具材などを確認できます。"
            )
            helpSection(
                title: "データを守る",
                text: "設定の「バックアップと復元」から、写真を含むバックアップファイルを作成できます。機種変更前などに保存してください。"
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("ヘルプ")
    }

    private func helpSection(title: String, text: String) -> some View {
        Section(AppLocalization.string(title)) {
            Text(verbatim: AppLocalization.string(text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
