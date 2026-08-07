import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query private var servings: [Serving]

    @State private var estimate: ExportEstimate?
    @State private var exportURL: URL?
    @State private var showingShare = false
    @State private var showingImporter = false
    @State private var showingUnlimitedAccess = false
    @State private var pendingProAction: BackupProAction?
    @State private var pendingInspection: BackupService.Inspection?
    @State private var pendingMode: RestoreMode = .append
    @State private var showingReplaceConfirm1 = false
    @State private var showingReplaceConfirm2 = false
    @State private var result: RestoreResult?
    @State private var errorMessage: String?

    static var archiveType: UTType {
        UTType(exportedAs: BackupFormat.uti, conformingTo: .data)
    }

    private var visitedStoreCount: Int {
        Set(
            servings
                .filter { SampleDataService.isSample($0) == false }
                .compactMap { $0.store?.uuid }
        ).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                exportCard
                importCard
                if let result { resultCard(result) }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
        }
        .warmBackground()
        .navigationTitle("バックアップ")
        .navigationBarTitleDisplayMode(.inline)
        .task { estimate = BackupService.estimate(context: context) }
        .sheet(isPresented: $showingShare) {
            if let exportURL {
                ActivityView(items: [exportURL])
            }
        }
        .sheet(isPresented: $showingUnlimitedAccess) {
            UnlimitedAccessView(visitedStoreCount: visitedStoreCount)
        }
        .onChange(of: showingUnlimitedAccess) { _, isShowing in
            guard isShowing == false else { return }
            continuePendingProAction()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [Self.archiveType, .data],
            allowsMultipleSelection: false
        ) { outcome in
            handleImport(outcome)
        }
        .confirmationDialog(
            "今ある記録をすべて消して入れ替えますか？",
            isPresented: $showingReplaceConfirm1,
            titleVisibility: .visible
        ) {
            Button("続ける（次で最終確認）", role: .destructive) { showingReplaceConfirm2 = true }
            Button("やめる", role: .cancel) { pendingInspection = nil }
        } message: {
            Text("現在の記録と写真がすべて削除されます。")
        }
        .confirmationDialog(
            "本当に全置換しますか？取り消せません。",
            isPresented: $showingReplaceConfirm2,
            titleVisibility: .visible
        ) {
            Button("全置換で復元する", role: .destructive) { runRestore(mode: .replaceAll) }
            Button("やめる", role: .cancel) { pendingInspection = nil }
        }
    }

    // MARK: - 書き出し

    private var exportCard: some View {
        SectionCard(title: "バックアップを作る", subtitle: "写真も含めて1つのファイルにまとめます") {
            VStack(alignment: .leading, spacing: 12) {
                if let estimate {
                    VStack(alignment: .leading, spacing: 4) {
                        infoRow("記録", String(localized: "\(estimate.servingCount)件"))
                        infoRow("写真", String(localized: "\(estimate.photoCount)枚"))
                        infoRow("店舗", String(localized: "\(estimate.storeCount)件"))
                        infoRow("推定容量", estimate.estimatedSizeText)
                    }
                }
                Button {
                    requireUnlockThen(.export)
                } label: {
                    Label("バックアップを書き出す", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .disabled((estimate?.servingCount ?? 0) == 0)

                if purchaseManager.isUnlocked == false {
                    Text("バックアップの書き出しは無制限版で使えます。金額は購入画面で確認できます。")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleText)
                }

                Text("書き出したファイル（.malaarchive）は「ファイル」アプリやiCloud Driveなど、お好きな場所に保存できます。")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
            }
        }
    }

    // MARK: - 復元

    private var importCard: some View {
        SectionCard(title: "バックアップから復元", subtitle: "方式を選んでから読み込みます") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("復元方式", selection: $pendingMode) {
                    ForEach(RestoreMode.allCases) { mode in
                        Text(verbatim: mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(pendingMode.explanation)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleText)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    requireUnlockThen(.import)
                } label: {
                    Label("バックアップファイルを選ぶ", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.bordered)

                if purchaseManager.isUnlocked == false {
                    Text("バックアップからの復元は無制限版で使えます。押すと購入画面で金額を確認できます。")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleText)
                }
            }
        }
    }

    private func resultCard(_ result: RestoreResult) -> some View {
        SectionCard(title: "復元しました", subtitle: result.mode.title) {
            VStack(alignment: .leading, spacing: 4) {
                infoRow("追加した記録", String(localized: "\(result.addedServings)件"))
                infoRow("重複でスキップ", String(localized: "\(result.skippedServings)件"))
                infoRow("追加した店舗", String(localized: "\(result.addedStores)件"))
                infoRow("追加したマスター", String(localized: "\(result.addedMasters)件"))
                infoRow("復元した写真", String(localized: "\(result.restoredPhotos)枚"))
                if result.missingPhotos > 0 {
                    infoRow("見つからない写真", String(localized: "\(result.missingPhotos)枚"))
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).font(.subheadline).foregroundStyle(Theme.subtleText)
            Spacer()
            Text(verbatim: value).font(.body.weight(.medium).monospacedDigit())
        }
        .frame(minHeight: 28)
    }

    // MARK: - 処理

    private func requireUnlockThen(_ action: BackupProAction) {
        errorMessage = nil
        result = nil
        guard purchaseManager.isUnlocked == false else {
            perform(action)
            return
        }
        pendingProAction = action
        showingUnlimitedAccess = true
    }

    private func continuePendingProAction() {
        guard let pendingProAction, purchaseManager.isUnlocked else { return }
        self.pendingProAction = nil
        perform(pendingProAction)
    }

    private func perform(_ action: BackupProAction) {
        switch action {
        case .export:
            runExport()
        case .import:
            showingImporter = true
        }
    }

    private func runExport() {
        errorMessage = nil
        do {
            exportURL = try BackupService.export(context: context)
            showingShare = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleImport(_ outcome: Result<[URL], Error>) {
        errorMessage = nil
        switch outcome {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let inspection = try BackupService.inspect(url: url)
                pendingInspection = inspection
                if pendingMode == .replaceAll {
                    showingReplaceConfirm1 = true
                } else {
                    runRestore(mode: .append)
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func runRestore(mode: RestoreMode) {
        guard let inspection = pendingInspection else { return }
        do {
            result = try BackupService.restore(inspection: inspection, mode: mode, context: context)
            estimate = BackupService.estimate(context: context)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        pendingInspection = nil
    }
}

private enum BackupProAction {
    case export
    case `import`
}
