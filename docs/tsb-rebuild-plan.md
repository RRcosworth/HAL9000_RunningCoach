# HAL9000 TSB 模型重构 — 开发计划

> 基于 [fellrnr.com TSB Model](https://fellrnr.com/wiki/Modeling_Human_Performance#The_TSB_Model)  
> 目标页面：`TodayView` → `readinessDetail`（当前「状态稳定」页面）  
> 项目路径：`~/hal9000-ios/`

---

## 一、目标效果

![TSB 目标效果](目标：TrainingPeaks 风格三线图 + 负荷聚焦 + 心率强度)

重构后「状态稳定」页面包含 **4 个卡片**：

| # | 卡片 | 内容 |
|---|------|------|
| 1 | **Fitness (TSB 模型)** | CTL/ATL/TSB 三指标 + 三线趋势图 + 时间范围选择器 |
| 2 | **Training Load Focus** | 无氧/高有氧/低有氧 负荷分布 + 每日柱状图 |
| 3 | **Training Load Ratio** | ATL/CTL 比值 + 彩色量表 + 历史曲线 |
| 4 | **Heart Rate Intensity** | 心率五区分布 + 百分比条 + 各区明细 |

---

## 二、TSB 核心公式

### 指数加权移动平均 (EWMA)
```
CTL_today = CTL_yesterday + (TSS_day - CTL_yesterday) / time_constant_ctl
ATL_today = ATL_yesterday + (TSS_day - ATL_yesterday) / time_constant_atl
TSB_today = CTL_yesterday - ATL_yesterday
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `time_constant_ctl` | 42 天 | Chronic Training Load 时间常数 |
| `time_constant_atl` | 7 天 | Acute Training Load 时间常数 |
| TSS_day | 日训练负荷 | 每日训练刺激分数 |

### TSB 解读

| TSB 范围 | 状态 | 含义 |
|----------|------|------|
| > +10 | Fresh | 体能充沛，适合比赛 |
| -10 ~ +10 | Neutral | 维持状态 |
| -10 ~ -30 | Fatigue | 疲劳积累 |
| < -30 | High Risk | 过度训练风险 |

---

## 三、文件变更清单

```
修改文件：
├── HAL9000/Health/TrainingLoadCalculator.swift    ← 核心：改为 CTL/ATL/TSB 算法
├── HAL9000/Health/HealthMetricModels.swift        ← 新增 TSB 相关模型
├── HAL9000/Features/Today/TodayViewModel.swift    ← 新增 HR 区间、TSB 数据获取
├── HAL9000/Features/Today/TodayView.swift         ← 重建 readinessDetail UI
└── HAL9000/Health/HealthKitService.swift          ← 新增心率区间查询方法

新增文件：
├── HAL9000/Health/TSBCalculator.swift             ← 纯 TSB 计算引擎
├── HAL9000/Health/HeartRateZoneCalculator.swift   ← 心率区间计算
└── HAL9000/Features/Today/TSBDetailView.swift     ← TSB 详情页（可选独立文件）
```

---

## 四、分步实施

### 第 1 步：创建 `TSBCalculator.swift`

新建文件，纯函数计算引擎，不依赖 SwiftUI。

```swift
// HAL9000/Health/TSBCalculator.swift

struct TSBPoint {
    let date: Date
    let ctl: Double       // Fitness
    let atl: Double       // Fatigue
    let tsb: Double       // Form = CTL - ATL
}

struct TSBResult {
    let current: TSBPoint
    let history: [TSBPoint]
}

enum TSBState {
    case fresh       // TSB > 10
    case neutral     // -10 <= TSB <= 10
    case fatigued    // -30 <= TSB < -10
    case highRisk    // TSB < -30
    case noData
}

struct TSBCalculator {
    let ctlTimeConstant: Double = 42
    let atlTimeConstant: Double = 7

    /// 从每日 TSS 序列计算 CTL/ATL/TSB 历史
    func calculate(dailyTSS: [(date: Date, tss: Double)]) -> TSBResult {
        // 按日期升序排列
        let sorted = dailyTSS.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else {
            return TSBResult(current: TSBPoint(date: Date(), ctl: 0, atl: 0, tsb: 0), history: [])
        }

        var ctl = sorted.first!.tss  // 初始 CTL = 第一天 TSS
        var atl = sorted.first!.tss  // 初始 ATL = 第一天 TSS
        var history: [TSBPoint] = []

        for day in sorted {
            let alphaCTL = 1.0 / ctlTimeConstant
            let alphaATL = 1.0 / atlTimeConstant
            ctl = ctl + alphaCTL * (day.tss - ctl)
            atl = atl + alphaATL * (day.tss - atl)
            let tsb = ctl - atl
            history.append(TSBPoint(date: day.date, ctl: ctl, atl: atl, tsb: tsb))
        }

        let current = history.last ?? TSBPoint(date: Date(), ctl: 0, atl: 0, tsb: 0)
        return TSBResult(current: current, history: history)
    }

    func state(for tsb: Double) -> TSBState {
        if tsb > 10 { return .fresh }
        if tsb >= -10 { return .neutral }
        if tsb >= -30 { return .fatigued }
        return .highRisk
    }
}
```

**关键点：**
- `alpha = 1 / time_constant` 是 EWMA 的标准公式
- 初始 CTL/ATL 用第一天的 TSS 作为种子值
- TSB = CTL - ATL（注意：通常是 CTL_yesterday - ATL_yesterday，但用当天 CTL-ATL 也可，差异很小）

---

### 第 2 步：更新 `HealthMetricModels.swift`

```swift
// 在 HealthMetricModels.swift 末尾追加

// MARK: - TSB Model

struct TSBDisplayData: Equatable {
    let ctl: Double          // Fitness
    let atl: Double          // Fatigue
    let tsb: Double          // Form
    let state: TSBState
    let stateTitle: String
    let history: [TSBChartPoint]

    struct TSBChartPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let ctl: Double
        let atl: Double
        let tsb: Double
    }
}

