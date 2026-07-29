import SwiftUI
import SwiftData

@main
struct MalatangLogApp: App {

    @AppStorage("appearancePreference") private var appearancePreference = AppearancePreference.light.rawValue
    @State private var purchaseManager = PurchaseManager()
    private let containerResult: Result<ModelContainer, Error>

    init() {
        containerResult = Result { try AppModelContainer.make() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch containerResult {
                case .success(let container):
                    RootView()
                        .modelContainer(container)
                case .failure(let error):
                    DataUnavailableView(error: error)
                }
            }
            .environment(purchaseManager)
            .tint(Theme.primary)
            .preferredColorScheme(
                AppearancePreference(rawValue: appearancePreference)?.colorScheme
            )
        }
    }
}

/// データベースを開けなかったときの画面。
/// 黙ってメモリ内保存に切り替えると記録が消えたように見えるため、必ず状態を伝える。
struct DataUnavailableView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.primary)
            Text("データを開けませんでした")
                .font(Theme.title(22))
            Text("記録は端末内に残っている可能性があります。アプリを削除すると復元できなくなるため、削除せずに一度アプリを再起動してください。")
                .font(.footnote)
                .foregroundStyle(Theme.subtleText)
                .multilineTextAlignment(.center)
            Text(error.localizedDescription)
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.subtleText)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .warmBackground()
    }
}
