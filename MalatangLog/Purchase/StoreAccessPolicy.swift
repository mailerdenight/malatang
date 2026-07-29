import Foundation

enum StoreAccessPolicy {
    static let freeStoreLimit = PurchaseConfiguration.freeStoreLimit

    /// 保存後の訪問店舗数が無料枠を超えるか判定する。
    /// 店舗未設定の記録や、すでに訪問済みの店舗への追加記録は無料枠を消費しない。
    static func requiresUnlock(
        isUnlocked: Bool,
        visitedStoreIDs: Set<UUID>,
        selectedStoreID: UUID?
    ) -> Bool {
        guard isUnlocked == false, let selectedStoreID else { return false }
        return visitedStoreIDs.union([selectedStoreID]).count > freeStoreLimit
    }

    static func remainingFreeStores(visitedStoreCount: Int) -> Int {
        max(freeStoreLimit - visitedStoreCount, 0)
    }
}
