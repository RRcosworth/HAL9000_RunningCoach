# HAL9000 Profile Page Development Spec

## 1. 目标

Profile 页面从占位页升级为个人中心，用于展示个人信息、数据源连接状态、AI 配置和版本信息。

参考视觉：

- 顶部个人信息
- 白色圆角分组卡片
- 数据源连接状态
- AI 配置状态
- 关于与版本信息

## 2. 当前实现

文件：

- `~/hal9000-ios/HAL9000/Features/Profile/ProfileView.swift`

首版仍然保持单文件 SwiftUI，避免大幅改动 Xcode 工程结构。

## 3. 页面模块

### 3.1 个人信息

展示：

- 用户名：从本地配置读取，未配置时显示 `Runner`
- 产品身份：`HAL9000 Runner Coach`
- 状态标签：开发版、本地数据

### 3.2 数据源

展示三类数据源：

1. `Apple Health`
   - 状态：已接入
   - 用途：跑步、HRV、体重、运动记录
   - 说明：Today / Analysis 使用 HealthKit 本地数据

2. `Intervals.icu`
   - 状态：按 `@AppStorage("intervalsApiKey")` 判断
   - Athlete ID：优先显示用户配置；未配置时显示未连接
   - 用途：Race Log 比赛地图、活动识别

3. `Strava`
   - 状态：未连接
   - 用途：预留佳明运动详情、海拔、分段数据

### 3.3 AI 配置

展示：

- API Key 已配置
- 知识库已接入
- 动态训练计划生成可用

### 3.4 关于

展示：

- App version
- Build number
- Bundle ID
- 数据策略

## 4. 交互口径

首版 Profile 以展示为主，不做表单编辑和 OAuth 跳转。

后续可扩展：

- Strava OAuth 登录
- Intervals.icu Keychain 配置页
- AI API Key 检查与重置
- 用户目标、比赛目标、训练偏好编辑

## 5. 验收清单

- [x] Profile 不再是占位页。
- [x] 展示个人信息。
- [x] 展示 Apple Health 数据源状态。
- [x] 展示 Intervals.icu Athlete ID 和连接状态。
- [x] 展示 Strava 预留连接模块。
- [x] 展示 AI 配置模块。
- [x] 展示版本与 Bundle ID。
- [ ] 真机视觉检查。
