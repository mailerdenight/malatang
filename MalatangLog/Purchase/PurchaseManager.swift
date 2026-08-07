import Foundation
import Observation
import StoreKit

enum PurchaseOutcome {
    case purchased
    case pending
    case cancelled
}

@MainActor
@Observable
final class PurchaseManager {
    private(set) var product: Product?
    private(set) var isUnlocked = false
    private(set) var hasCheckedEntitlements = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    init(previewIsUnlocked: Bool? = nil) {
        if let previewIsUnlocked {
            isUnlocked = previewIsUnlocked
            hasCheckedEntitlements = true
        } else {
            updatesTask = observeTransactions()
            Task {
                await refreshEntitlements()
                await loadProduct()
            }
        }
    }

    var displayedPrice: String {
        product?.displayPrice ?? String(localized: "価格を確認")
    }

    func loadProduct() async {
        guard product == nil else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            product = try await Product.products(
                for: [PurchaseConfiguration.unlimitedProductID]
            ).first
            if product == nil {
                errorMessage = String(localized: "商品情報を読み込めませんでした。通信状態を確認して、もう一度お試しください。")
            }
        } catch {
            errorMessage = String(localized: "商品情報を読み込めませんでした。通信状態を確認して、もう一度お試しください。")
        }
    }

    func purchase() async -> PurchaseOutcome {
        errorMessage = nil
        if product == nil {
            await loadProduct()
        }
        guard let product else { return .cancelled }

        isLoading = true
        defer { isLoading = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    errorMessage = String(localized: "購入情報を確認できませんでした。")
                    return .cancelled
                }
                guard transaction.productID == PurchaseConfiguration.unlimitedProductID else {
                    errorMessage = String(localized: "購入した商品を確認できませんでした。")
                    return .cancelled
                }
                isUnlocked = transaction.revocationDate == nil
                hasCheckedEntitlements = true
                await transaction.finish()
                return isUnlocked ? .purchased : .cancelled
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            errorMessage = String(localized: "購入を完了できませんでした。もう一度お試しください。")
            return .cancelled
        }
    }

    func restore() async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return isUnlocked
        } catch {
            errorMessage = String(localized: "購入を復元できませんでした。通信状態を確認して、もう一度お試しください。")
            return false
        }
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == PurchaseConfiguration.unlimitedProductID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isUnlocked = entitled
        hasCheckedEntitlements = true
    }

    func clearError() {
        errorMessage = nil
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                if transaction.productID == PurchaseConfiguration.unlimitedProductID {
                    await self?.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
    }
}
