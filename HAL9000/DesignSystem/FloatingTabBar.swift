import SwiftUI

/// iOS 26-inspired floating Liquid Glass tab bar.
struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var selectionNamespace

    var body: some View {
        if #available(iOS 26.0, *) {
            officialLiquidGlassBar
        } else {
            legacyGlassBar
        }
    }

    @available(iOS 26.0, *)
    private var officialLiquidGlassBar: some View {
        GlassEffectContainer(spacing: 0) {
            tabItems
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
                .simultaneousGesture(tabDragGesture)
                .shadow(color: AppColor.tabBarShadow, radius: 24, x: 0, y: 14)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
        }
    }

    private var legacyGlassBar: some View {
        tabItems
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .simultaneousGesture(tabDragGesture)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.26),
                                        .white.opacity(0.08),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .stroke(AppColor.tabBarStroke, lineWidth: 1)
                    }
            }
            .shadow(color: AppColor.tabBarShadow, radius: 24, x: 0, y: 14)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
    }

    private var tabItems: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: selectedTab == tab ? 29 : 26, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selectedTab == tab ? AppColor.accent : AppColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background { selectedTabBackground(for: tab) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func selectedTabBackground(for tab: AppTab) -> some View {
        if selectedTab == tab {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(AppColor.accent.opacity(0.14))
                    .overlay {
                        Capsule()
                            .fill(.white.opacity(0.10))
                    }
                    .matchedGeometryEffect(id: "selectedTabGlass", in: selectionNamespace)
            } else {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.38), lineWidth: 1)
                    }
                    .shadow(color: AppColor.accent.opacity(0.18), radius: 10, x: 0, y: 5)
                    .matchedGeometryEffect(id: "selectedTabGlass", in: selectionNamespace)
            }
        }
    }

    private var tabDragGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                moveSelection(by: value.translation.width)
            }
    }

    private func moveSelection(by translation: CGFloat) {
        guard abs(translation) > 28,
              let currentIndex = AppTab.allCases.firstIndex(of: selectedTab)
        else { return }

        let offset = translation < 0 ? 1 : -1
        let nextIndex = min(max(currentIndex + offset, 0), AppTab.allCases.count - 1)
        guard nextIndex != currentIndex else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selectedTab = AppTab.allCases[nextIndex]
        }
    }
}
