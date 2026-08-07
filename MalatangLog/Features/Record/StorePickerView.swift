import SwiftUI
import SwiftData
import CoreLocation

/// 店舗の指定。店名だけでも保存できる。位置情報を拒否していても地図検索は使える。
struct StorePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Store.createdAt, order: .reverse) private var savedStores: [Store]
    @Binding var selection: Store?

    @StateObject private var location = LocationProvider()
    @State private var search = StoreSearchService()

    @State private var nameInput = ""
    @State private var mapQuery = ""
    @State private var isWaitingForNearbyLocation = false
    @State private var nearbyLocationMessage: String?
    @State private var nearbyLocationRequestID = UUID()

    private var normalizedInput: String { MasterService.normalize(nameInput) }

    private var matchedSavedStores: [Store] {
        guard normalizedInput.isEmpty == false else { return Array(savedStores.prefix(8)) }
        return savedStores.filter {
            $0.displayName.localizedCaseInsensitiveContains(normalizedInput)
                || $0.address.localizedCaseInsensitiveContains(normalizedInput)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    manualEntry
                    if matchedSavedStores.isEmpty == false {
                        savedStoreList
                    }
                    mapSearch
                }
                .padding(16)
            }
            .warmBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("店舗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("この店名で決定") { commitManualName() }
                        .disabled(normalizedInput.isEmpty)
                        .font(.body.weight(.semibold))
                }
            }
            .onReceive(location.$currentLocation) { currentLocation in
                guard isWaitingForNearbyLocation, let currentLocation else { return }
                finishNearbySearch(at: currentLocation.coordinate)
            }
            .onChange(of: location.authorizationStatus) { _, status in
                guard isWaitingForNearbyLocation else { return }
                if status == .denied || status == .restricted {
                    isWaitingForNearbyLocation = false
                    nearbyLocationMessage = String(localized: "現在地を利用できません。店名・地域名で検索するか、店名を直接入力してください。")
                }
            }
            .task(id: nearbyLocationRequestID) {
                guard isWaitingForNearbyLocation else { return }
                try? await Task.sleep(for: .seconds(10))
                guard Task.isCancelled == false, isWaitingForNearbyLocation else { return }
                isWaitingForNearbyLocation = false
                nearbyLocationMessage = String(localized: "現在地を取得できませんでした。店名・地域名で検索するか、店名を直接入力してください。")
            }
        }
    }

    // MARK: - 手入力

    private var manualEntry: some View {
        SectionCard(title: "店名を入力", subtitle: "店名だけでも保存できます") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("例：張亮麻辣湯 新宿店", text: $nameInput)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { commitManualName() }

                if selection != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.secondary)
                        Text("選択中：\(selection?.displayName ?? "")")
                            .font(.footnote)
                        Spacer()
                        Button("解除") { selection = nil }
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private var savedStoreList: some View {
        SectionCard(title: "保存済みの店舗", subtitle: "過去に記録した店舗を優先して表示します") {
            VStack(spacing: 0) {
                ForEach(matchedSavedStores, id: \.uuid) { store in
                    Button {
                        selection = store
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.displayName)
                                    .font(.body)
                                    .foregroundStyle(Theme.text)
                                if store.address.isEmpty == false {
                                    Text(verbatim: SampleDataService.displayAddress(for: store))
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtleText)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(store.visitCount)回")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.subtleText)
                        }
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if store.uuid != matchedSavedStores.last?.uuid {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
        }
    }

    // MARK: - 地図検索

    private var mapSearch: some View {
        SectionCard(title: "地図で探す", subtitle: "位置情報を許可しなくても検索できます") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("店名・地域名（例：麻辣湯 池袋）", text: $mapQuery)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { runKeywordSearch() }
                    Button("検索") { runKeywordSearch() }
                        .buttonStyle(.borderedProminent)
                        .disabled(MasterService.normalize(mapQuery).isEmpty)
                }

                if isWaitingForNearbyLocation {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("現在地を取得中…")
                            .font(.footnote)
                            .foregroundStyle(Theme.subtleText)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                } else if location.isAuthorized {
                    Button {
                        runNearbySearch()
                    } label: {
                        Label("現在地付近から選ぶ", systemImage: "location")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                } else if location.isUndetermined {
                    Button {
                        runNearbySearch()
                    } label: {
                        Label("現在地の利用を許可する", systemImage: "location")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                }

                if let nearbyLocationMessage {
                    Text(nearbyLocationMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.subtleText)
                }

                searchResults
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        switch search.state {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView()
                Text("検索中…").font(.footnote).foregroundStyle(Theme.subtleText)
            }
        case .empty:
            VStack(alignment: .leading, spacing: 10) {
                Text("該当する店舗が見つかりませんでした。店名を直接入力しても保存できます。")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtleText)
                googleMapsFallback
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.primary)
                googleMapsFallback
            }
        case .results(let items):
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        adopt(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.name)
                                .font(.body)
                                .foregroundStyle(Theme.text)
                            if item.address.isEmpty == false {
                                Text(item.address)
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtleText)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
        }
    }

    // MARK: - 操作

    @ViewBuilder
    private var googleMapsFallback: some View {
        let keyword = MasterService.normalize(mapQuery)
        if keyword.isEmpty == false {
            Button {
                MapLauncher.openMap(.query(keyword), using: .google)
            } label: {
                Label("Googleマップで探す", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
        }
    }

    private func runKeywordSearch() {
        let keyword = MasterService.normalize(mapQuery)
        guard keyword.isEmpty == false else { return }
        isWaitingForNearbyLocation = false
        nearbyLocationMessage = nil
        search.search(keyword: keyword, near: location.currentLocation?.coordinate)
    }

    private func runNearbySearch() {
        nearbyLocationMessage = nil
        if let coordinate = location.currentLocation?.coordinate {
            finishNearbySearch(at: coordinate)
            return
        }

        isWaitingForNearbyLocation = true
        nearbyLocationRequestID = UUID()
        if location.isUndetermined {
            location.requestAuthorization()
        } else {
            location.requestOneShotLocation()
        }
    }

    private func finishNearbySearch(at coordinate: CLLocationCoordinate2D) {
        isWaitingForNearbyLocation = false
        nearbyLocationMessage = nil
        search.searchNearby(coordinate: coordinate)
    }

    private func commitManualName() {
        guard normalizedInput.isEmpty == false else { return }
        selection = MasterService.findOrCreateStore(name: normalizedInput, in: context)
        dismiss()
    }

    /// 検索結果の生データ全体は保存せず、必要な項目だけを取り込む。
    private func adopt(_ result: StoreSearchResult) {
        selection = MasterService.findOrCreateStore(
            name: result.name,
            branch: "",
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            in: context
        )
        dismiss()
    }
}
