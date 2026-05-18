# Training Export Development Spec

## 目标

Training 模块需要把 Hermes 动态生成的本周跑步课表导出到可穿戴设备生态：

- Apple Watch：通过 WorkoutKit 写入 Apple Watch 的体能训练计划。
- Garmin：生成 Garmin 可识别的 TCX 训练文件，通过系统分享交给 Garmin Connect / 文件 App。

当前版本先完成可用闭环，不做 Garmin OAuth 自动推送。

## 页面入口

文件：`HAL9000/Features/Training/TrainingView.swift`

在本周进度和统计卡片下方新增 `导出课表` 卡片：

- `Apple Watch` 按钮：同步本周未完成跑步训练。
- `Garmin` 按钮：生成 `.tcx` 文件。
- `分享 TCX` 按钮：文件生成后使用系统 `ShareLink` 分享。
- 状态文案：idle / exporting / succeeded / failed。

## 数据筛选口径

导出服务只处理：

- `TrainingSession.isCompleted == false`
- 类型为跑步：`type` 包含 `run` 或图标为 `figure.run`
- 有计划距离或计划时长

休息日、已完成训练、非跑步训练不导出。

## Apple Watch 实现

文件：`HAL9000/Features/Training/TrainingExportService.swift`

使用 `WorkoutKit`：

1. 检查 `WorkoutScheduler.isSupported`
2. 读取 `WorkoutScheduler.shared.authorizationState`
3. 首次使用时调用 `requestAuthorization()`
4. 将每个 `TrainingSession` 转成 `CustomWorkout`
5. 用 `WorkoutScheduler.shared.schedule(_:at:)` 写入 Apple Watch 训练计划

训练结构：

- Activity：`.running`
- Location：`.unknown`
- Display Name：`TrainingSession.exportTitle`
- Goal：
  - 优先 `.distance(km, .kilometers)`
  - 没有距离时使用 `.time(minutes, .minutes)`
  - 都没有则 `.open`
- Alert：
  - 如果 `zone` 可解析为 Z1-Z5，则写入 `HeartRateZoneAlert`

计划时间：

- 日期来自 `TrainingSession.date`
- 默认时间：07:00

稳定 ID：

- 使用 `session.id + date + title` 生成稳定 UUID，降低重复点击后生成重复计划的概率。

## Garmin 实现

文件：`HAL9000/Features/Training/TrainingExportService.swift`

当前版本生成 `HAL9000-Training-yyyyMMdd-HHmm.tcx`：

- XML 根节点：`TrainingCenterDatabase`
- 节点：`Workouts > Workout Sport="Running"`
- 每节训练写一个 `Step`
- Duration：
  - 有距离：`Distance_t / Meters`
  - 无距离：`Time_t / Seconds`
- Target：
  - `HeartRateZone_t`
  - zone 缺失时默认 Z2

导出位置：

- `FileManager.default.temporaryDirectory`
- UI 使用 `ShareLink(item: url)` 分享。

## 当前限制

- Garmin Connect 的自动写入需要 Garmin OAuth / Partner API 权限，当前没有接入。
- TCX 文件的 Garmin 导入兼容性需要真机 + Garmin Connect 实测。
- Apple Watch 计划同步需要已配对 Apple Watch，并允许 WorkoutKit 授权。

## 验证

- `xcodebuild -project ~/hal9000-ios/HAL9000.xcodeproj -scheme HAL9000 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project ~/hal9000-ios/HAL9000.xcodeproj -scheme HAL9000 -destination 'generic/platform=iOS' -allowProvisioningUpdates build`
- 结果：通过
