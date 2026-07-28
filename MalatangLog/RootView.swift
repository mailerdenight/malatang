import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: Tab
    @State private var showingRecordSheet = false

    enum Tab: String, Hashable {
        case home, map, catalog, analytics
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

            CatalogView()
                .tabItem { Label("一覧", systemImage: "list.bullet.rectangle") }
                .tag(Tab.catalog)

            AnalyticsView()
                .tabItem { Label("分析", systemImage: "chart.bar") }
                .tag(Tab.analytics)
        }
        .sheet(isPresented: $showingRecordSheet) {
            RecordEditorView(mode: .create)
        }
        .task {
            MasterService.seedIfNeeded(context)
            SampleDataService.seedIfNeeded(context)
        }
    }
}
