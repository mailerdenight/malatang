import SwiftUI
import SwiftData
import MapKit
import Combine
import UIKit

struct NearbyMapView: View {
    @Environment(\.modelContext) private var context
    @Query private var stores: [Store]

    @StateObject private var location = LocationProvider()
    @State private var search = StoreSearchService()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedResultID: StoreSearchResult.ID?
    @State private var recordStore: Store?
    @State private var showingRecordEditor = false
    @State private var favorites = FavoriteStoreService.shared
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var lastSearchedRegion: MKCoordinateRegion?
    @State private var searchRegionNeedsRefresh = false
    @State private var isChoosingManualLocation = false
    @State private var showingManualStore = false
    @State private var manualCoordinate: CLLocationCoordinate2D?
    @State private var pendingManualRecordStore: Store?
    @State private var mapQuery = ""
    @State private var shouldFrameKeywordResults = false
    @State private var didHandleInitialLocation = false
    @State private var keywordLocationFallback: String?
    @State private var isResolvingSearchLocation = false
    @State private var keywordSearchGeneration = UUID()
    @State private var mapSaveErrorMessage: String?

    private var results: [StoreSearchResult] {
        MapDisplayPolicy.mergedResults(
            searchResults: search.results,
            savedStores: stores
        )
    }

    private var selectedResult: StoreSearchResult? {
        NearbyMapSelectionPolicy.selectedResult(
            id: selectedResultID,
            in: results
        )
    }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(resultsWithCoordinates) { result in
                    Annotation(result.name, coordinate: result.coordinate!, anchor: .bottom) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedResultID = result.id
                            }
                        } label: {
                            mapPin(for: result)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isVisited(result)
                                ? String(localized: "\(result.name)、訪問済み")
                                : result.name
                        )
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { mapContext in
                visibleRegion = mapContext.region
                if cameraPosition.positionedByUser {
                    shouldFrameKeywordResults = false
                    keywordLocationFallback = nil
                    keywordSearchGeneration = UUID()
                    if NearbyMapSearchPolicy.hasMeaningfulMapChange(
                        from: lastSearchedRegion,
                        to: mapContext.region
                    ) {
                        selectedResultID = nil
                        searchRegionNeedsRefresh = true
                    }
                }
            }
            .overlay {
                if isChoosingManualLocation {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .offset(y: -22)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                topBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            .overlay(alignment: .bottom) {
                if isChoosingManualLocation {
                    manualLocationCard
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let selectedResult {
                    storeCard(selectedResult)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("近くの麻辣湯")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $mapQuery, prompt: "店名・都市名で検索")
            .onSubmit(of: .search) {
                searchByKeyword()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        beginManualLocationSelection()
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .accessibilityLabel("地図上の場所に店舗を追加")
                }
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
            .sheet(
                isPresented: $showingManualStore,
                onDismiss: continueToManualRecordIfNeeded
            ) {
                if let manualCoordinate {
                    ManualMapStoreView(coordinate: manualCoordinate) { store in
                        pendingManualRecordStore = store
                    }
                }
            }
            .alert(
                "店舗を保存できませんでした",
                isPresented: Binding(
                    get: { mapSaveErrorMessage != nil },
                    set: { if $0 == false { mapSaveErrorMessage = nil } }
                )
            ) {
                Button("閉じる", role: .cancel) { mapSaveErrorMessage = nil }
            } message: {
                Text(mapSaveErrorMessage ?? "")
            }
            .task {
                startLocationFlow()
            }
            .onReceive(location.$currentLocation.compactMap { $0 }) { currentLocation in
                guard didHandleInitialLocation == false else { return }
                didHandleInitialLocation = true
                if MasterService.normalize(mapQuery).isEmpty {
                    searchAround(currentLocation)
                }
            }
            .onChange(of: search.state) { _, state in
                guard shouldFrameKeywordResults else { return }
                switch state {
                case .results(let items):
                    shouldFrameKeywordResults = false
                    keywordLocationFallback = nil
                    frameSearchResults(items)
                case .empty:
                    shouldFrameKeywordResults = false
                    if let keyword = keywordLocationFallback {
                        let generation = keywordSearchGeneration
                        keywordLocationFallback = nil
                        Task {
                            await moveToLocationAndSearch(
                                keyword,
                                generation: generation
                            )
                        }
                    }
                case .failed:
                    shouldFrameKeywordResults = false
                    keywordLocationFallback = nil
                case .idle, .searching:
                    break
                }
            }
        }
    }

    private var resultsWithCoordinates: [StoreSearchResult] {
        results.filter { $0.coordinate != nil }
    }

    private var visibleResultCount: Int {
        guard let visibleRegion else { return resultsWithCoordinates.count }
        return resultsWithCoordinates.lazy.filter { result in
            guard let coordinate = result.coordinate else { return false }
            return NearbyMapSearchPolicy.contains(coordinate, in: visibleRegion)
        }.count
    }

    private func mapPin(for result: StoreSearchResult) -> some View {
        ZStack {
            Circle()
                .fill(isVisited(result) ? Theme.primary : Color.accentColor)
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            Image(systemName: isVisited(result) ? "flame.fill" : "mappin")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            if selectedResultID == result.id {
                Circle()
                    .stroke(.white, lineWidth: 3)
                    .frame(width: 42, height: 42)
            }
            if isFavorite(result) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.accent, in: Circle())
                    .offset(x: 16, y: -16)
            }
        }
        .frame(width: 48, height: 48)
        .contentShape(Circle())
    }

    @ViewBuilder
    private var topBanner: some View {
        if isResolvingSearchLocation {
            Label("都市・住所を確認しています…", systemImage: "location.magnifyingglass")
                .statusCapsule()
        } else if searchRegionNeedsRefresh, isChoosingManualLocation == false {
            Button {
                searchCurrentRegion()
            } label: {
                Label("このエリアを検索", systemImage: "magnifyingglass")
                    .statusCapsule()
            }
            .buttonStyle(.plain)
        } else if isChoosingManualLocation == false,
                  searchShowsRecoveryAction {
            VStack(spacing: 8) {
                statusBanner
                Button {
                    beginManualLocationSelection()
                } label: {
                    Label("この場所に店舗を追加", systemImage: "mappin.and.ellipse")
                        .statusCapsule()
                }
                .buttonStyle(.plain)
                if location.authorizationStatus == .denied
                    || location.authorizationStatus == .restricted {
                    Button {
                        openAppSettings()
                    } label: {
                        Label("位置情報の設定を開く", systemImage: "gear")
                            .statusCapsule()
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if isChoosingManualLocation == false,
                  location.authorizationStatus == .denied
                    || location.authorizationStatus == .restricted {
            VStack(spacing: 8) {
                statusBanner
                Button {
                    openAppSettings()
                } label: {
                    Label("設定を開く", systemImage: "gear")
                        .statusCapsule()
                }
                .buttonStyle(.plain)
            }
        } else {
            statusBanner
        }
    }

    private var searchShowsRecoveryAction: Bool {
        switch search.state {
        case .empty, .failed:
            return visibleRegion != nil
        case .results:
            return visibleRegion != nil && visibleResultCount == 0
        case .idle, .searching:
            return false
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch search.state {
        case .searching:
            Label("表示範囲を検索中…", systemImage: "location.magnifyingglass")
                .statusCapsule()
        case .empty:
            if visibleResultCount == 0 {
                Label("表示範囲に店舗が見つかりませんでした", systemImage: "mappin.slash")
                    .statusCapsule()
            } else {
                Label("保存済みの\(visibleResultCount)店を表示", systemImage: "bookmark.fill")
                    .statusCapsule()
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .statusCapsule()
        case .results:
            if visibleResultCount == 0 {
                Label("表示範囲に店舗が見つかりませんでした", systemImage: "mappin.slash")
                    .statusCapsule()
            } else {
                Label("\(visibleResultCount)店を表示", systemImage: "mappin.and.ellipse")
                    .statusCapsule()
            }
        case .idle:
            if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Label("位置情報を許可すると近くのお店を表示します", systemImage: "location.slash")
                    .statusCapsule()
            }
        }
    }

    private var manualLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ピンを店舗の位置に合わせてください", systemImage: "hand.draw")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Text("地図を動かしてから、この場所を選びます。Appleの検索にない店舗も座標付きで記録できます。")
                .font(.caption)
                .foregroundStyle(Theme.subtleText)

            HStack(spacing: 8) {
                Button("キャンセル") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isChoosingManualLocation = false
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    confirmManualLocation()
                } label: {
                    Label("この場所を選ぶ", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(visibleRegion == nil)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    private func storeCard(_ result: StoreSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: result.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 8) {
                        if let distance = result.distance(from: location.currentLocation) {
                            Label(distanceText(distance), systemImage: "figure.walk")
                        }
                        Label(
                            AppLocalization.string(isVisited(result) ? "訪問済み" : "未訪問"),
                            systemImage: isVisited(result) ? "flame.fill" : "mappin"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
                }
                Spacer()
                Button {
                    selectedResultID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.subtleText)
                }
                .accessibilityLabel("閉じる")
            }

            if result.address.isEmpty == false {
                Text(verbatim: result.address)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
                    .lineLimit(2)
            }

            Label("営業時間は地図で確認", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(Theme.subtleText)

            HStack(spacing: 8) {
                Menu {
                    ForEach(MapLauncher.Provider.allCases) { provider in
                        Button {
                            openMap(result, using: provider)
                        } label: {
                            Label(provider.title, systemImage: provider.symbol)
                        }
                    }
                } label: {
                    Label("地図で開く", systemImage: "arrow.up.right.square")
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
        selectedResultID = nil
        if let visibleRegion {
            lastSearchedRegion = visibleRegion
            searchRegionNeedsRefresh = false
            search.searchVisibleRegion(visibleRegion)
        } else if location.isAuthorized {
            location.requestOneShotLocation()
            if let currentLocation = location.currentLocation {
                searchAround(currentLocation)
            }
        } else if location.isUndetermined {
            location.requestAuthorization()
        }
    }

    private func searchAround(_ currentLocation: CLLocation) {
        let region = MKCoordinateRegion(
            center: currentLocation.coordinate,
            latitudinalMeters: 6_000,
            longitudinalMeters: 6_000
        )
        visibleRegion = region
        lastSearchedRegion = region
        searchRegionNeedsRefresh = false
        cameraPosition = .region(region)
        search.searchVisibleRegion(region)
    }

    private func searchCurrentRegion() {
        guard let visibleRegion else { return }
        selectedResultID = nil
        lastSearchedRegion = visibleRegion
        searchRegionNeedsRefresh = false
        search.searchVisibleRegion(visibleRegion)
    }

    private func searchByKeyword() {
        let keyword = MasterService.normalize(mapQuery)
        guard keyword.isEmpty == false else { return }
        selectedResultID = nil
        searchRegionNeedsRefresh = false
        shouldFrameKeywordResults = false
        keywordLocationFallback = nil
        search.cancel()

        let generation = UUID()
        keywordSearchGeneration = generation
        Task {
            await resolveKeywordSearch(keyword, generation: generation)
        }
    }

    /// 「Da Nang」のような都市名は、同名POIではなくその都市の周辺検索として扱う。
    @MainActor
    private func resolveKeywordSearch(
        _ query: String,
        generation: UUID
    ) async {
        isResolvingSearchLocation = true
        defer {
            if generation == keywordSearchGeneration {
                isResolvingSearchLocation = false
            }
        }

        if let placemarks = try? await CLGeocoder().geocodeAddressString(
            query,
            in: nil,
            preferredLocale: MapSearchQueryPolicy.geocodingLocale(for: query)
        ),
           generation == keywordSearchGeneration,
           let placemark = placemarks.first(where: {
               MapSearchQueryPolicy.matchesGeographicName(
                   query,
                   candidates: [
                       $0.locality,
                       $0.subAdministrativeArea,
                       $0.administrativeArea,
                       $0.country
                   ]
               )
           }),
           let coordinate = placemark.location?.coordinate {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 10_000,
                longitudinalMeters: 10_000
            )
            visibleRegion = region
            lastSearchedRegion = region
            searchRegionNeedsRefresh = false
            cameraPosition = .region(region)
            search.searchVisibleRegion(region)
            return
        }

        guard generation == keywordSearchGeneration else { return }
        shouldFrameKeywordResults = true
        keywordLocationFallback = query
        search.search(keyword: query)
    }

    @MainActor
    private func moveToLocationAndSearch(
        _ query: String,
        generation: UUID
    ) async {
        isResolvingSearchLocation = true
        defer {
            if generation == keywordSearchGeneration {
                isResolvingSearchLocation = false
            }
        }
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(
                query,
                in: nil,
                preferredLocale: MapSearchQueryPolicy.geocodingLocale(for: query)
            )
            guard generation == keywordSearchGeneration else { return }
            guard let coordinate = placemarks.first?.location?.coordinate else { return }
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 10_000,
                longitudinalMeters: 10_000
            )
            visibleRegion = region
            lastSearchedRegion = region
            searchRegionNeedsRefresh = false
            cameraPosition = .region(region)
            search.searchVisibleRegion(region)
        } catch {
            // 都市・住所としても解決できなければ、空結果と手動追加導線を維持する。
        }
    }

    private func frameSearchResults(_ items: [StoreSearchResult]) {
        let coordinates = items.compactMap(\.coordinate)
        guard let first = coordinates.first else { return }
        let minimumLatitude = coordinates.map(\.latitude).min() ?? first.latitude
        let maximumLatitude = coordinates.map(\.latitude).max() ?? first.latitude
        let minimumLongitude = coordinates.map(\.longitude).min() ?? first.longitude
        let maximumLongitude = coordinates.map(\.longitude).max() ?? first.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.4, 0.02),
                longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.4, 0.02)
            )
        )
        lastSearchedRegion = region
        cameraPosition = .region(region)
    }

    private func existingStore(for result: StoreSearchResult) -> Store? {
        StoreMatchPolicy.bestMatch(
            name: result.name,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            among: stores
        )
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
        do {
            try context.save()
        } catch {
            context.rollback()
            mapSaveErrorMessage = String(localized: "端末内に店舗を保存できませんでした。空き容量を確認して、もう一度お試しください。")
            return nil
        }
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

    private func openMap(
        _ result: StoreSearchResult,
        using provider: MapLauncher.Provider
    ) {
        let destination: MapLauncher.Destination
        if let latitude = result.latitude, let longitude = result.longitude {
            destination = .coordinate(latitude: latitude, longitude: longitude, label: result.name)
        } else if result.address.isEmpty == false {
            destination = .query("\(result.name) \(result.address)")
        } else {
            destination = .query(result.name)
        }
        MapLauncher.openMap(destination, using: provider)
    }

    private func distanceText(_ distance: CLLocationDistance) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .short
        return formatter.string(
            from: Measurement(value: distance, unit: UnitLength.meters)
        )
    }

    private func beginManualLocationSelection() {
        selectedResultID = nil
        shouldFrameKeywordResults = false
        keywordLocationFallback = nil
        keywordSearchGeneration = UUID()
        isResolvingSearchLocation = false
        search.reset()
        withAnimation(.easeInOut(duration: 0.2)) {
            isChoosingManualLocation = true
        }
    }

    private func confirmManualLocation() {
        guard let coordinate = visibleRegion?.center,
              StoreMatchPolicy.validCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
              ) != nil else {
            return
        }
        manualCoordinate = coordinate
        isChoosingManualLocation = false
        showingManualStore = true
    }

    private func continueToManualRecordIfNeeded() {
        guard let store = pendingManualRecordStore else { return }
        pendingManualRecordStore = nil
        Task { @MainActor in
            // 先のシートが完全に閉じてから記録画面を提示する。
            await Task.yield()
            recordStore = store
            showingRecordEditor = true
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

enum NearbyMapSelectionPolicy {
    static func selectedResult(
        id: StoreSearchResult.ID?,
        in results: [StoreSearchResult]
    ) -> StoreSearchResult? {
        guard let id else { return nil }
        return results.first { $0.id == id }
    }
}

enum MapDisplayPolicy {
    static func mergedResults(
        searchResults: [StoreSearchResult],
        savedStores: [Store]
    ) -> [StoreSearchResult] {
        var merged = searchResults
        var seenIDs = Set(searchResults.map(\.id))
        for store in savedStores {
            guard let coordinate = StoreMatchPolicy.validCoordinate(
                latitude: store.latitude,
                longitude: store.longitude
            ) else {
                continue
            }
            let alreadyShown = searchResults.contains { result in
                StoreMatchPolicy.bestMatch(
                    name: result.name,
                    address: result.address,
                    latitude: result.latitude,
                    longitude: result.longitude,
                    among: [store]
                ) != nil
            }
            guard alreadyShown == false else { continue }
            let savedResult = StoreSearchResult(
                name: store.displayName,
                address: SampleDataService.displayAddress(for: store),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            guard seenIDs.insert(savedResult.id).inserted else { continue }
            merged.append(savedResult)
        }
        return merged
    }
}

enum NearbyMapSearchPolicy {
    static func contains(
        _ coordinate: CLLocationCoordinate2D,
        in region: MKCoordinateRegion
    ) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }

        let latitudeDistance = abs(coordinate.latitude - region.center.latitude)
        var longitudeDistance = abs(coordinate.longitude - region.center.longitude)
        longitudeDistance = min(longitudeDistance, 360 - longitudeDistance)

        return latitudeDistance <= abs(region.span.latitudeDelta) / 2
            && longitudeDistance <= abs(region.span.longitudeDelta) / 2
    }

    static func hasMeaningfulMapChange(
        from previous: MKCoordinateRegion?,
        to current: MKCoordinateRegion
    ) -> Bool {
        guard let previous else { return true }

        let previousCenter = CLLocation(
            latitude: previous.center.latitude,
            longitude: previous.center.longitude
        )
        let currentCenter = CLLocation(
            latitude: current.center.latitude,
            longitude: current.center.longitude
        )
        let westEdge = CLLocation(
            latitude: current.center.latitude,
            longitude: current.center.longitude - current.span.longitudeDelta / 2
        )
        let eastEdge = CLLocation(
            latitude: current.center.latitude,
            longitude: current.center.longitude + current.span.longitudeDelta / 2
        )
        let visibleWidth = westEdge.distance(from: eastEdge)
        let movedEnough = previousCenter.distance(from: currentCenter)
            > max(visibleWidth * 0.12, 120)

        let latitudeScale = current.span.latitudeDelta
            / max(previous.span.latitudeDelta, 0.000_001)
        let longitudeScale = current.span.longitudeDelta
            / max(previous.span.longitudeDelta, 0.000_001)
        let zoomedEnough = latitudeScale < 0.8 || latitudeScale > 1.25
            || longitudeScale < 0.8 || longitudeScale > 1.25

        return movedEnough || zoomedEnough
    }
}

enum MapSearchQueryPolicy {
    /// 入力文字に合う言語で地名を返し、照合時の表記揺れを抑える。
    /// ラテン文字は英語の標準地名を使い、「Da Nang」が「ダナン」へ変換されるのを防ぐ。
    static func geocodingLocale(
        for query: String,
        preferredLanguageIdentifier: String = Bundle.main.preferredLocalizations.first ?? "en"
    ) -> Locale {
        let scalars = query.unicodeScalars
        let usesJapaneseKana = scalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0xFF66...0xFF9D:
                return true
            default:
                return false
            }
        }
        if usesJapaneseKana { return Locale(identifier: "ja") }

        let usesHangul = scalars.contains { scalar in
            (0x1100...0x11FF).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
        if usesHangul { return Locale(identifier: "ko") }

        let usesThai = scalars.contains { (0x0E00...0x0E7F).contains($0.value) }
        if usesThai { return Locale(identifier: "th") }

        let usesHan = scalars.contains {
            (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
        }
        if usesHan {
            let identifier = preferredLanguageIdentifier.hasPrefix("zh")
                ? preferredLanguageIdentifier
                : "ja"
            return Locale(identifier: identifier)
        }

        return Locale(identifier: "en")
    }

    /// 住所ジオコーダーの行政地名と一致したときだけ、入力を都市・地域名として扱う。
    /// カンマ区切りの「Da Nang, Vietnam」にも対応し、店名の部分一致は避ける。
    static func matchesGeographicName(
        _ query: String,
        candidates: [String?]
    ) -> Bool {
        let queryParts = query
            .split(separator: ",", omittingEmptySubsequences: true)
            .flatMap { geographicVariants(of: String($0)) }
            .filter { $0.isEmpty == false }
        guard queryParts.isEmpty == false else { return false }

        return candidates.compactMap { $0 }.contains { candidate in
            let variants = geographicVariants(of: candidate)
                .filter { $0.count >= 2 }
            return variants.contains { queryParts.contains($0) }
        }
    }

    private static func geographicVariants(of value: String) -> [String] {
        let value = normalized(value)
        guard value.isEmpty == false else { return [] }

        let suffixes = [
            "特别行政区", "特別行政區", "특별시", "광역시",
            "prefecture", "province", "city", "県", "縣", "县", "省", "市", "区", "區", "都", "府", "道", "시", "도"
        ]
        guard let suffix = suffixes.first(where: {
            value.count > $0.count + 1 && value.hasSuffix($0)
        }) else {
            return [value]
        }
        return [value, String(value.dropLast(suffix.count))]
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "臺", with: "台")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
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
