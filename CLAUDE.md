# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目

火柴人（Stick）—— iOS app，4 个姿态状态：**走 / 坐 / 站 / 睡**。深色主题，UI 布局参考 WorkBuddy（顶栏 + 主舞台 + 时间线 + 3 功能卡 + 底部输入栏），火柴人视觉风格参考 ATLAS 项目的 v2/v3/v6（侧视、线框、关节圆点、胸前虚线、道具提示）。

**状态来源不是手选，而是 24h 时刻表自动查表。** 用户可以在时间线上拖动 thumb 来预览任意时刻的状态。

工程有两部分：
- `ios/` —— SwiftUI iOS app（**主项目**，可在 Xcode 直接打开运行）
- `mock/index.html` —— 早期 HTML 静态原型（15 状态版本，已不再维护，仅作历史参考）

`img_v3_0212i_4b596c22-1bae-4bd2-a06c-6fef3662219g.jpg` 是上游 WorkBuddy 风格参考图。

## 运行 iOS app

```bash
# 推荐：直接打开 Xcode
open ios/Stick.xcodeproj

# 或命令行
cd ios
xcodebuild -project Stick.xcodeproj -scheme Stick \
  -destination 'generic/platform=iOS Simulator' build

# 装到模拟器
SIM=$(xcrun simctl list devices available | grep "iPhone 17 " | head -1 | awk -F'[()]' '{print $2}')
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Stick.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" com.stick.app.van
```

要求 Xcode 15+（实测 Xcode 26.5，iOS 17+ deployment target）。注意 bundle ID 是 `com.stick.app.van`，不是 `com.stick.app`。

## iOS 架构

```
ios/Stick/
├── StickApp.swift                   @main 入口，强制 dark scheme
├── ContentView.swift                主舞台 + 布局；@State 持有 now / scrubMinute
├── Models/
│   └── StickState.swift             enum: walk / sit / stand + 24h daySchedule + current(at:)
├── Views/                           SwiftUI 视图（见上文）
└── Services/                        @MainActor ObservableObject 业务服务（HealthKit / LLM / AI 分析等）
```

**关键设计选择：**

- **`StickState`** 是状态中枢。文案 / 数据 / accent 颜色全部从 enum 派生；新增状态只需加 case + 派生 + `daySchedule` 一行。
- **`StickState.daySchedule`** 是 24h 时刻表。8 个时段覆盖全天（00:00-07:00 睡 / 07-08:30 走 / 08:30-12 坐 / 12-13:30 走 / 13:30-18 坐 / 18-19 走 / 19-22 站 / 22-24 睡）。`current(at:)` 给定时间查 state，`currentSegment(at:)` 给定时间查 segment（UI 用来显示当前时段范围）。
- **`ContentView`** 持有 `now: Date` 和 `scrubMinute: Int?`。`displayMinute = scrubMinute ?? minutesOfDay(now)`，`displayState = currentSegment(...).state`。所有子视图（StickFigure / Timeline / FeatureRow）都消费 `displayState`。
- **`TimelineView`** 是核心交互：
  - 24h 横条：4 状态色段（绿/橙/蓝/紫）+ 1.5pt 间隙 + 圆角
  - 白色 thumb，整条 `DragGesture(minimumDistance: 0)` 监听，5 分钟 snap
  - `scrubMinute != 当前分钟` 时显示 "SCRUBBING" 提示 + 时段信息 + "回到现在" 按钮
- **状态色** — 走=绿 / 坐=橙 / 站=蓝 / 睡=紫；线条=off-white (`#E6EBF2`)。状态色渗透到关节点、状态徽章、thumb 边框、feature 卡、accent 字、背景柔光。
- **动效**：
  - thumb 拖动：`interactiveSpring(response: 0.18, dampingFraction: 0.85)` 跟手
  - 状态切换：`.animation(.easeInOut(0.45), value: state)` 让 stick figure / 背景柔光平滑过渡
  - 时间数字：`.contentTransition(.numericText())` 翻牌效果
  - "回到现在" 按钮：`withAnimation(.spring(response: 0.4, dampingFraction: 0.72))` 回弹

## 改动时的注意事项

- **坐标系**：火柴人坐标全部在 240×320 空间内。**不要**改 viewBox，改坐标即可。
- **添加新状态**：(1) `StickState` 加 case + 派生属性 (2) `daySchedule` 加 segment (3) `StickFigureView` 加 `drawXxx` 函数 (4) `drawScene` switch 加 case 画场景 (5) `drawFigure` 路由加 case
- **时刻表修改**：在 `StickState.daySchedule` 直接改分钟数即可。所有 1440 分钟必须覆盖到，否则 `current()` 会 fall back 到 `.stand`。
- **bg / accent 颜色**：直接用 `state.accent` 派生，**不要**在调用方硬编码
- **pbxproj**：手写版，新增/重命名 .swift 需同步改 `PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase` 四处（**没有** xcodegen/tuist 依赖）。Widget target 的文件 ID 固定 24 字符（如 `B40000000000000000000012`）。
- **Preview Assets 路径含空格**会有 asset reader warning，不影响 build

## Widget 扩展（StickWidget）

```
ios/StickWidget/
├── StickWidget.swift              Widget bundle 入口
├── StickRiskAlertWidgetView.swift 2×2 久坐血小板风险 widget
└── WidgetPreviewView.swift        app 内预览 widget 效果
```

- **App ↔ Widget 通信**：通过 App Group (`group.com.zdeer.testaiear`) 的 UserDefaults 共享状态。Widget 写入，App 启动时读取。
- **Widget 点击**：使用 `Button(intent: OpenRiskAlertIntent(...))` 触发 AppIntent，不弹 "在 Stick 中打开?" 系统确认框。
- **OpenRiskAlertIntent**：定义在 `StickRiskAlertWidgetView.swift`（或 SharedKit），同时被 widget target 和主 app target 编译。`perform()` 在 widget 进程运行，调用 `SharedStateStore.writePendingRiskAlert()`。
- **Timeline 更新**：每 5 分钟刷新一次。

## SharedKit（跨 target 共享代码）

```
ios/SharedKit/
├── SharedState.swift    Theme 色板 + SharedStickState + SharedStateStore
└── OpenChatIntent.swift AppIntent（主 app 用，widget 侧另有同名 struct）
```

- `SharedStateStore`：App Group UserDefaults 读写，key 为 `pendingRiskAlert`。
- SharedKit 被主 app 和 widget 两个 target 编译，Intent 文件在两边的 import 路径相同。

## 健康相关服务

```
ios/Stick/Services/
├── HealthKitService.swift   HealthKit 数据拉取（心率/步数/睡眠等）
├── HealthAnalyzer.swift     历史健康数据异常分析
├── AIRiskAnalyzer.swift     AI 实时风险分析
├── AISleepAnalyzer.swift    AI 睡眠分析
└── StateInference.swift     多信号融合推断体态（走/坐/站/睡）
```

- `HealthKitService` 每 30 秒轮询一次，合并进 UI 状态。
- `AlertAggregator` 聚合 AI 实时风险和历史分析，驱动 `AlertsPanel`。

## App 入口与 Sheet

`StickApp.swift` 是 `@main` 入口，`scenePhase == .active` 时从 App Group 读取 widget 写入的 pending alert，有值则弹出 `WidgetRiskAlertSheet`。

## 后续方向

- 替换 `Date()` 为真实时间 + 后端 sensor
- thumb 拖动时让 stick figure 关节参数化（smooth pose 插值而非瞬时切换）
- 详情页：点底部功能卡 / 火柴人 → push sheet
- 1024×1024 AppIcon（现为占位）
- 横屏适配
