import Foundation
import SwiftData

@Model
final class Store {
    var uuid: UUID = UUID()
    var name: String = ""
    var branch: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Serving.store)
    var servings: [Serving] = []

    init(
        uuid: UUID = UUID(),
        name: String,
        branch: String = "",
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.branch = branch
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = Date()
    }
}

extension Store {
    var displayName: String {
        branch.isEmpty ? name : "\(name) \(branch)"
    }

    var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }

    var visitCount: Int { servings.count }

    /// サンプルを除く実際の記録が1件以上あれば訪問済み。
    var visited: Bool {
        servings.contains { SampleDataService.isSample($0) == false }
    }

    /// SwiftDataのスキーマを変えず、既存DB互換のまま端末内へ保存する。
    var favorite: Bool {
        get { FavoriteStoreService.shared.contains(self) }
        set { FavoriteStoreService.shared.set(self, isFavorite: newValue) }
    }

    var averageRating: Double? {
        let rated = servings.map(\.rating).filter { $0 > 0 }
        guard rated.isEmpty == false else { return nil }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    var averagePrice: Int? {
        let prices = servings.compactMap(\.priceYen)
        guard prices.isEmpty == false else { return nil }
        return prices.reduce(0, +) / prices.count
    }

    var lastVisit: Date? {
        servings.map(\.date).max()
    }
}
