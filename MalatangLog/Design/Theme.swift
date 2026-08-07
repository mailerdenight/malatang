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
    @MainActor
    private static var selectedTheme: AppTheme {
        AppearanceSettings.shared.theme
    }

    @MainActor
    static var background: Color { selectedTheme.backgroundColor }
    @MainActor
    static var primary: Color { selectedTheme.primaryColor }
    @MainActor
    static var secondary: Color { selectedTheme.secondaryColor }
    @MainActor
    static var accent: Color { selectedTheme.accentColor }
    static let text = Color(uiColor: .label)
    static let subtleText = Color(uiColor: .secondaryLabel)
    @MainActor
    static var surface: Color { selectedTheme.cardColor }
    @MainActor
    static var card: Color { selectedTheme.cardColor }
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

enum AppTheme: String, CaseIterable, Identifiable {
    case forest
    case blossom
    case ocean
    case sunshine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest: return String(localized: "フォレスト")
        case .blossom: return String(localized: "ブロッサム")
        case .ocean: return String(localized: "オーシャン")
        case .sunshine: return String(localized: "サンシャイン")
        }
    }

    var primaryColor: Color {
        switch self {
        case .forest: return Color(hex: 0x4A7C59)
        case .blossom: return Color(hex: 0xC4687A)
        case .ocean: return Color(hex: 0x4A7FA8)
        case .sunshine: return Color(hex: 0xC09020)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .forest: return Color(hex: 0x6B9E7A)
        case .blossom: return Color(hex: 0xE8A8B8)
        case .ocean: return Color(hex: 0x7AAFD0)
        case .sunshine: return Color(hex: 0xE0BC6A)
        }
    }

    var accentColor: Color {
        switch self {
        case .forest: return Color(hex: 0x2D5A3D)
        case .blossom: return Color(hex: 0x8B4558)
        case .ocean: return Color(hex: 0x2B5F84)
        case .sunshine: return Color(hex: 0x8B6C10)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .forest:
            return Color(lightHex: 0xF5F5F0, darkHex: 0x1C1C1F)
        case .blossom:
            return Color(lightHex: 0xFCF5F7, darkHex: 0x1C1C1F)
        case .ocean:
            return Color(lightHex: 0xF0F7FC, darkHex: 0x1C1C1F)
        case .sunshine:
            return Color(lightHex: 0xFCFAED, darkHex: 0x1C1C1F)
        }
    }

    var cardColor: Color {
        Color(lightHex: 0xFFFFFF, darkHex: 0x2B2B2E)
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return String(localized: "ライト")
        case .dark: return String(localized: "ダーク")
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
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
