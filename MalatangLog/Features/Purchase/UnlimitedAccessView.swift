import SwiftUI

struct UnlimitedAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    let visitedStoreCount: Int
    var onUnlocked: (() -> Void)?

    @State private var notice: PurchaseNotice?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("もっと麻辣湯を記録しよう")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.text)
                        Text("無料版では5店舗まで記録できます。買い切りで、店舗数と記録数がずっと無制限になります。")
                            .foregroundStyle(Theme.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        feature("店舗数・記録数が無制限", symbol: "infinity")
                        feature("分析・地図・バックアップもすべて利用可能", symbol: "chart.bar.xaxis")
                        feature("月額料金なしの買い切り", symbol: "checkmark.seal")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    freePlanNotice

                    Button {
                        Task { await purchase() }
                    } label: {
                        HStack {
                            if purchaseManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(
                                purchaseManager.isUnlocked
                                    ? "無制限版は解除済みです"
                                    : "無制限版にする　\(purchaseManager.displayedPrice)"
                            )
                            .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .disabled(purchaseManager.isLoading || purchaseManager.isUnlocked)

                    Button("このまま無料で使う") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)

                    Button("購入を復元") {
                        Task { await restore() }
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                    .disabled(purchaseManager.isLoading)

                    Text("購入処理はAppleのStoreKitを通じて行われます。広告や行動追跡はありません。")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtleText)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("閉じる")) {
                        if purchaseManager.isUnlocked {
                            finishUnlock()
                        }
                    }
                )
            }
            .onChange(of: purchaseManager.errorMessage) { _, message in
                guard let message else { return }
                notice = PurchaseNotice(title: "お知らせ", message: message)
                purchaseManager.clearError()
            }
        }
    }

    private var freePlanNotice: some View {
        let remaining = StoreAccessPolicy.remainingFreeStores(
            visitedStoreCount: visitedStoreCount
        )
        return VStack(alignment: .leading, spacing: 7) {
            Label("無料版の利用状況", systemImage: "storefront")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.secondary)
            Text("\(min(visitedStoreCount, StoreAccessPolicy.freeStoreLimit)) / \(StoreAccessPolicy.freeStoreLimit)店舗を記録済み")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.text)
            Text(
                remaining > 0
                    ? "あと\(remaining)店舗を無料で記録できます。既存店舗への記録追加は何杯でも無料です。"
                    : "既存店舗への記録追加、閲覧、編集、バックアップは引き続き無料です。"
            )
            .font(.footnote)
            .foregroundStyle(Theme.subtleText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func purchase() async {
        if purchaseManager.isUnlocked {
            finishUnlock()
            return
        }

        switch await purchaseManager.purchase() {
        case .purchased:
            notice = PurchaseNotice(
                title: "購入が完了しました",
                message: "店舗数と記録数が無制限になりました。"
            )
        case .pending:
            notice = PurchaseNotice(
                title: "購入は保留中です",
                message: "承認後、自動的に無制限版が利用できるようになります。"
            )
        case .cancelled:
            break
        }
    }

    private func restore() async {
        let restored = await purchaseManager.restore()
        notice = PurchaseNotice(
            title: restored ? "購入を復元しました" : "購入が見つかりませんでした",
            message: restored
                ? "無制限版が利用できるようになりました。"
                : "このApple Accountで復元できる購入はありませんでした。"
        )
    }

    private func finishUnlock() {
        dismiss()
        onUnlocked?()
    }

    private func feature(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PurchaseNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
