# HAL9000 Race Log Development Spec

## 1. 目标

将 Race Log 页面接入 Intervals.icu，自动识别历史比赛，并把带坐标的比赛标记到地图上。

## 2. 数据来源

知识库文件：

- `/private/tmp/running-knowledge-base/references/intervals-icu-api-notes.md`

Intervals.icu 认证：

```text
Base URL: https://intervals.icu
Auth: Basic Auth
Username: API_KEY
Password: <Intervals.icu API Key>
```

关键接口：

```http
GET /api/v1/athlete/me
GET /api/v1/athlete/{athlete_id}/activities?oldest=YYYY-MM-DD&newest=YYYY-MM-DD
GET /api/v1/activity/{activity_id}/streams?types=latlng
```

## 3. 当前实现

文件：

- `~/hal9000-ios/HAL9000/Features/RaceLog/RaceLogView.swift`

首版为了减少 Xcode 工程文件变动，把 View、ViewModel、Intervals service、DTO 和展示 model 放在同一个 Swift 文件中。

## 4. 页面结构

Race Log 页面：

1. Header
   - `Race Log`
   - `Intervals.icu 比赛地图`
   - API Key 设置按钮
   - 刷新按钮

2. 设置 Sheet
   - API Key
   - Athlete ID，可留空自动读取

3. 比赛地图
   - 使用 MapKit
   - 将有坐标的比赛用 flag marker 标记

4. 统计卡
   - 比赛数量
   - 有地图坐标的比赛数量
   - 比赛总距离
   - 最快平均配速

5. 比赛列表
   - 名称
   - 日期
   - 距离
   - 时长
   - 平均配速
   - 地点，如 API 返回

## 5. 比赛识别规则

仅考虑 Intervals.icu 活动类型：

- `Run`
- `VirtualRun`

优先使用官方字段：

- `race == true`
- `sub_type == RACE`

再在活动 `name`、`category`、`sub_type`、`tags` 中搜索关键词：

```text
race
marathon
half marathon
10k
5k
trail race
比赛
半马
全马
马拉松
越野赛
竞赛
```

命中即视为比赛。

## 6. 坐标解析

优先级：

1. `start_latlng`
2. `latlng`
3. `end_latlng`
4. 活动名称/地点中的城市兜底坐标
5. `/api/v1/activity/{activity_id}/streams?types=latlng` 的首个轨迹点，仅在能得到合法经度时使用

没有坐标的比赛仍保留在列表，不渲染地图 marker。

已知 Intervals.icu 对部分 Garmin 活动的 `latlng` stream 只返回纬度序列，不能直接拆成经纬度。App 必须校验经度范围；中国城市赛事如果经度不在 `70...140`，应丢弃该坐标并使用城市兜底。

## 7. 当前限制

- API Key 首版用 `@AppStorage` 保存，后续应迁移到 Keychain。
- Intervals.icu 不一定为所有活动返回坐标字段。
- 比赛识别依赖关键词，后续应支持用户手动标记/取消标记。
- 不得内置 Athlete ID 或 API Key；API Key 应由用户输入，后续迁移到 Keychain 或后端代理。
- `start_date_local` 为无时区本地时间，需要用 `yyyy-MM-dd'T'HH:mm:ss` 兜底解析。
- 不再给 activities 加 `limit=200`，避免历史比赛被截断。

## 8. 验收清单

- [x] Race Log 不再是占位页。
- [x] 能填写 Intervals.icu API Key。
- [x] Athlete ID 可自动读取。
- [x] 能拉取 Intervals.icu activities。
- [x] 能自动识别比赛活动。
- [x] 能把有坐标的比赛标到地图上。
- [x] 无坐标比赛能显示在列表中。
- [x] 支持 Intervals.icu 无时区本地时间解析。
- [x] 支持用 activity streams 兜底解析比赛起点坐标。
- [x] 拒绝只有纬度序列的伪坐标，避免地图 marker 跑偏。
- [x] 历史活动不再被 200 条限制截断。
- [x] Simulator build 通过。
- [x] 真机通过用户输入 API Key 验证。
- [ ] 后续迁移 API Key 到 Keychain。
