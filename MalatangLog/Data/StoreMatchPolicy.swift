import CoreLocation
import Foundation

/// 店名だけで離れた支店を同一視せず、安全に既存店舗を再利用するための共通ポリシー。
enum StoreMatchPolicy {
    static let maximumMatchDistance: CLLocationDistance = 50

    /// 緯度・経度がペアで揃い、Core Location で有効な場合だけ返す。
    static func validCoordinate(
        latitude: Double?,
        longitude: Double?
    ) -> CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              latitude.isFinite, longitude.isFinite else {
            return nil
        }
        let coordinate = CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    /// 最も安全に同一店舗と判定できる候補を返す。
    ///
    /// - 入力と候補の両方に有効な座標がある場合は、50m以内かつ同名の店舗だけを再利用する。
    /// - 離れた同名店は、別の支店として扱う。
    /// - 座標のない過去データは、住所が一致するか候補が一意な場合に限って再利用する。
    static func bestMatch(
        name rawName: String,
        branch rawBranch: String = "",
        address rawAddress: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        among stores: [Store]
    ) -> Store? {
        let name = normalize(rawName)
        guard name.isEmpty == false else { return nil }
        let branch = normalize(rawBranch)
        let address = normalize(rawAddress)

        let nameMatches = stores.filter {
            matchesName($0, name: name, branch: branch)
        }
        guard nameMatches.isEmpty == false else { return nil }

        if let incomingCoordinate = validCoordinate(
            latitude: latitude,
            longitude: longitude
        ) {
            let incomingLocation = CLLocation(
                latitude: incomingCoordinate.latitude,
                longitude: incomingCoordinate.longitude
            )
            let nearby = nameMatches.compactMap { store -> (Store, CLLocationDistance)? in
                guard let coordinate = validCoordinate(
                    latitude: store.latitude,
                    longitude: store.longitude
                ) else {
                    return nil
                }
                let distance = incomingLocation.distance(
                    from: CLLocation(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                )
                guard distance <= maximumMatchDistance else { return nil }
                return (store, distance)
            }

            if let closest = nearby.min(by: { $0.1 < $1.1 }) {
                return closest.0
            }

            // 座標つきの同名店が離れた場所にあるなら、店名だけでは統合しない。
            // 座標なし候補の住所が一致する場合だけは、安全に補完できる。
            let withoutCoordinate = nameMatches.filter {
                validCoordinate(latitude: $0.latitude, longitude: $0.longitude) == nil
            }
            if let addressMatch = uniqueAddressMatch(
                address: address,
                among: withoutCoordinate
            ) {
                return addressMatch
            }
            if nameMatches.count == 1,
               let only = withoutCoordinate.first,
               addressesAreCompatible(address, normalize(only.address)) {
                return only
            }
            return nil
        }

        return safeMatchWithoutCoordinate(
            address: address,
            among: nameMatches
        )
    }

    private static func safeMatchWithoutCoordinate(
        address: String,
        among stores: [Store]
    ) -> Store? {
        if let addressMatch = uniqueAddressMatch(address: address, among: stores) {
            return addressMatch
        }
        guard stores.count == 1, let only = stores.first else { return nil }
        return addressesAreCompatible(address, normalize(only.address)) ? only : nil
    }

    private static func uniqueAddressMatch(
        address: String,
        among stores: [Store]
    ) -> Store? {
        guard address.isEmpty == false else { return nil }
        let matches = stores.filter {
            let candidateAddress = normalize($0.address)
            return candidateAddress.isEmpty == false
                && sameText(candidateAddress, address)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func addressesAreCompatible(_ lhs: String, _ rhs: String) -> Bool {
        lhs.isEmpty || rhs.isEmpty || sameText(lhs, rhs)
    }

    private static func matchesName(
        _ store: Store,
        name: String,
        branch: String
    ) -> Bool {
        let requestedDisplayName = displayName(name: name, branch: branch)
        return sameText(normalize(store.displayName), requestedDisplayName)
            || (sameText(normalize(store.name), name)
                && sameText(normalize(store.branch), branch))
    }

    private static func displayName(name: String, branch: String) -> String {
        branch.isEmpty ? name : "\(name) \(branch)"
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{3000}", with: " ")
    }

    private static func sameText(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(
            rhs,
            options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }
}
