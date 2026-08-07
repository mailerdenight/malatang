import SwiftUI
import SwiftData
import CoreLocation

/// 地図サービスに店舗がない場合でも、任意の座標を店名付きで保存する。
struct ManualMapStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let coordinate: CLLocationCoordinate2D
    let onStoreCreated: (Store) -> Void

    @State private var name = ""
    @State private var address = ""
    @State private var isResolvingAddress = true
    @State private var saveErrorMessage: String?

    private var normalizedName: String {
        MasterService.normalize(name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("店名", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("店舗")
                } footer: {
                    Text("地図に登録されていない店でも、店名と場所を端末内に保存できます。")
                }

                Section("場所") {
                    if isResolvingAddress {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("住所を確認しています…")
                                .foregroundStyle(Theme.subtleText)
                        }
                    }

                    TextField("住所（任意）", text: $address, axis: .vertical)
                        .lineLimit(2...4)

                    LabeledContent("座標") {
                        Text(coordinateText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.subtleText)
                    }
                }
            }
            .navigationTitle("この場所に店舗を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("記録へ") { saveAndContinue() }
                        .disabled(normalizedName.isEmpty)
                        .font(.body.weight(.semibold))
                }
            }
            .task {
                await resolveAddress()
            }
            .alert(
                "店舗を保存できませんでした",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if $0 == false { saveErrorMessage = nil } }
                )
            ) {
                Button("閉じる", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private var coordinateText: String {
        String(
            format: "%.5f, %.5f",
            locale: Locale(identifier: "en_US_POSIX"),
            coordinate.latitude,
            coordinate.longitude
        )
    }

    private func saveAndContinue() {
        guard normalizedName.isEmpty == false else { return }
        guard let store = MasterService.findOrCreateStore(
            name: normalizedName,
            address: MasterService.normalize(address),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            in: context
        ) else {
            return
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            saveErrorMessage = String(localized: "端末内に店舗を保存できませんでした。空き容量を確認して、もう一度お試しください。")
            return
        }
        onStoreCreated(store)
        dismiss()
    }

    @MainActor
    private func resolveAddress() async {
        defer { isResolvingAddress = false }
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: AppLocalization.preferredLocale
            )
            guard address.isEmpty, let placemark = placemarks.first else { return }
            address = MapAddressFormatter.string(from: placemark)
        } catch {
            // 逆ジオコードに失敗しても、店名と座標だけで保存できる。
        }
    }
}