struct HeartRateZoneDistribution: Equatable {
    let period: String              // e.g. "May 11 – 18, 2026"
    let zones: [HRZoneBreakdown]
    let totalMinutes: Double
}

struct HRZoneBreakdown: Identifiable, Equatable {
    let id = UUID()
    let zone: Int                   // 1-5
    let name: String                // "Very Easy"
    let rangeText: String           // "93–111 bpm"
    let minutes: Double
    let percentage: Double          // 0-100
    let colorName: String           // "blue", "green", "yellow", "orange", "red"
}

struct DailyLoadFocus: Equatable {
    let date: Date
    let anaerobic: Double
    let highAerobic: Double
    let lowAerobic: Double
    let other: Double
}

struct TrainingLoadFocusData: Equatable {
    let period: String
    let anaerobic: Double
    let anaerobicPercent: Double
    let highAerobic: Double
    let highAerobicPercent: Double
    let lowAerobic: Double
    let lowAerobicPercent: Double
    let dailyBreakdown: [DailyLoadFocus]
}
```

---

### 第 3 步：创建 `HeartRateZoneCalculator.swift`

```swift
// HAL9000/Health/HeartRateZoneCalculator.swift

struct HeartRateZoneCalculator {

    /// 根据最大心率百分比划分五区
    /// Zone 1: 50-60%  (Very Easy)
    /// Zone 2: 60-70%  (Easy)
    /// Zone 3: 70-80%  (Moderate)
    /// Zone 4: 80-90%  (Hard)
    /// Zone 5: 90-100% (Very Hard)
    func classify(heartRate: Double, maxHR: Double) -> Int {
        let pct = heartRate / maxHR
        switch pct {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default:      return 5
        }
    }

    func zoneName(_ zone: Int) -> String {
        ["", "Very Easy", "Easy", "Moderate", "Hard", "Very Hard"][zone]
    }

    func zoneRange(zone: Int, maxHR: Double) -> String {
        let low  = [0, 0.50, 0.60, 0.70, 0.80, 0.90][zone] * maxHR
        let high = [0, 0.60, 0.70, 0.80, 0.90, 1.00][zone] * maxHR
        return String(format: "%.0f–%.0f bpm", low, high)
    }

    /// 按 Training Load Type 分类心率（用于 Training Load Focus）
    enum LoadType {
        case lowAerobic     // < 70% maxHR
        case highAerobic    // 70-90% maxHR
        case anaerobic      // > 90% maxHR
    }

