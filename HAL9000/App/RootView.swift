import SwiftUI
import UIKit

/// Root container: ZStack with tab content + floating tab bar.
/// Main tabs managed by @State, following spec Section 5.1.
struct RootView: View {
    @State private var selectedTab: AppTab = .training
    @State private var isKeyboardVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            Group {
                switch selectedTab {
                case .today:    TodayView()
                case .training: TrainingView()
                case .analysis: AnalysisView()
                case .raceLog:  RaceLogView()
                case .coach:    CoachView()
                case .profile:  ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isKeyboardVisible {
                FloatingTabBar(selectedTab: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}
