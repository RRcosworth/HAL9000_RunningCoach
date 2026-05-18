import SwiftUI
import UIKit

/// Adaptive design palette for iOS 26-style light/dark interfaces.
enum AppColor {
    // Page
    static let heroBackground = Color(light: "F4F6FB", dark: "111214")
    static let pageGlow       = Color(light: "DCEBFF", dark: "0A84FF")
    static let pageTitle      = Color(light: "111318", dark: "F7F8FA")

    // Content
    static let contentBackground = Color(light: "FFFFFF", dark: "1C1D20").opacity(0.94)
    static let cardBackground    = Color(light: "F2F4F8", dark: "2A2B30").opacity(0.92)
    static let controlBackground = Color(light: "E8EEF7", dark: "FFFFFF").opacity(0.12)

    // Accent
    static let accent      = Color(hex: "0A84FF")
    static let accentLight = Color(hex: "0A84FF").opacity(0.14)

    // Text
    static let textPrimary   = Color(light: "111318", dark: "F5F6F8")
    static let textSecondary = Color(light: "6B7280", dark: "A2A6AE")
    static let textTertiary  = Color(light: "9AA1AD", dark: "727782")

    // Liquid glass tab bar
    static let tabBarHighlight = Color(light: "FFFFFF", dark: "FFFFFF").opacity(0.22)
    static let tabBarStroke    = Color(light: "FFFFFF", dark: "FFFFFF").opacity(0.34)
    static let tabBarShadow    = Color.black.opacity(0.20)

    // Semantic
    static let success = Color(hex: "34C759")
    static let warning = Color(hex: "FF9F0A")
    static let error   = Color(hex: "FF453A")

    // Training load
    static let tsbFitness = Color(hex: "3388FF")
    static let tsbFatigue = Color(hex: "FF5533")
    static let tsbForm    = Color(hex: "33CC66")
    static let anaerobic  = Color(hex: "9944FF")
    static let highAerobic = Color(hex: "FF8833")
    static let lowAerobic = Color(hex: "55AADD")
    static let hrZone3 = Color(hex: "FFCC00")
    static let hrZone5 = Color(hex: "FF3333")

    // Divider
    static let divider = Color(light: "E5E7EE", dark: "34363D")
}

// MARK: - Hex Initializer

extension Color {
    init(light: String, dark: String) {
        self.init(
            UIColor { trait in
                let hex = trait.userInterfaceStyle == .dark ? dark : light
                return UIColor(hex: hex)
            }
        )
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8)  & 0xFF) / 255.0
            b = Double(int         & 0xFF) / 255.0
        default:
            r = 0; g = 0; b = 0
        }

        self.init(red: r, green: g, blue: b)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255.0
            g = CGFloat((int >> 8) & 0xFF) / 255.0
            b = CGFloat(int & 0xFF) / 255.0
        default:
            r = 0
            g = 0
            b = 0
        }

        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