    func loadType(heartRate: Double, maxHR: Double) -> LoadType {
        let pct = heartRate / maxHR
        if pct < 0.70 { return .lowAerobic }
        if pct < 0.90 { return .highAerobic }
        return .anaerobic
    }
}
```

---

### 第 4 步：更新 `HealthKitService.swift`

新增两个查询方法：

```swift
// 新增到 HealthKitServing 协议
func fetchHeartRateSamples(days: Int) async throws -> [(date: Date, value: Double)]
func fetchMaxHeartRate() async throws -> Double
```

**实现要点：**
- `fetchHeartRateSamples(days:)` — 查询近 N 天所有 workout 中的心率样本（`HKQuantityType(.heartRate)`），关联到 `HKWorkout`。返回 `(date, bpm)` 数组。
- `fetchMaxHeartRate()` — 从 HealthKit 读取用户设置的 maxHR，或使用 `220 - age` 公式估算。

具体实现参考现有 `fetchRunningLoadDays` 模式，使用 `HKSampleQuery` + `HKWorkout` predicate。

---

### 第 5 步：更新 `TrainingLoadCalculator.swift`

保持现有接口兼容，内部改用 TSBCalculator：

```swift
// 在现有 calculate() 中，将 dailyLoad() 作为 TSS 输入 TSBCalculator
// dailyLoad 已经包含了距离、心率因子的计算，可以继续作为 TSS 的代理
// 后续可以接入真正的 rTSS（running TSS）计算

func calculateTSB(days: [RunningLoadDay]) -> TSBResult {
    let dailyTSS = days.map { day in
        (date: day.date, tss: dailyLoad(day))
    }
    return TSBCalculator().calculate(dailyTSS: dailyTSS)
}
```

---

### 第 6 步：更新 `TodayViewModel.swift`

```swift
// 新增 @Published 属性
@Published var tsbData: TSBDisplayData?
@Published var loadFocus: TrainingLoadFocusData?
@Published var hrDistribution: HeartRateZoneDistribution?

// 在 loadHealthSnapshot() 中新增并发获取
async let tsbResult = result { [self] in try await self.loadTSBData() }
async let focusResult = result { [self] in try await self.loadLoadFocus() }
async let hrResult = result { [self] in try await self.loadHRDistribution() }
```

新增三个 private 方法：

1. **`loadTSBData()`** — 获取 180 天 load data，调 `TSBCalculator.calculate()`，转换 state
2. **`loadLoadFocus()`** — 获取 28 天心率样本，按 `heartRate / maxHR` 分三类（<70%, 70-90%, >90%），汇总百分比和每日分布
3. **`loadHRDistribution()`** — 获取近 7 天心率样本，分五区，统计分钟数和百分比

---

### 第 7 步：重建 `readinessDetail` UI（核心）

这是工作量最大的部分。替换 `TodayView.swift` 中 `TodayMetricDetailView` 的 `route == .readiness` 分支。

```swift
// --- 新增 TSB 详情视图（替换现有 readinessDetail）---

