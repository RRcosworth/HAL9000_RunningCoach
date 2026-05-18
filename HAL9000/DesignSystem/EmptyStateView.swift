import SwiftUI

/// Reusable empty state view for all feature pages.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        systemImage: String = "tray",
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(AppColor.textTertiary)
                .padding(.bottom, 4)

            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColor.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 80)
    }
}
