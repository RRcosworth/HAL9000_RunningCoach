import SwiftUI

/// Root container: ZStack with tab content + floating tab bar.
/// Main tabs managed by @State, following spec Section 5.1.
struct RootView: View {
    @State private var selectedTab: AppTab = .training

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

            FloatingTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}