private var tsbDetailView: some View {
    VStack(alignment: .leading, spacing: 16) {

        // ═══ 卡片 1: Fitness (TSB 模型) ═══
        tsbFitnessCard

        // ═══ 卡片 2: Training Load Focus ═══
        loadFocusCard

        // ═══ 卡片 3: Training Load Ratio ═══
        loadRatioCard

        // ═══ 卡片 4: Heart Rate Intensity ═══
        heartRateIntensityCard
    }
}
```

---

### 第 7.1 步：卡片 1 — Fitness (TSB 三指标 + 三线图)

```
┌─────────────────────────────────────┐
│  Fitness                         ··· │
│  ┌──────┬──────┬──────┐             │
│  │  CTL │  ATL │  TSB │             │
│  │  18  │  11  │  +8  │             │
│  │Fitness│Fatigue│ Form │             │
│  └──────┴──────┴──────┘             │
│                                      │
│  时间范围: [30D] 6W 3M 6M 1Y        │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  📈 CTL(蓝) ATL(红) TSB(绿)  │   │
│  │    三线趋势图                 │   │
│  │    Y轴: 0-100                │   │
│  │    X轴: 日期                 │   │
│  └──────────────────────────────┘   │
│  About TSB Model →                   │
└─────────────────────────────────────┘
```

**Chart 实现：**
```swift
Chart(tsbData.history) { point in
    // CTL - 蓝色实线 + 半透明填充
    AreaMark(x: ..., y: point.ctl)
        .foregroundStyle(.blue.opacity(0.1))
    LineMark(x: ..., y: point.ctl)
        .foregroundStyle(.blue)
    
    // ATL - 红色实线
    LineMark(x: ..., y: point.atl)
        .foregroundStyle(.red)
    
    // TSB - 绿色虚线，Y轴右轴或叠加
    LineMark(x: ..., y: point.tsb)
        .foregroundStyle(.green)
}
```

**时间范围选择器：** `Picker(.segmented)` 带 `["30D", "6W", "3M", "6M", "1Y"]`

---

### 第 7.2 步：卡片 2 — Training Load Focus

```
┌─────────────────────────────────────┐
│  Training Load Focus             ··· │
│  Apr 21 – May 18, 2026              │
│                                      │
│  Anaerobic    █ 2%    9              │
│  High Aerobic ████████████ 95%  418  │
│  Low Aerobic  █ 3%    12             │
│                                      │
│  Daily Training Load Focus           │
│  ┌──────────────────────────────┐   │
│  │  📊 每日堆叠柱状图            │   │
│  │  紫=无氧 橙=高有氧 蓝=低有氧 │   │
│  │  X轴: 日期  Y轴: 负荷        │   │
│  └──────────────────────────────┘   │
│  Training Method: % Max HR           │
└─────────────────────────────────────┘
```

**进度条实现：**
```swift
// 三条彩色条，填充比例 = 百分比
HStack(spacing: 0) {
    Rectangle().fill(.purple).frame(width: pct(anaerobic))
    Rectangle().fill(.orange).frame(width: pct(highAerobic))
    Rectangle().fill(.blue).frame(width: pct(lowAerobic))
}
.frame(height: 8)
.clipShape(Capsule())
```

**每日柱状图：** 堆叠 BarMark：
```swift
Chart(dailyData) { day in
    BarMark(x: day.date, y: day.anaerobic)
        .foregroundStyle(.purple)
    BarMark(x: day.date, y: day.highAerobic)
        .foregroundStyle(.orange)
    BarMark(x: day.date, y: day.lowAerobic)
        .foregroundStyle(.blue)
}
```

---

### 第 7.3 步：卡片 3 — Training Load Ratio

```
┌─────────────────────────────────────┐
│  Training Load Ratio                 │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ ●━━━━━━━━━━━━━━━━━━━━━━━━━━  │   │
│  │ 蓝     绿     橙      红     │   │
│  │ 0.6                          │   │
│  │ Low                          │   │
│  └──────────────────────────────┘   │
│  Your short-term load is lower      │
│  than your long-term load.          │
│                                      │
│  Daily Training Load Ratio          │
│  Nov 18 – May 18                    │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  📈 ATL/CTL 比值历史曲线     │   │
│  │  线色随比值变化:             │   │
│  │  <0.8 蓝  0.8-1.1 绿        │   │
│  │  1.1-1.5 橙  >1.5 红        │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

**彩色量表条实现：**
```swift
GeometryReader { geo in
    ZStack(alignment: .leading) {
        // 背景渐变条
        LinearGradient(
            colors: [.blue, .green, .orange, .red],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 8)
        .clipShape(Capsule())
        
        // 指示器圆点
        Circle()
            .fill(.white)
            .frame(width: 12, height: 12)
            .shadow(radius: 2)
            .offset(x: geo.size.width * indicatorPosition)
    }
}
```

**比值着色曲线：** 使用 `LineMark` 配合分段着色，或使用多个 `LineMark` 按阈值分段（Swift Charts 对单线多色支持有限，可以用 `RectangleMark` 色块 + `LineMark` 叠加实现）。

---

### 第 7.4 步：卡片 4 — Heart Rate Intensity

```
┌─────────────────────────────────────┐
│  Heart Rate Intensity               │
│  May 11 – 18, 2026      [1W] ...    │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ ████░░░░░░░░░░░░░░░░░░░░░░░  │   │
│  │ 蓝  绿  黄  橙  红            │   │
│  └──────────────────────────────┘   │
│                                      │
│  ● Very Easy   93–111 bpm  32% 31min│
│  ● Easy       112–130 bpm   8%  8min│
│  ● Moderate   131–148 bpm  17% 17min│
│  ● Hard       149–167 bpm  42% 41min│
│  ● Very Hard     ≥168 bpm   0% 20s  │
│                                      │
│  Training Method: % Max HR           │
│                                      │
│  Heart Rate Distribution by Activity │
│  2,207 Workouts                      │
│  Z1 Z2 Z3 Z4 Z5                      │
└─────────────────────────────────────┘
```

**区间色条实现：**
```swift
HStack(spacing: 0) {
    ForEach(zones) { zone in
        Rectangle()
            .fill(zoneColor(zone.zone))
            .frame(width: pct(zone.percentage))
    }
}
.frame(height: 12)
.clipShape(RoundedRectangle(cornerRadius: 6))
```

**各区明细行：**
```swift
ForEach(zones) { zone in
    HStack {
        Circle().fill(zoneColor).frame(width: 10)
        Text(zone.name).frame(width: 90, alignment: .leading)
        Text(zone.rangeText).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text("\(Int(zone.percentage))%")
        Text(formatMinutes(zone.minutes))
            .frame(width: 50, alignment: .trailing)
    }
}
```

