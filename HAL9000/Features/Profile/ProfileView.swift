import SwiftUI

struct ProfileView: View {
    @AppStorage("intervalsAthleteId") private var intervalsAthleteId = ""
    @AppStorage("intervalsApiKey") private var intervalsApiKey = ""

    private let defaultIntervalsAthleteId = ""
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                profileCard
                dataSourcesSection
                aiSection
                aboutSection

                Color.clear.frame(height: 118)
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
        }
        .background {
            AppBackground()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Profile")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColor.pageTitle)
            Text("个人信息、数据源和 AI 配置")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var profileCard: some View {
        ProfileCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 62, height: 62)
                    .background(AppColor.accentLight)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Justin Song")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("跑步训练 · HAL9000 Runner Coach")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                    HStack(spacing: 8) {
                        StatusPill(title: "开发版", tint: AppColor.warning)
                        StatusPill(title: "本地数据", tint: AppColor.success)
                    }
                }

                Spacer()
            }
        }
    }

    private var dataSourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("数据源")

            ProfileCard(spacing: 0) {
                DataSourceRow(
                    icon: "heart.text.square.fill",
                    iconTint: AppColor.success,
                    title: "Apple Health",
                    subtitle: "已接入 - 跑步、HRV、体重、运动记录",
                    trailing: "本地",
                    trailingTint: AppColor.success
                )

                divider

                SyncSummary(
                    title: "读取成功",
                    subtitle: "Today / Analysis 使用 HealthKit 本地数据；授权完成后不再重复弹窗。"
                )

                divider

                DataSourceRow(
                    icon: "waveform.path.ecg",
                    iconTint: Color(hex: "2D9CDB"),
                    title: "Intervals.icu",
                    subtitle: intervalsConnectionText,
                    trailing: "同步",
                    trailingTint: AppColor.accent
                )

                idRow("Athlete ID", intervalsAthleteIdText)

                mutedNote("当前使用 Athlete ID + API Key 接入；后续扩展多用户时再切换 OAuth 会更稳。")

                SyncSummary(
                    title: intervalsApiKey.isEmpty ? "等待配置" : "同步成功",
                    subtitle: intervalsApiKey.isEmpty
                        ? "Race Log 需要 Intervals.icu API Key 才能同步比赛。"
                        : "Race Log 已使用 Intervals.icu 拉取活动并识别比赛地图。"
                )

                divider

                DataSourceRow(
                    icon: "link",
                    iconTint: AppColor.warning,
                    title: "Strava",
                    subtitle: "未连接 - 获取佳明运动详情、海拔、分段数据",
                    trailing: "连接",
                    trailingTint: AppColor.warning
                )

                mutedNote("Strava 当前为预留数据源，后续可接 OAuth 和活动匹配。")
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("AI 配置")

            ProfileCard(spacing: 0) {
                ConfigRow(
                    icon: "checkmark.circle.fill",
                    iconTint: AppColor.success,
                    title: "API Key 已配置",
                    subtitle: "训练计划、分析摘要和对话能力可用"
                )

                divider

                ConfigRow(
                    icon: "brain.head.profile",
                    iconTint: AppColor.accent,
                    title: "知识库",
                    subtitle: "running-knowledge-base 已用于 Analysis 规则"
                )

                divider

                ConfigRow(
                    icon: "wand.and.stars",
                    iconTint: AppColor.warning,
                    title: "计划生成",
                    subtitle: "基于每周训练进度生成动态训练建议"
                )
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("关于")

            ProfileCard(spacing: 0) {
                idRow("版本", "\(appVersion) (\(buildNumber))")
                divider
                idRow("Bundle ID", "com.hal9000.runnercoach")
                divider
                idRow("数据策略", "本地优先 · 密钥开发版内置")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColor.divider)
            .frame(height: 1)
            .padding(.leading, 42)
    }

    private var intervalsAthleteIdText: String {
        let trimmed = intervalsAthleteId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultIntervalsAthleteId : trimmed
    }

    private var intervalsConnectionText: String {
        intervalsApiKey.isEmpty ? "未配置 API Key" : "已连接 - 比赛、活动、轨迹摘要"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.title3)
            .foregroundStyle(AppColor.pageTitle)
            .padding(.top, 4)
    }

    private func idRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    private func mutedNote(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.footnote)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 14)
    }
}

private struct ProfileCard<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

private struct DataSourceRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let trailing: String
    let trailingTint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Text(trailing)
                .font(AppTypography.captionBold)
                .foregroundStyle(trailingTint)
                .padding(.top, 3)
        }
        .padding(.vertical, 14)
    }
}

private struct SyncSummary: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppTypography.captionBold)
                .foregroundStyle(AppColor.success)
            Text(subtitle)
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
    }
}

private struct ConfigRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, 14)
    }
}

private struct StatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(AppTypography.captionBold)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
