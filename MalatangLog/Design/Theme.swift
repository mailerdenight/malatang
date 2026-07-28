import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? darkHex : lightHex
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum Theme {
    /// iOS標準の背景。ライト／ダークに自動追従する。
    static let background = Color(uiColor: .systemGroupedBackground)
    /// 麻辣の赤
    static let primary = Color(lightHex: 0xC74332, darkHex: 0xFF7462)
    /// 深い緑
    static let secondary = Color(lightHex: 0x2F6B55, darkHex: 0x71B99D)
    /// 金
    static let accent = Color(lightHex: 0xB07818, darkHex: 0xE2AE50)
    static let text = Color(uiColor: .label)
    static let subtleText = Color(uiColor: .secondaryLabel)
    static let surface = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .systemBackground)
    static let hairline = Color(uiColor: .separator)
    static let shadow = Color.black.opacity(0.06)

    static let cornerRadius: CGFloat = 16
    static let minTapTarget: CGFloat = 44

    /// iOS標準のサンセリフ体
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// iOS標準背景をルートに敷く。
struct WarmBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.background.ignoresSafeArea())
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case light
    case system
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "ライト"
        case .system: return "端末に合わせる"
        case .dark: return "ダーク"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .system: return nil
        case .dark: return .dark
        }
    }
}

extension View {
    func warmBackground() -> some View { modifier(WarmBackground()) }

    func cardStyle() -> some View {
        self
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: Theme.shadow, radius: 10, x: 0, y: 4)
    }
}
