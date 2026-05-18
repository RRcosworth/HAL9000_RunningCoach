# HAL9000 Analysis Page Development Spec

## 1. 目标

基于 `running-knowledge-base.zip` 开发 Analysis 页面，让用户能看到自己的训练趋势、负荷状态和下一步训练判断。

首版不做复杂后台推理，使用 HealthKit 本地数据 + 知识库规则生成可解释分析。

## 2. 知识库依据

使用文件：

- `SKILL.md`
- `references/data-analysis-workflow.md`

核心规则：

- 跑量是长期表现的重要基础。
- 训练应遵循难易交替，约 80% 轻松、20% 较难。
- CTL/ATL/TSB 用于判断长期能力、短期压力和新鲜度。
- 周跑量变异系数 `> 40%` 视为不稳定。
- 距上次跑步 `> 2 天` 时，优先打破停跑循环。

## 3. 当前实现

文件：

- `~/hal9000-ios/HAL9000/Features/Analysis/AnalysisView.swift`

为减少 Xcode 工程改动，首版将 View、ViewModel、Snapshot、Insight model 放在同一个 Swift 文件中。

## 4. 数据来源

当前从 HealthKit 读取：

```swift
HealthKitService.fetchRunningLoadDays(days: 42)
```

每一天包含：

- `date`
- `runningDistanceKm`
- `exerciseMinutes`
- `averageHeartRate`
- `restingHeartRate`

负荷计算复用：

```swift
TrainingLoadCalculator.calculate(days:)
```

## 5. 页面结构

Analysis 页面：

1. Header
   - `Analysis`
   - `基于 42 天跑步数据和训练知识库`
   - 刷新按钮

2. 状态卡
   - 当前训练状态
   - ATL
   - CTL
   - TSB
   - 今日建议

3. 跑量趋势
   - 6 周柱状图
   - 当前周高亮
   - `40 km/week` 参考线

4. 指标卡
   - 近 7 天跑量
   - 近 42 天跑量
   - 周稳定性
   - 距上次跑步天数

5. 知识库分析
   - 训练量分析
   - 负荷分析
   - 稳定性分析
   - 连续性分析
   - 80/20 分析占位

## 6. 计算规则

### 6.1 周跑量

- 用周一作为每周开始。
- 每周跑量 = 该周 daily `runningDistanceKm` 汇总。

### 6.2 变异系数

```text
CV = standardDeviation(weeklyMileage) / mean(weeklyMileage)
```

- 只统计已完成周。
- 少于 3 个有效周时显示“需要更多周数据”。
- `CV > 40%` 提示波动偏大。

### 6.3 TSB

```text
TSB = CTL - ATL
```

- 正值表示相对新鲜。
- 负值表示短期压力高于长期能力。

### 6.4 训练量参考线

首版按知识库 workflow 的业余 5K 基础跑量下沿：

```text
40 km/week
```

注意：这是背景参考线，不是所有用户的硬性目标。

## 7. 80/20 后续

首版无法准确计算 80/20，因为当前 HealthKitService 还没有读取每次跑步的心率分区时间。

后续需要新增：

- workout 内心率样本查询。
- 基于用户最大心率/阈值心率的 zone 分类。
- 或接 Intervals.icu zone time 数据。

UI 当前保留“等待心率分区”洞察卡。

## 8. 验收清单

- [x] Analysis 不再是占位页。
- [x] 页面能请求 Apple Health 授权。
- [x] Apple Health 授权请求只触发一次，Tab 切换复用本地授权状态。
- [x] 页面能显示 42 天跑步趋势。
- [x] 页面能显示 ATL/CTL/TSB。
- [x] 页面能显示周跑量稳定性。
- [x] 页面能显示距上次跑步天数。
- [x] 页面包含基于知识库的训练洞察。
- [x] Simulator build 通过。
- [ ] 真机打开检查 HealthKit 数据是否正常渲染。
- [ ] 后续接入心率分区后启用真实 80/20 分析。
