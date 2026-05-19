# HAL9000 跑步私教 · iOS 原生 App

完全原生 SwiftUI 重写，非 WebView 套壳。

## 快速启动

```bash
open ~/hal9000-ios/HAL9000.xcodeproj
```

1. Xcode → Signing & Capabilities → 用自己的 Apple ID
2. Bundle Identifier 改为 `com.你的名字.runnercoach`
3. 选 iPhone 模拟器或真机 → ⌘R

## 项目结构

```
HAL9000/
├── App/                    # AppTab, NativeApp, RootView
├── DesignSystem/           # AppColor, Typography, FloatingTabBar, PrimaryButton, EmptyState
├── Features/
│   ├── Training/           # 训练历史 + Hermes 动态训练计划
│   ├── Today/              # Apple Health 健康与跑步 dashboard
│   ├── Analysis/           # 跑步知识库驱动的训练分析
│   ├── RaceLog/            # Intervals.icu 比赛地图
│   ├── Coach/              # Hermes AI 教练对话
│   └── Profile/            # 占位
├── Networking/             # APIClient (async/await), Endpoint, APIError
├── Persistence/            # UserSessionStore, CacheStore
├── Resources/              # Assets.xcassets, training-mascot.png
└── Info.plist
```

## 对齐开发文档

与 `iOS-native-app-development-spec.md` 对照：

| 章节 | 状态 |
|---|---|
| §3 技术选型 | ✅ SwiftUI + MVVM + iOS 17+ + async/await |
| §4 信息架构 | ✅ 6 Tab: Today / Training / Analysis / Race Log / Coach / Profile |
| §5 视觉设计 | ✅ ZStack 三层结构：hero + 内容 + 悬浮 Tab Bar |
| §5.4 浮动 Tab Bar | ✅ 胶囊形、毛玻璃、选中蓝色、椭圆高亮 |
| §7 项目结构 | ✅ 目录结构与文档一致 |
| §8 网络层 | ✅ APIClient + Codable + 错误处理 |
| §9 Training 首屏 | ✅ 本周进度 + 动态训练计划 + 训练历史 |
| §10 适配 | ✅ Portrait only, iOS 17+, Safe Area |
| M1 原生壳 | ✅ 5 Tab 可切换，浮动导航 |
| M2 Training 首屏 | ✅ Training dashboard + weekly progress + plan/history |
| M3 数据接入 | ✅ `/api/weekly` 真实 API, loading/empty/error/loaded |
| M4 Today 健康页 | ✅ HealthKit + ATL/CTL + HRV + 体重 + 跑量 |
| M5 Training 动态计划 | ✅ 基于 Hermes 周计划和完成进度生成下一步建议 |
| M6 Training 课表导出 | ✅ Apple Watch WorkoutKit + Garmin TCX 分享 |
| M6 Analysis 训练分析 | ✅ 42天趋势 + ATL/CTL/TSB + 稳定性 + 知识库洞察 |
| M7 Race Log 比赛地图 | ✅ Intervals.icu API + 比赛识别 + MapKit 标记 |
| M8 Coach AI 教练 | ✅ Coach Tab + Hermes Gateway + 上下文注入 |

## 里程碑进度

- [x] **M1** 原生壳与导航
- [x] **M2** Training 首屏
- [x] **M3** 数据接入 (APIClient + ViewModel + 缓存)
- [x] **M4** Today Apple Health 页面
- [x] **M5** Training 动态计划与历史
- [x] **M6** Training 课表导出到 Apple Watch / Garmin
- [x] **M6** Analysis 训练分析
- [x] **M7** Race Log 比赛地图
- [x] **M8** Coach AI 教练 MVP
- [ ] **M8** Profile 迁移
- [ ] **M9** 测试与发布

## Training 页面当前口径

