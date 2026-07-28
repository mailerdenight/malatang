import SwiftUI
import SwiftData
import MapKit
import Combine

struct NearbyMapView: View {
    @Environment(\.modelContext) private var context
    @Query private var stores: [Store]

    @StateObject private var location = LocationProvider()
    @State private var search = StoreSearchService()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedResult: StoreSearchResult?
    @State private var recordStore: Store?
    @State private var showingRecordEditor = false
    @State private var favorites = FavoriteStoreService.shared

    private var results: [StoreSearchResult] {
        if case .results(let items) = search.state { return items }
        return []
    }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(resultsWithCoordinates) { result in
                    Annotation(result.name, coordinate: result.coordinate!, anchor: .bottom) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedResult = result
                            }
                        } label: {
                            mapPin(for: result)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isVisited(result) ? "\(result.name)、訪問済み" : result.name
                        )
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.restaurant])))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .overlay(alignment: .top) {
                statusBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            .safeAreaInset(edge: .bottom) {
                if let selectedResult {
                    storeCard(selectedResult)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("近くの麻辣湯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("周辺を再検索")
                }
            }
            .sheet(isPresented: $showingRecordEditor) {
                RecordEditorView(mode: .create, initialStore: recordStore)
            }
            .task {
                startLocationFlow()
            }
            .onReceive(location.$currentLocation.compactMap { $0 }) { currentLocation in
                searchAround(currentLocation)
            }
        }
    }

    private var resultsWithCoordinates: [StoreSearchResult] {
        results.filter { $0.coordinate != nil }
    }

    private func mapPin(for result: StoreSearchResult) -> some View {
        ZStack {
            Circle()
                .fill(isVisited(result) ? Theme.primary : Color.accentColor)
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            Image(systemName: isVisited(result) ? "flame.fill" : "mappin")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay {
            if selectedResult?.id == result.id {
                Circle().stroke(.white, lineWidth: 3)
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch search.state {
        case .searching:
            Label("3km圏内を検索中…", systemImage: "location.magnifyingglass")
                .statusCapsule()
        case .empty:
            Label("3km圏内に店舗が見つかりませんでした", systemImage: "mappin.slash")
                .statusCapsule()
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .statusCapsule()
        case .results(let items):
            Label("\(items.count)店を表示", systemImage: "mappin.and.ellipse")
                .statusCapsule()
        case .idle:
            if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Label("位置情報を許可すると近くのお店を表示します", systemImage: "location.slash")
                    .statusCapsule()
            }
        }
    }

    private func storeCard(_ result: StoreSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 8) {
                        if let distance = result.distance(from: location.currentLocation) {
                            Label(distanceText(distance), systemImage: "figure.walk")
                        }
                        Label(
                            isVisited(result) ? "訪問済み" : "未訪問",
                            systemImage: isVisited(result) ? "flame.fill" : "mappin"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
                }
                Spacer()
                Button {
                    selectedResult = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.subtleText)
                }
                .accessibilityLabel("閉じる")
            }

            if result.address.isEmpty == false {
                Text(result.address)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
                    .lineLimit(2)
            }

            Label("営業時間は地図で確認", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(Theme.subtleText)

            HStack(spacing: 8) {
                Button {
                    openGoogleMaps(result)
                } label: {
                    Label("Googleマップ", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    toggleFavorite(result)
                } label: {
                    Image(systemName: isFavorite(result) ? "star.fill" : "star")
                        .frame(minWidth: 24)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .accessibilityLabel(isFavorite(result) ? "お気に入りから外す" : "お気に入りに追加")

                Button {
                    startRecord(result)
                } label: {
                    Label("記録する", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    private func startLocationFlow() {
        if location.isUndetermined {
            location.requestAuthorization()
        } else if location.isAuthorized {
            location.requestOneShotLocation()
        }
    }

    private func refresh() {
        selectedResult = nil
        if location.isAuthorized {
            location.requestOneShotLocation()
            if let currentLocation = location.currentLocation {
                searchAround(currentLocation)
            }
        } else if location.isUndetermined {
            location.requestAuthorization()
        }
    }

    private func searchAround(_ currentLocation: CLLocation) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: currentLocation.coordinate,
                latitudinalMeters: 6_000,
                longitudinalMeters: 6_000
            )
        )
        search.searchNearby(coordinate: currentLocation.coordinate)
    }

    private func existingStore(for result: StoreSearchResult) -> Store? {
        if let exact = stores.first(where: {
            MasterService.isSameName($0.displayName, result.name)
                || MasterService.isSameName($0.name, result.name)
        }) {
            return exact
        }
        guard let coordinate = result.coordinate else { return nil }
        let resultLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return stores.first { store in
            guard let latitude = store.latitude, let longitude = store.longitude else { return false }
            return resultLocation.distance(
                from: CLLocation(latitude: latitude, longitude: longitude)
            ) < 120
        }
    }

    private func savedStore(for result: StoreSearchResult) -> Store? {
        if let existing = existingStore(for: result) { return existing }
        let store = MasterService.findOrCreateStore(
            name: result.name,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            in: context
        )
        try? context.save()
        return store
    }

    private func isVisited(_ result: StoreSearchResult) -> Bool {
        guard let store = existingStore(for: result) else { return false }
        return store.servings.contains { SampleDataService.isSample($0) == false }
    }

    private func isFavorite(_ result: StoreSearchResult) -> Bool {
        favorites.contains(existingStore(for: result))
    }

    private func toggleFavorite(_ result: StoreSearchResult) {
        guard let store = savedStore(for: result) else { return }
        favorites.toggle(store)
    }

    private func startRecord(_ result: StoreSearchResult) {
        guard let store = savedStore(for: result) else { return }
        recordStore = store
        showingRecordEditor = true
    }

    private func openGoogleMaps(_ result: StoreSearchResult) {
        let destination: MapLauncher.Destination
        if let latitude = result.latitude, let longitude = result.longitude {
            destination = .coordinate(latitude: latitude, longitude: longitude, label: result.name)
        } else {
            destination = .query([result.name, result.address].joined(separator: " "))
        }
        MapLauncher.openMap(destination, using: .google)
    }

    private func distanceText(_ distance: CLLocationDistance) -> String {
        if distance < 1_000 {
            return "\(Int(distance.rounded()))m"
        }
        return String(format: "%.1fkm", distance / 1_000)
    }
}

private extension View {
    func statusCapsule() -> some View {
        font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }
}
