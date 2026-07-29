import Foundation
import MapKit

struct StoreSearchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
    private var currentSearches: [MKLocalSearch] = []
    private var searchGeneration = UUID()

    /// 漢字名とカタカナ名の両方を検索し、表記が違う店舗も拾う。
    static let defaultKeyword = "麻辣湯"
    static let defaultKeywords = ["麻辣湯", "マーラータン"]

    func searchNearby(coordinate: CLLocationCoordinate2D, keyword: String = defaultKeyword) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3_000,
            longitudinalMeters: 3_000
        )
        perform(
            keywords: keywords(for: keyword),
            region: region,
            center: coordinate,
            maximumDistance: 3_500
        )
    }

    /// ユーザーが移動・拡大縮小した現在の地図範囲を中心に検索し直す。
    func searchVisibleRegion(
        _ region: MKCoordinateRegion,
        keyword: String = defaultKeyword
    ) {
        let center = region.center
        let northEdge = CLLocation(
            latitude: center.latitude + region.span.latitudeDelta / 2,
            longitude: center.longitude
        )
        let eastEdge = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude + region.span.longitudeDelta / 2
        )
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let radius = hypot(
            centerLocation.distance(from: northEdge),
            centerLocation.distance(from: eastEdge)
        ) * 1.15

        perform(
            keywords: keywords(for: keyword),
            region: region,
            center: center,
            maximumDistance: radius
        )
    }

    func search(keyword: String, near coordinate: CLLocationCoordinate2D? = nil) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            state = .idle
            return
        }
        let region: MKCoordinateRegion?
        if let coordinate {
            region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        } else {
            region = nil
        }
        perform(keywords: keywords(for: trimmed), region: region)
    }

    func cancel() {
        currentSearches.forEach { $0.cancel() }
        currentSearches.removeAll()
        searchGeneration = UUID()
    }

    func reset() {
        cancel()
        state = .idle
    }

    private func perform(
        keywords: [String],
        region: MKCoordinateRegion?,
        center: CLLocationCoordinate2D? = nil,
        maximumDistance: CLLocationDistance? = nil
    ) {
        cancel()
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
                        self.state = .failed("店舗を検索できませんでした。通信状態と検索語を確認してください。")
                        return
                    }
                    let items = Self.makeResults(
                        from: collectedMapItems.flatMap { $0 },
                        center: center,
                        maximumDistance: maximumDistance
                    )
                    self.state = items.isEmpty ? .empty : .results(items)
                }
            }
        }
    }

    private func keywords(for keyword: String) -> [String] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.defaultKeyword {
            return Self.defaultKeywords
        }
        return [trimmed]
    }

    private static func makeResults(
        from mapItems: [MKMapItem],
        center: CLLocationCoordinate2D?,
        maximumDistance: CLLocationDistance?
    ) -> [StoreSearchResult] {
        let centerLocation = center.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        var seen = Set<String>()

        let results = mapItems.compactMap { item -> StoreSearchResult? in
            if let centerLocation,
               let maximumDistance,
               let resultLocation = item.placemark.location,
               centerLocation.distance(from: resultLocation) > maximumDistance {
                return nil
            }

            let name = item.name ?? "名称不明"
            let address = formattedAddress(item.placemark)
            let coordinate = item.placemark.location?.coordinate
            let normalizedName = name.folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: .current
            )
            let normalizedAddress = address.folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: .current
            )
            let locationFallback = [
                coordinate.map { String(format: "%.5f", $0.latitude) } ?? "",
                coordinate.map { String(format: "%.5f", $0.longitude) } ?? ""
            ].joined(separator: "|")
            let key = normalizedAddress.isEmpty
                ? "\(normalizedName)|\(locationFallback)"
                : "\(normalizedName)|\(normalizedAddress)"
            guard seen.insert(key).inserted else { return nil }

            return StoreSearchResult(
                name: name,
                address: address,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            )
        }

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

    static func formattedAddress(_ placemark: MKPlacemark) -> String {
        var parts: [String] = []
        if let administrativeArea = placemark.administrativeArea { parts.append(administrativeArea) }
        if let locality = placemark.locality { parts.append(locality) }
        if let subLocality = placemark.subLocality { parts.append(subLocality) }
        if let thoroughfare = placemark.thoroughfare { parts.append(thoroughfare) }
        if let subThoroughfare = placemark.subThoroughfare { parts.append(subThoroughfare) }
        let joined = parts.joined()
        return joined.isEmpty ? (placemark.title ?? "") : joined
    }
}
