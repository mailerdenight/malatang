import Foundation

@Observable
final class FavoriteStoreService {
    static let shared = FavoriteStoreService()

    private static let defaultsKey = "favoriteStoreUUIDs"
    private(set) var ids: Set<UUID>

    private init() {
        let values = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        ids = Set(values.compactMap(UUID.init(uuidString:)))
    }

    func contains(_ store: Store?) -> Bool {
        guard let store else { return false }
        return ids.contains(store.uuid)
    }

    func toggle(_ store: Store) {
        set(store, isFavorite: ids.contains(store.uuid) == false)
    }

    func set(_ store: Store, isFavorite: Bool) {
        if isFavorite {
            ids.insert(store.uuid)
        } else {
            ids.remove(store.uuid)
        }
        persist()
    }

    func removeAll() {
        ids.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: Self.defaultsKey)
    }
}
