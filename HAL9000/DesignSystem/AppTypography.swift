import SwiftUI

/// Typography constants for the app.
enum AppTypography {
    static let largeTitle  = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title       = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2      = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let title3      = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let headline    = Font.system(size: 17, weight: .semibold)
    static let body        = Font.system(size: 17, weight: .regular)
    static let callout     = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let footnote    = Font.system(size: 13, weight: .regular)
    static let caption     = Font.system(size: 12, weight: .regular)
    static let captionBold = Font.system(size: 12, weight: .semibold)
}