- 数据源：`GET /api/weekly?date=YYYY-MM-DD`，由 Hermes 后端返回本周训练、活动汇总、诊断阶段和计划摘要。
- 页面结构：顶部 Training 标题、本周进度卡、距离/时长/次数卡、动态训练计划、训练历史。
- 导出能力：未完成跑步课表可同步到 Apple Watch 体能训练计划，也可生成 Garmin TCX 文件通过系统分享导入 Garmin Connect。
- 动态计划：未完成的 plan item 显示在“动态训练计划”；已完成或带实际数据的 item 显示在“训练历史”。
- 进度建议：根据 `target_km`、`completed_km`、`remaining_km` 和训练阶段生成轻量建议，避免用一次训练硬补剩余跑量。
- 兜底：如果接口没有 plan summary，就从 plan item 的 planned/actual distance 汇总目标和完成量。

## Analysis 页面当前口径

- 知识来源：`running-knowledge-base.zip` 中 `SKILL.md` 与 `references/data-analysis-workflow.md`。
- 数据来源：Apple Health / HealthKit 的 running workouts，经 `HealthKitService.fetchRunningLoadDays(days: 42)` 汇总。
- 授权策略：`HealthKitService` 记录本地授权请求版本；用户完成一次 Apple 健康授权流程后，Today / Analysis 只复用状态读取数据，不在 Tab 切换时再次触发授权弹窗。
- 展示内容：近 7 天跑量、近 42 天跑量、6 周跑量趋势、ATL/CTL/TSB、周跑量稳定性、距上次跑步天数。
- 分析规则：
  - 跑量参考线暂按知识库中业余 5K 基础跑量下沿 `40 km/week` 展示。
  - 周跑量变异系数 `> 40%` 判定为波动偏大。
  - 距上次跑步 `> 2 天` 优先提示先打破停跑循环。
  - ATL/CTL/TSB 复用 Today 的 `TrainingLoadCalculator`。
- 80/20 强度分析首版先占位；后续需要接入心率分区时间或 workout effort distribution。

## Race Log 页面当前口径

- 数据源：Intervals.icu API。
- 认证：Basic Auth，用户名固定 `API_KEY`，密码为 Intervals.icu settings 页面生成的 API Key。
- 不内置 API Key 或 Athlete ID；用户在页面内填写 API Key，Athlete ID 可留空自动读取。
- 活动拉取：`GET /api/v1/athlete/{athlete_id}/activities`，默认回看 8 年，不加 `limit=200` 以免漏掉历史比赛。
- 比赛识别：仅识别 `Run` / `VirtualRun`，优先使用 `race=true` / `sub_type=RACE`，再用名称、分类、标签关键词识别。
- 地图标记：优先读取 `start_latlng`，兜底读取 `latlng` / `end_latlng`；坐标缺失时用比赛名称中的城市定位。`latlng` stream 如果只返回纬度序列会被拒绝，避免把纬度误当经度。
- 后续增强：手动标记某次活动为比赛、Keychain 或后端代理保存 API Key。

## Coach 页面当前口径

- 入口：第 6 个 Tab `Coach`，提供原生 SwiftUI 聊天界面。
- 上下文：发送前实时收集 Apple Health 中的 TSB/CTL/ATL、训练阶段、周跑量、HRV、心率分区和最近活动。
- 数据源：`POST /api/coach/chat`，请求体包含 `context`、用户 `message` 和最近 20 条本地对话历史。
- Markdown：原生渲染粗体、列表、代码块和 Markdown 表格，不使用 WebView。
- 历史：最近 100 条消息存入本机 UserDefaults，冷启动后可继续查看。
- Gateway：`HermesGateway/coach_gateway.py` 提供 Flask 路由，默认调用 `hermes ask --skill running-knowledge-base --no-interactive`。
- Mock：调试时可请求 `/api/coach/chat?mock=true`，无需真实 Hermes 即可验证 iOS 链路。

启动 Gateway 示例：

```bash
python3 HermesGateway/coach_gateway.py --host 127.0.0.1 --port 5055
```

真机访问本机 Gateway 时，把 Profile 里的本地服务器地址设为 Mac 的局域网 IP，端口设为 `5055`。
