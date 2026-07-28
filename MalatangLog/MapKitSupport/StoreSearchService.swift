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
    private var currentSearch: MKLocalSearch?

    /// 麻辣湯の店を探しやすいよう、既定のキーワードを補う。
    static let defaultKeyword = "麻辣湯"

    func searchNearby(coordinate: CLLocationCoordinate2D, keyword: String = defaultKeyword) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3_000,
            longitudinalMeters: 3_000
        )
        perform(
            keyword: keyword.isEmpty ? Self.defaultKeyword : keyword,
            region: region,
            center: coordinate,
            maximumDistance: 3_500
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
        perform(keyword: trimmed, region: region)
    }

    func cancel() {
        currentSearch?.cancel()
        currentSearch = nil
    }

    func reset() {
        cancel()
        state = .idle
    }

    private func perform(
        keyword: String,
        region: MKCoordinateRegion?,
        center: CLLocationCoordinate2D? = nil,
        maximumDistance: CLLocationDistance? = nil
    ) {
        cancel()
        state = .searching

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.resultTypes = [.pointOfInterest]
        if let region { request.region = region }

        let search = MKLocalSearch(request: request)
        currentSearch = search
        search.start { [weak self] response, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let response else {
                    self.state = .failed("店舗を検索できませんでした。通信状態と検索語を確認してください。")
                    return
                }
                let centerLocation = center.map {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                }
                let mapItems = response.mapItems.filter { item in
                    guard
                        let centerLocation,
                        let maximumDistance,
                        let resultLocation = item.placemark.location
                    else {
                        return true
                    }
                    return centerLocation.distance(from: resultLocation) <= maximumDistance
                }
                let items = mapItems.map { item -> StoreSearchResult in
                    StoreSearchResult(
                        name: item.name ?? "名称不明",
                        address: Self.formattedAddress(item.placemark),
                        latitude: item.placemark.location?.coordinate.latitude,
                        longitude: item.placemark.location?.coordinate.longitude
                    )
                }
                self.state = items.isEmpty ? .empty : .results(items)
            }
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
