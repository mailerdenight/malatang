import Foundation
import MapKit

struct StoreSearchResult: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?

    init(
        name: String,
        address: String,
        latitude: Double?,
        longitude: Double?
    ) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        id = Self.stableID(
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude
        )
    }

    static func stableID(
        name: String,
        address: String,
        latitude: Double?,
        longitude: Double?
    ) -> String {
        let normalizedName = normalizedIdentityComponent(name)
        if let latitude, let longitude {
            let coordinateKey = String(
                format: "%.5f|%.5f",
                locale: identityLocale,
                latitude,
                longitude
            )
            return "\(normalizedName)|\(coordinateKey)"
        }
        let normalizedAddress = normalizedIdentityComponent(address)
        return "\(normalizedName)|\(normalizedAddress)"
    }

    static func normalizedIdentityComponent(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: identityLocale
            )
            .lowercased(with: identityLocale)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static let identityLocale = Locale(identifier: "en_US_POSIX")

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    func distance(from location: CLLocation?) -> CLLocationDistance? {
        guard let coordinate, let location else { return nil }
        return location.distance(
            from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    /// 「渋谷店」のような支店名をざっくり切り出す。確証がなければ空にする。
    var inferredBranch: String {
        guard let range = name.range(of: "　") ?? name.range(of: " ") else { return "" }
        return String(name[range.upperBound...])
    }
}

@Observable
final class StoreSearchService {

    enum State: Equatable {
        case idle
        case searching
        case results([StoreSearchResult])
        case empty
        case failed(String)
    }

    private(set) var state: State = .idle
    /// 再検索中も直前のピンを維持するため、表示用の結果を状態とは分けて保持する。
    private(set) var results: [StoreSearchResult] = []
    private var currentSearches: [MKLocalSearch] = []
    private var searchGeneration = UUID()

    /// 自動検索では普遍的な表記に端末言語の現地表記だけを足し、過剰な並列検索を避ける。
    static let defaultKeyword = "麻辣湯"
    static let defaultKeywords = [
        "malatang",
        "mala tang",
        "麻辣烫",
        "麻辣燙",
        "麻辣湯"
    ]
    static let maximumSearchDistance: CLLocationDistance = 25_000
    static let duplicateCoordinateTolerance: CLLocationDistance = 25

    func searchNearby(coordinate: CLLocationCoordinate2D, keyword: String? = nil) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3_000,
            longitudinalMeters: 3_000
        )
        perform(
            keywords: Self.keywords(for: keyword),
            region: region,
            center: coordinate,
            maximumDistance: 3_500
        )
    }

    /// ユーザーが移動・拡大縮小した現在の地図範囲を中心に検索し直す。
    func searchVisibleRegion(
        _ region: MKCoordinateRegion,
        keyword: String? = nil
    ) {
        let center = region.center

        perform(
            keywords: Self.keywords(for: keyword),
            region: Self.clampedRegion(region),
            center: center,
            maximumDistance: Self.searchRadius(for: region)
        )
    }

    func search(keyword: String, near coordinate: CLLocationCoordinate2D? = nil) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            results = []
            state = .idle
            return
        }
        let region: MKCoordinateRegion?
        if let coordinate {
            region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: Self.maximumSearchDistance * 2,
                longitudinalMeters: Self.maximumSearchDistance * 2
            )
        } else {
            region = nil
        }
        perform(
            keywords: [trimmed],
            region: region,
            center: coordinate,
            maximumDistance: coordinate == nil ? nil : Self.maximumSearchDistance
        )
    }

    func cancel() {
        currentSearches.forEach { $0.cancel() }
        currentSearches.removeAll()
        searchGeneration = UUID()
    }

    func reset() {
        cancel()
        results = []
        state = .idle
    }

    private func perform(
        keywords: [String],
        region: MKCoordinateRegion?,
        center: CLLocationCoordinate2D? = nil,
        maximumDistance: CLLocationDistance? = nil
    ) {
        cancel()
        guard keywords.isEmpty == false else {
            results = []
            state = .idle
            return
        }
        state = .searching

        let generation = UUID()
        searchGeneration = generation
        var remaining = keywords.count
        var receivedResponse = false
        var collectedMapItems = Array(repeating: [MKMapItem](), count: keywords.count)

        for (index, keyword) in keywords.enumerated() {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = keyword
            request.resultTypes = [.pointOfInterest]
            if let region { request.region = region }

            let search = MKLocalSearch(request: request)
            currentSearches.append(search)
            search.start { [weak self] response, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.searchGeneration == generation else { return }
                    if let response {
                        receivedResponse = true
                        collectedMapItems[index] = response.mapItems
                    }
                    remaining -= 1
                    guard remaining == 0 else { return }

                    self.currentSearches.removeAll()
                    guard receivedResponse else {
                        self.state = .failed(
                            String(localized: "店舗を検索できませんでした。通信状態と検索語を確認してください。")
                        )
                        return
                    }
                    let items = Self.makeResults(
                        from: collectedMapItems.flatMap { $0 },
                        center: center,
                        maximumDistance: maximumDistance
                    )
                    self.results = items
                    self.state = items.isEmpty ? .empty : .results(items)
                }
            }
        }
    }

    /// nilは自動周辺検索、値ありはユーザーが明示した単一検索語として扱う。
    static func keywords(for keyword: String?) -> [String] {
        guard let keyword else {
            return automaticKeywords(
                preferredLanguageIdentifier: Bundle.main.preferredLocalizations.first ?? "en"
            )
        }
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    static func automaticKeywords(preferredLanguageIdentifier: String) -> [String] {
        let localKeyword: String?
        switch preferredLanguageIdentifier {
        case let language where language.hasPrefix("ja"):
            localKeyword = "マーラータン"
        case let language where language.hasPrefix("ko"):
            localKeyword = "마라탕"
        case let language where language.hasPrefix("vi"):
            localKeyword = "lẩu mala"
        case let language where language.hasPrefix("th"):
            localKeyword = "หม่าล่าทั่ง"
        default:
            localKeyword = nil
        }
        return defaultKeywords + [localKeyword].compactMap { $0 }
    }

    static func makeResults(
        from mapItems: [MKMapItem],
        center: CLLocationCoordinate2D?,
        maximumDistance: CLLocationDistance?
    ) -> [StoreSearchResult] {
        let centerLocation = center.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        let candidates = mapItems.compactMap { item -> StoreSearchResult? in
            if let centerLocation,
               let maximumDistance,
               let resultLocation = item.placemark.location,
               centerLocation.distance(from: resultLocation) > maximumDistance {
                return nil
            }

            let name = item.name ?? String(localized: "名称不明")
            let address = MapAddressFormatter.string(from: item.placemark)
            let coordinate = item.placemark.location?.coordinate
            return StoreSearchResult(
                name: name,
                address: address,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            )
        }
        let results = removingDuplicates(from: candidates)

        guard let centerLocation else { return results }
        return results.sorted {
            let lhs = $0.coordinate.map {
                centerLocation.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            } ?? .greatestFiniteMagnitude
            let rhs = $1.coordinate.map {
                centerLocation.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            } ?? .greatestFiniteMagnitude
            return lhs < rhs
        }
    }

    static func removingDuplicates(
        from candidates: [StoreSearchResult]
    ) -> [StoreSearchResult] {
        var seenIDs = Set<String>()
        var unique: [StoreSearchResult] = []

        for candidate in candidates {
            guard seenIDs.insert(candidate.id).inserted else { continue }
            guard unique.contains(where: { likelySamePlace($0, candidate) }) == false else {
                continue
            }
            unique.append(candidate)
        }
        return unique
    }

    static func likelySamePlace(
        _ lhs: StoreSearchResult,
        _ rhs: StoreSearchResult
    ) -> Bool {
        if lhs.id == rhs.id { return true }

        let sameName = StoreSearchResult.normalizedIdentityComponent(lhs.name)
            == StoreSearchResult.normalizedIdentityComponent(rhs.name)
        guard let lhsCoordinate = lhs.coordinate,
              let rhsCoordinate = rhs.coordinate else {
            let lhsAddress = StoreSearchResult.normalizedIdentityComponent(lhs.address)
            let rhsAddress = StoreSearchResult.normalizedIdentityComponent(rhs.address)
            return sameName && lhsAddress.isEmpty == false && lhsAddress == rhsAddress
        }

        let distance = CLLocation(
            latitude: lhsCoordinate.latitude,
            longitude: lhsCoordinate.longitude
        ).distance(from: CLLocation(
            latitude: rhsCoordinate.latitude,
            longitude: rhsCoordinate.longitude
        ))

        return sameName && distance <= duplicateCoordinateTolerance
    }

    static func clampedRegion(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        let maximumDiameter = maximumSearchDistance * 2
        let dimensions = estimatedDimensions(of: region)

        return MKCoordinateRegion(
            center: region.center,
            latitudinalMeters: min(dimensions.height, maximumDiameter),
            longitudinalMeters: min(dimensions.width, maximumDiameter)
        )
    }

    static func searchRadius(for region: MKCoordinateRegion) -> CLLocationDistance {
        let dimensions = estimatedDimensions(of: region)
        return min(
            hypot(dimensions.height / 2, dimensions.width / 2) * 1.15,
            maximumSearchDistance
        )
    }

    private static func estimatedDimensions(
        of region: MKCoordinateRegion
    ) -> (height: CLLocationDistance, width: CLLocationDistance) {
        let latitudeDelta = min(abs(region.span.latitudeDelta), 180)
        let longitudeDelta = min(abs(region.span.longitudeDelta), 360)
        let latitudeRadians = region.center.latitude * .pi / 180
        let metersPerLongitudeDegree = 111_320 * max(abs(cos(latitudeRadians)), 0.000_001)

        return (
            height: max(latitudeDelta * 111_132, 1),
            width: max(longitudeDelta * metersPerLongitudeDegree, 1)
        )
    }

    /// 旧APIを呼ぶ箇所とテストの互換用。
    static func formattedAddress(_ placemark: MKPlacemark) -> String {
        MapAddressFormatter.string(from: placemark)
    }
}
