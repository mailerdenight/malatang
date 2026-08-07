import SwiftUI
import UIKit

// MARK: - タグチップ

/// 選択状態を色だけで表さない（チェックマークと枠線を併用）。
struct TagChip: View {
    let title: String
    var isSelected: Bool = false
    var isPinned: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .font(.callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 40)
            .foregroundStyle(isSelected ? Color.white : Theme.text)
            .background(isSelected ? Theme.primary : Theme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Theme.primary : Theme.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(
            isSelected ? String(localized: "\(title)、選択中") : title
        )
    }
}

// MARK: - 辛さ・痺れ

struct LevelSelector: View {
    let title: String
    let symbol: String
    @Binding var value: Int
    var maximum: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value) / \(maximum)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.subtleText)
            }
            HStack(spacing: 6) {
                ForEach(0...maximum, id: \.self) { level in
                    Button {
                        value = level
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(level <= value && level > 0 ? Theme.primary : Theme.surface)
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(value == level ? Theme.secondary : Theme.hairline, lineWidth: value == level ? 2.5 : 1)
                            if level == 0 {
                                Text("0")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(value == 0 ? Theme.secondary : Theme.subtleText)
                            } else {
                                Image(systemName: symbol)
                                    .font(.footnote)
                                    .foregroundStyle(level <= value ? Color.white : Theme.subtleText)
                            }
                        }
                        .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "\(AppLocalization.string(title)) \(level)")
                    )
                    .accessibilityAddTraits(value == level ? [.isSelected] : [])
                }
            }
        }
    }
}

// MARK: - 評価

struct StarRatingView: View {
    @Binding var rating: Int
    var isEditable: Bool = true
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(star <= rating ? Theme.accent : Theme.subtleText.opacity(0.5))
                    .frame(minWidth: isEditable ? Theme.minTapTarget : size + 2,
                           minHeight: isEditable ? Theme.minTapTarget : size + 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isEditable else { return }
                        rating = (rating == star) ? 0 : star
                    }
            }
            if isEditable, rating == 0 {
                Text("未評価")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtleText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating == 0 ? "評価は未入力" : "5段階中\(rating)")
        .accessibilityValue("\(rating)")
    }
}

struct StaticRatingLabel: View {
    let rating: Int

    var body: some View {
        if rating > 0 {
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                Text("\(rating)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("評価 5段階中\(rating)")
        }
    }
}

// MARK: - セクション

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption)
                        .foregroundStyle(Theme.subtleText)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }
}

// MARK: - 写真

struct ServingThumbnail: View {
    let photoID: String?
    var cornerRadius: CGFloat = Theme.cornerRadius

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = PhotoStore.shared.load(photoID) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Theme.secondary.opacity(0.10)
                        Image(systemName: "takeoutbag.and.cup.and.straw")
                            .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.32))
                            .foregroundStyle(Theme.secondary.opacity(0.45))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(photoID == nil ? "写真なし" : "一杯の写真")
    }
}

// MARK: - 保存完了の湯気

struct SteamOverlay: View {
    @State private var rise = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    SteamCurve()
                        .stroke(Theme.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 18, height: 46)
                        .offset(x: CGFloat(index - 1) * 22, y: rise ? -14 : 6)
                        .opacity(rise ? 0 : 0.9)
                        .animation(
                            .easeOut(duration: 1.1).delay(Double(index) * 0.12),
                            value: rise
                        )
                }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.primary)
                    .offset(y: 46)
            }
            Text("保存しました")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.top, 34)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { rise = true }
        .accessibilityLabel("保存しました")
    }
}

private struct SteamCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.maxX + 6, y: rect.maxY * 0.62),
            control2: CGPoint(x: rect.minX - 6, y: rect.maxY * 0.34)
        )
        return path
    }
}

// MARK: - 空状態

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(Theme.secondary.opacity(0.5))
            Text(LocalizedStringKey(title))
                .font(Theme.title(17))
            Text(LocalizedStringKey(message))
                .font(.footnote)
                .foregroundStyle(Theme.subtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - 折り返しタグ配置

/// 具材タグを2行程度で折り返して並べる。iOS 17 の Layout を使用。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let currentIndex = rows.count - 1
            let projected = rows[currentIndex] == 0 ? size.width : rows[currentIndex] + spacing + size.width
            if projected > maxWidth, rows[currentIndex] > 0 {
                rows.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[currentIndex] = projected
                rowHeights[currentIndex] = max(rowHeights[currentIndex], size.height)
            }
        }
        let totalHeight = rowHeights.reduce(0, +) + spacing * CGFloat(max(rowHeights.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.max() ?? 0, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