---

## 五、数据流示意

```
HealthKit (Apple Watch)
    │
    ├── 每日跑步距离、时间、心率 → dailyLoad() → TSS
    │                                           │
    │                                    TSBCalculator
    │                                           │
    │                              ┌─ CTL (Fitness) ─┐
    │                              ├─ ATL (Fatigue)  ├─ 卡片 1
    │                              └─ TSB (Form) ────┘
    │
    ├── 心率样本 (workout 内逐秒) → HeartRateZoneCalculator
    │                                           │
    │                              ┌─ 五区分布 ─── 卡片 4
    │                              └─ 三类负荷 ─── 卡片 2
    │
    └── ATL/CTL 比值 ───────────────────────────── 卡片 3
```

---

## 六、实施顺序建议

| 优先级 | 步骤 | 依赖 | 预估工时 |
|--------|------|------|----------|
| 1 | `TSBCalculator.swift` | 无 | 30min |
| 2 | `HeartRateZoneCalculator.swift` | 无 | 20min |
| 3 | 更新 `HealthMetricModels.swift` | 1 | 15min |
| 4 | 更新 `HealthKitService.swift`（心率查询）| 无 | 45min |
| 5 | 更新 `TrainingLoadCalculator.swift` | 1 | 20min |
| 6 | 更新 `TodayViewModel.swift` | 4,5 | 45min |
| 7 | **重建 readinessDetail UI（核心）** | 6 | 2-3h |
| 7.1 | 卡片 1: TSB 三线图 | 6 | 45min |
| 7.2 | 卡片 2: Load Focus | 6 | 30min |
| 7.3 | 卡片 3: Load Ratio | 6 | 30min |
| 7.4 | 卡片 4: HR Intensity | 6 | 30min |
| 8 | 调色 + 暗黑模式适配 | 7 | 20min |
| **合计** | | | **约 6-7 小时** |

---

## 七、配色映射

与用户截图中 TrainingPeaks 风格对齐：

| 指标 | 颜色 | Hex |
|------|------|-----|
| CTL (Fitness) | 蓝色 | `#3388FF` |
| ATL (Fatigue) | 红色/橙色 | `#FF5533` |
| TSB (Form) | 绿色 | `#33CC66` |
| Anaerobic | 紫色 | `#9944FF` |
| High Aerobic | 橙色 | `#FF8833` |
| Low Aerobic | 浅蓝 | `#55AADD` |
| HR Z1 | 蓝色 | `#3388FF` |
| HR Z2 | 绿色 | `#33CC66` |
| HR Z3 | 黄色 | `#FFCC00` |
| HR Z4 | 橙色 | `#FF8833` |
| HR Z5 | 红色 | `#FF3333` |

在 `AppColor.swift` 中新增：
```swift
static let tsbFitness = Color(hex: "3388FF")
static let tsbFatigue = Color(hex: "FF5533")
static let tsbForm    = Color(hex: "33CC66")
static let anaerobic  = Color(hex: "9944FF")
// ...
```

---

## 八、注意事项

1. **现有 TodayView 向下兼容**：`readinessDetail` 改为 `tsbDetailView`，保留其他 detail 页面不变（HRV、体重、跑量等）
2. **数据不足时降级**：TSB 需要 ≥ 42 天数据才能稳定，不足时显示「需要更多训练数据」占位
3. **心率数据可能很大**：workout 内逐秒心率样本可达数万条，查询时用 `HKStatisticsQuery` 聚合而非逐条拉取
4. **最大心率获取**：优先读 HealthKit `HKQuantityType(.maximumHeartRate)`，无数据时 `220 - age`
5. **现有 dailyLoad() 作为 TSS 代理**：真正的 rTSS 需要配速 vs 阈值配速对比，可作为后续优化
6. **不要改 AppTab 和 RootView**：只改 `TodayView` 内的 detail 页面

---

## 九、验证检查点

- [ ] CTL 曲线平滑缓慢，ATL 曲线波动较大
- [ ] TSB 在减量训练后转为正数（Fresh）
- [ ] 心率五区分布加起来 = 100%
- [ ] 无氧/高有氧/低有氧 三条进度条视觉比例正确
- [ ] ATL/CTL 比值彩色量表指示器在正确位置
- [ ] 暗黑模式下所有颜色正常显示
- [ ] 首次启动无数据时不崩溃
