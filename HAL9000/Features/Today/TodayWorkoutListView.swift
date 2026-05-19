import SwiftUI

struct TodayWorkoutListView: View {
    let workouts: [TodayWorkoutSummary]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if workouts.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(workouts) { workout in
                            NavigationLink(value: workout) {
                                workoutRow(workout)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Color.clear.frame(height: 118)
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background { AppBackground() }
        .supportsSwipeBack()
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(AppColor.controlBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("今日运动")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColor.pageTitle)
                Text(workouts.isEmpty ? "Apple 健康记录" : "\(workouts.count) 次运动")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()
        }
    }

    private var emptyState: some View {
        TodayCard {
            VStack(spacing: 14) {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                Text("今日暂无运动记录")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("完成一次 Apple Watch 运动后，这里会显示列表、轨迹和心率详情。")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
    }

    private func workoutRow(_ workout: TodayWorkoutSummary) -> some View {
        TodayCard {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 44, height: 44)
                    .background(AppColor.accentLight)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(workout.title)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text(workout.startedAt.formatted(date: .omitted, time: .shortened))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }

                    Text(summaryText(for: workout))
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }

    private func summaryText(for workout: TodayWorkoutSummary) -> String {
        let duration = String(format: "%.0f 分钟", workout.durationMinutes)
        let distance = workout.distanceKm.map { String(format: "%.2f km", $0) } ?? "--"
        return "\(distance) · \(duration)"
    }
}
