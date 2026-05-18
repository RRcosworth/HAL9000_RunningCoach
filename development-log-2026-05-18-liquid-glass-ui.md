# Development Log - 2026-05-18 - Liquid Glass UI Refresh

## Request

重构整体 UI：

- 底部菜单栏采用 iOS 26 风格 Liquid Glass。
- 支持日间模式、夜间模式，并随系统自动切换。
- 美化主要页面视觉层次。

## References

- Apple Developer: Build a SwiftUI app with the new design, WWDC25
  https://developer.apple.com/videos/play/wwdc2025/323
- Apple Developer: Meet Liquid Glass, WWDC25
  https://developer.apple.com/videos/play/wwdc2025/219

实现口径：当前项目仍保留自定义底部 Tab Bar，因此没有完全切换到系统 `TabView`。本次采用 SwiftUI material、动态色、玻璃高光、描边和阴影组合，模拟 Liquid Glass 的浮动导航层级。

## Changes

### Design System

Files:

- `HAL9000/DesignSystem/AppColor.swift`
- `HAL9000/DesignSystem/AppBackground.swift`
- `HAL9000/DesignSystem/FloatingTabBar.swift`

Updates:

- `AppColor` 从固定深色 palette 改为 `UIColor` 动态色。
- 新增 `Color(light:dark:)`，支持系统浅色/深色自动切换。
- 新增 `AppBackground`，提供浅色/深色自适应页面背景和柔和光晕。
- 重做 `FloatingTabBar`：
  - `.ultraThinMaterial`
  - 多层高光渐变
  - 玻璃描边
  - 浮动阴影
  - 选中 Tab 使用 `.regularMaterial` 胶囊
  - 保留 spring 选中动画

### Page Polish

Files:

- `HAL9000/Features/Today/TodayView.swift`
- `HAL9000/Features/Training/TrainingView.swift`
- `HAL9000/Features/Analysis/AnalysisView.swift`
- `HAL9000/Features/RaceLog/RaceLogView.swift`
- `HAL9000/Features/Profile/ProfileView.swift`

Updates:

- 页面背景统一接入 `AppBackground`。
- 页面标题改用 `AppColor.pageTitle`。
- 卡片改为动态 `AppColor.contentBackground`，并增加轻量阴影。
- 骨架屏和按钮背景改用动态色，避免浅色模式下白色透明元素不可见。
- Today 页白字内容改为动态 `AppColor.textPrimary`。

### Status Bar

File:

- `HAL9000/Info.plist`

Updates:

- 移除固定 `UIStatusBarStyleLightContent`，让系统根据当前显示模式自动选择状态栏颜色。

## Validation

Commands:

