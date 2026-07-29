import SwiftUI
import SwiftData

/// 写真を主役に、月ごとに麻辣湯の記録を振り返る画面。
/// 検索・絞り込み・削除は右上の「記録一覧」に分離する。
struct AlbumView: View {
    @Query(sort: \Serving.date, order: .reverse) private var servings: [Serving]

    @State private var sortOrder: AlbumSortOrder = .newest
    @State private var showingRecordList = false

    private let calendar = Calendar.current

    private var servingsWithPhotos: [Serving] {
        servings.filter { $0.photoID != nil }
    }

    private var groupedByMonth: [AlbumMonthSection] {
        var monthStarts: [String: Date] = [:]
        let grouped = Dictionary(grouping: servingsWithPhotos) { serving -> String in
            let components = calendar.dateComponents([.year, .month], from: serving.date)
            let year = components.year ?? 0
            let month = components.month ?? 0
            let key = "\(year)年\(month)月"
            if monthStarts[key] == nil {
                monthStarts[key] = calendar.date(from: components) ?? serving.date
            }
            return key
        }

        return grouped.map { title, items in
            AlbumMonthSection(
                title: title,
                startDate: monthStarts[title] ?? .distantPast,
                servings: sortOrder.apply(to: items)
            )
        }
        .sorted {
            sortOrder == .newest
                ? $0.startDate > $1.startDate
                : $0.startDate < $1.startDate
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if servingsWithPhotos.isEmpty {
                    emptyState
                } else {
                    albumContent
                }
            }
            .warmBackground()
            .navigationTitle("アルバム")
            .navigationDestination(for: Serving.self) { serving in
                ServingDetailView(serving: serving)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingRecordList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("記録一覧")

                    Menu {
                        ForEach(AlbumSortOrder.allCases) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                Label(
                                    order.title,
                                    systemImage: sortOrder == order ? "checkmark" : "arrow.up.arrow.down"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("並び替え")
                }
            }
            .sheet(isPresented: $showingRecordList) {
                CatalogView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                symbol: "photo.on.rectangle.angled",
                title: "まだ写真がありません",
                message: "記録に写真を追加すると、月ごとのアルバムになります。"
            )

            Button {
                showingRecordList = true
            } label: {
                Label("写真なしを含む記録一覧を見る", systemImage: "list.bullet")
                    .frame(minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private var albumContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(groupedByMonth) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(section.title)
                                .font(Theme.title(18))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            NavigationLink {
                                AlbumMonthView(section: section)
                            } label: {
                                HStack(spacing: 3) {
                                    Text("すべて見る")
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                            }
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(section.servings.prefix(12), id: \.uuid) { serving in
                                    NavigationLink(value: serving) {
                                        AlbumThumbnailCard(serving: serving)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

private enum AlbumSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "新しい順"
        case .oldest: return "古い順"
        }
    }

    func apply(to servings: [Serving]) -> [Serving] {
        servings.sorted {
            self == .newest ? $0.date > $1.date : $0.date < $1.date
        }
    }
}

private struct AlbumMonthSection: Identifiable {
    var id: String { title }
    let title: String
    let startDate: Date
    let servings: [Serving]
}

private struct AlbumThumbnailCard: View {
    let serving: Serving

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ServingThumbnail(photoID: serving.photoID, cornerRadius: 12)
                .frame(width: 94, height: 94)
                .overlay(alignment: .topTrailing) {
                    SampleBadge(serving: serving)
                }

            Text(serving.date.formatted(.dateTime.month(.defaultDigits).day()))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.subtleText)
            Text(serving.storeDisplayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .frame(width: 94, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct AlbumMonthView: View {
    let section: AlbumMonthSection

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(section.servings, id: \.uuid) { serving in
                    NavigationLink(value: serving) {
                        VStack(alignment: .leading, spacing: 6) {
                            ServingThumbnail(photoID: serving.photoID, cornerRadius: 12)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .topTrailing) {
                                    SampleBadge(serving: serving)
                                }
                            Text(serving.date.formatted(.dateTime.month(.defaultDigits).day()))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.subtleText)
                            Text(serving.storeDisplayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .warmBackground()
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SampleBadge: View {
    let serving: Serving

    var body: some View {
        if SampleDataService.isSample(serving) {
            Text("sample")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.22), in: Capsule())
                .padding(6)
                .accessibilityHidden(true)
        }
    }
}
