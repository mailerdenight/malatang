import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(CurrencySettings.self) private var currencySettings
    @Query(sort: \Serving.date, order: .reverse) private var servings: [Serving]
    @State private var selection: Tab
    @State private var showingRecordSheet = false
    @State private var showingCurrencyConfirmation = false

    enum Tab: String, Hashable {
        case home, map, album, analytics
    }

    init() {
        let previewValue = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--preview-tab=") })?
            .replacingOccurrences(of: "--preview-tab=", with: "")
        _selection = State(initialValue: previewValue.flatMap(Tab.init(rawValue:)) ?? .home)
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(onNewRecord: { showingRecordSheet = true })
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(Tab.home)

            NearbyMapView()
                .tabItem { Label("地図", systemImage: "mappin.and.ellipse") }
                .tag(Tab.map)

            AlbumView()
                .tabItem { Label("アルバム", systemImage: "photo.on.rectangle") }
                .tag(Tab.album)

            AnalyticsView()
                .tabItem { Label("分析", systemImage: "chart.bar") }
                .tag(Tab.analytics)
        }
        .sheet(isPresented: $showingRecordSheet) {
            RecordEditorView(mode: .create)
        }
        .sheet(isPresented: $showingCurrencyConfirmation) {
            InitialCurrencyConfirmationView()
                .interactiveDismissDisabled()
        }
        .task {
            MasterService.seedIfNeeded(context)
            SampleDataService.seedIfNeeded(context)
            showingCurrencyConfirmation = currencySettings.needsInitialConfirmation(servings: servings)
        }
    }
}

private struct InitialCurrencyConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencySettings.self) private var currencySettings

    var body: some View {
        @Bindable var currencySettings = currencySettings

        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("既定の通貨", systemImage: "creditcard")
                        Spacer()
                        Text(verbatim: currencySettings.defaultCurrency.title)
                            .foregroundStyle(Theme.subtleText)
                    }
                } footer: {
                    Text("ほとんどの場合はこのままで問題ありません。違う通貨で記録したい場合だけ変更してください。最初の記録を保存した後は変更できません。")
                }

                Section {
                    Picker("通貨", selection: $currencySettings.defaultCurrencyCode) {
                        ForEach(AppCurrency.allCases) { currency in
                            Text(verbatim: currency.title).tag(currency.rawValue)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("通貨の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("この通貨で始める") {
                        currencySettings.didConfirmDefaultCurrency = true
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}