```bash
xcodebuild -project ~/hal9000-ios/HAL9000.xcodeproj -scheme HAL9000 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ~/hal9000-ios/HAL9000.xcodeproj -scheme HAL9000 -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

Result:

- iOS Simulator build: passed
- Generic iOS device build: passed

## Notes

- 当前为视觉重构第一版，未做系统 `TabView` 迁移。
- 如果后续决定完全采用系统 iOS 26 Tab Bar，可把 `RootView` 改为标准 `TabView`，让系统自动接管更多 Liquid Glass 行为。

## Patch 2026-05-18 20:00 - Today UI Debug

Files:

- `HAL9000/Features/Today/TodayView.swift`
- `HAL9000/DesignSystem/FloatingTabBar.swift`

Updates:

- Today 顶部增加安全区渐隐遮罩，避免滚动时卡片描边在状态栏下方露成横线。
- 训练状态里的短期负荷、长期负荷胶囊改用动态主/次文字色，修复浅色模式可读性不足。
- 训练负荷卡片的辅助说明从三级文字色提升到二级文字色。
- 底部浮动菜单选中态改用 `matchedGeometryEffect`，高亮胶囊现在会在 Tab 之间滑动。
- 底部浮动菜单增加横向拖拽切换，拖动底栏即可切到相邻 Tab。

Validation:

- iOS Simulator build: passed
- Generic iOS device build: passed
- Installed to connected iPhone: passed

## Patch 2026-05-18 22:04 - Swipe Back Runtime Fix

Files:

- `HAL9000/DesignSystem/SwipeBackSupport.swift`
- `HAL9000/Features/Today/TodayView.swift`

Issue:

- 上一版从辅助控制器的 parent 链查找 `UINavigationController`，在 SwiftUI `NavigationStack` + hidden toolbar 的层级下可能拿不到真正的导航控制器，导致左缘右滑没有反应。

Updates:

- 将 `SwipeBackSupport` 改为 `UIViewRepresentable` 探针，从当前窗口的 root controller 树递归查找最深层 `UINavigationController`。
- 保留手势代理，只有导航栈深度大于 1 时才允许左缘返回。
- 在 Today 根页面和 Today 明细页都挂载 `.supportsSwipeBack()`，确保 push 到详情后会再次启用系统 `interactivePopGestureRecognizer`。
- 允许返回手势和其他手势同时识别，降低与滚动视图手势竞争导致无响应的概率。

Validation:

- iOS Simulator build: passed
- Generic iOS device build: passed
- Installed to connected iPhone: passed

## Patch 2026-05-18 21:59 - Global Swipe Back Gesture

Files:

- `HAL9000/DesignSystem/SwipeBackSupport.swift`
- `HAL9000/Features/Today/TodayView.swift`
- `HAL9000/Features/RaceLog/RaceLogView.swift`
- `HAL9000.xcodeproj/project.pbxproj`

Updates:

- 新增 `SwipeBackSupport`，通过轻量 UIKit bridge 找到当前 `UINavigationController`。
- 在隐藏原生导航栏或使用自定义返回按钮时，重新启用系统 `interactivePopGestureRecognizer`。
- 手势只在导航栈深度大于 1 时开始，避免根页面误触。
- Today 明细页现在可以从屏幕左侧向右轻扫返回上一屏。
- Race Log 设置页的导航栈也接入同一能力，后续新增的 `NavigationStack` 可复用 `.supportsSwipeBack()`。

Validation:

- iOS Simulator build: passed
- Generic iOS device build: passed
- Installed to connected iPhone: passed

## Patch 2026-05-18 21:20 - Today Detail Drilldowns

Files:

- `HAL9000/Features/Today/TodayView.swift`
- `HAL9000/Features/Today/TodayViewModel.swift`
- `HAL9000/Health/HealthMetricModels.swift`
- `HAL9000/Health/HealthKitService.swift`
- `HAL9000/Health/TrainingLoadCalculator.swift`

Updates:

- Today 核心指标卡片改为可点击进入明细页：状态稳定、训练负荷、HRV 状态、体重、周跑量、月跑量。
- 状态稳定明细页展示判断依据，并用图表呈现短期/长期负荷比例的稳定区间和变化。
- 训练负荷明细页展示短期负荷和长期负荷曲线，支持 7 天、30 天、60 天、90 天切换。
- HRV 明细页展示正常区间和 HRV 变化曲线，支持 7 天、30 天、60 天、90 天切换。
- 体重明细页展示体重趋势，支持 7 天、30 天、60 天、90 天切换。
- 周跑量明细页按周一到周日统计跑步运动距离，并用柱状图展示最近 12 周趋势。
- 月跑量明细页按自然月统计跑步运动距离，并用柱状图展示最近 12 个月趋势。
- HealthKit 数据层新增 HRV、体重、周跑量、月跑量历史查询；周/月跑量只统计 `running` workout。
- 训练负荷计算器新增历史曲线计算，用同一套 ATL/CTL 逻辑保证 Today 总览和明细页一致。

Validation:

- iOS Simulator build: passed
- Generic iOS device build: passed
- Installed to connected iPhone: passed

## Patch 2026-05-18 20:42 - Official Liquid Glass Tab Bar

File:

- `HAL9000/DesignSystem/FloatingTabBar.swift`

Updates:

- 检测到当前 Xcode iOS 26.5 SDK 支持官方 SwiftUI Liquid Glass API。
- 底部导航在 iOS 26+ 使用 `GlassEffectContainer` 和 `.glassEffect(.regular.interactive(), in: Capsule())`。
- 选中态使用 `.glassEffectTransition(.matchedGeometry)`，让玻璃块在 Tab 之间动态融合移动。
- 移除上一版手工绘制的顶部静态高光线，避免出现用户圈出的“横线”假效果。
- 保留 iOS 17-25 的 material 降级实现，避免低系统版本崩溃。

Validation:

- iOS Simulator build: passed
- Generic iOS device build: passed
- Installed to connected iPhone: passed

## Patch 2026-05-18 20:43 - Remove Glass Highlight Line

File:

- `HAL9000/DesignSystem/FloatingTabBar.swift`

Updates:

- 确认代码里已无手工绘制的顶部横线。
- 横线来源判断为 iOS 26 外层玻璃和选中态内层玻璃叠加后的系统反光。
- 移除选中态内层 `.glassEffect`，保留外层官方 Liquid Glass。
- 选中态改为动态滑动的轻量 accent 胶囊，避免双层玻璃产生横向高光。

Validation:

- iOS Simulator build: passed
- Generic iOS device build: passed
- Installed to connected iPhone: passed

## Patch 2026-05-18 21:02 - Bottom Navigation Only

Files:

- `HAL9000/App/RootView.swift`
- `HAL9000/Features/Today/TodayView.swift`
- `HAL9000/Features/Training/TrainingView.swift`
- `HAL9000/Features/Analysis/AnalysisView.swift`
- `HAL9000/Features/RaceLog/RaceLogView.swift`
- `HAL9000/Features/Profile/ProfileView.swift`

Updates:

- 根据最新需求撤销 Apple Music 风格 mini-player 和全屏播放器交互。
- App 根布局恢复为页面内容 + 底部浮动导航栏。
- 保留底部导航栏的官方 Liquid Glass 外层和 matched geometry 选中态滑动。
- 页面底部滚动预留恢复为原导航栏高度，不再为播放器占位。

Validation:

- iOS Simulator build: passed
- Generic iOS device build: passed
- Installed to connected iPhone: passed
