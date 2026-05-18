import SwiftUI

/// Primary action button used throughout the app.
struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    var isFullWidth: Bool = true
    var variant: Variant = .filled

    enum Variant {
        case filled
        case outline
    }

    init(
        _ title: String,
        systemImage: String? = nil,
        isFullWidth: Bool = true,
        variant: Variant = .filled,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isFullWidth = isFullWidth
        self.variant = variant
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(variant == .filled ? AppColor.accent : Color.clear)
            .foregroundStyle(variant == .filled ? .white : AppColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                if variant == .outline {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColor.accent, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
