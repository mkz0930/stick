# context.md — Stick 项目读图

---

## 产品定位

iOS app「火柴人」：4 姿态状态（走 / 坐 / 站 / 睡）驱动的健康仪表盘。深色主题，ATLAS 火柴人视觉风格，核心交互是 24h 时间线拖动预览任意时刻状态。数据来源是 HealthKit（非手选）。

**bundle ID**：`com.stick.app.van`

---

## 技术栈

| 层 | 技术 |
|---|---|
| UI 框架 | SwiftUI（iOS 15+） |
| 数据持久化 | HealthKit（原始样本）+ HealthStore JSON（聚合快照） |
| Widget | WidgetKit + AppIntent（点击不弹系统确认框） |
| App ↔ Widget | App Group UserDefaults（`group.com.stick.app.h`） |
| 布局 | 纯 SwiftUI，无 SnapKit / UIKit 混用 |
| 构建 | Xcode pbxproj（手写，无 xcodegen/tuist） |

---

## 架构分层

```
ios/
├── Stick/                        主 app target
│   ├── Models/
│   │   └── StickState.swift      状态中枢：enum + 24h daySchedule + current(at:)
│   │                              文案/颜色/accent 全部从 enum 派生
│   ├── Views/
│   │   ├── ContentView.swift     首页（主舞台 + 布局），@State 持有 now/scrubMinute
│   │   ├── StickFigureView.swift Canvas 画火柴人（240×320 坐标系，等比缩放）
│   │   ├── TimelineView.swift    24h 可拖动时间线 + 5 分钟 snap
│   │   ├── DayTimelineView.swift Timeline 的内部实现（条状时间轴）
│   │   ├── FeatureRow.swift      底部 3 张数据卡（状态色 left border）
│   │   ├── TopBarView.swift      顶栏（汉堡 + 标题 + LIVE 标）
│   │   ├── InputBar.swift        底部输入栏 + 相机 chip
│   │   ├── ChatOverlay.swift     AI 对话 overlay
│   │   ├── MorningReportTab.swift 晨间健康报告 tab
│   │   └── ...                   其他页面/组件
│   ├── Services/
│   │   ├── HealthKitService.swift  HealthKit 原始数据查询（步数/心率/睡眠/久坐/活动能量）
│   │   ├── HealthStore.swift      聚合快照持久化（Documents/health-snapshots.json）
│   │   ├── StateInference.swift   姿态推理（心率+步数联合判断久坐）
│   │   ├── HealthAnalyzer.swift   综合健康分析
│   │   ├── SleepAnalyzer.swift    睡眠分析（夜间清醒/深睡/睡眠质量）
│   │   ├── MorningReportGenerator.swift 晨间报告生成
│   │   ├── MorningReportStore.swift 晨间报告持久化
│   │   ├── LLMService.swift       LLM 对话服务
│   │   ├── ChatHistoryStore.swift  对话历史持久化
│   │   └── ...                    其他业务服务
│   └── StickApp.swift            @main 入口，强制 dark scheme
│
├── SharedKit/                    被主 app + StickWidget 两个 target 共享编译
│   ├── SharedState.swift         Theme 色板 + SharedStickState + SharedStateStore
│   └── OpenChatIntent.swift      AppIntent（widget 点击触发）
│
└── StickWidget/                 Widget extension target
    ├── StickWidget.swift         Widget bundle 入口
    ├── StickRiskAlertWidgetView.swift  2×2 久坐血小板风险 widget
    └── SedentaryTimerLiveActivity.swift  Live Activity 久坐计时
```

---

## 核心数据流

```
HealthKit (原始样本)
    ↓ 每分钟轮询
HealthKitService (查询/聚合)
    ↓ 写入
HealthStore (Documents/health-snapshots.json) ← 快照持久化
    ↓ 读取
ContentView / DailyStepsStore / FeatureRow (业务消费)
    ↓ 写入
SharedStateStore (App Group UserDefaults) ← Widget 共享
```

**铁律**：`exportTodayData()` / `exportRecentData()` / `exportLast7Days()` 必须查 **HealthKit 原始样本**，输出 `{导出时间, 数据类型:[...]}` dict；**不能** `encode(HealthStore.shared.today)` 输出 `[...]` 数组。

---

## 关键模块

### StickState — 状态中枢

- 4 状态 enum（walk/sit/stand/sleep）
- `daySchedule`：8 段 24h 时刻表，所有 1440 分钟全覆盖
- `current(at:)` / `currentSegment(at:)` 查表
- 文案、accent 色全部从 enum 派生，新增状态只需加 case

### ContentView — 首页驱动

- `@State now: Date` + `@State scrubMinute: Int?`
- `displayMinute = scrubMinute ?? minutesOfDay(now)`
- `displayState = currentSegment(...).state`
- 1s timer 更新 `now`，30s timer 自动校时
- 状态切换动效：`.animation(.easeInOut(0.45), value: state)`

### TimelineView — 核心交互

- 24h 横条：4 状态色段（绿/橙/蓝/紫）+ 1.5pt 间隙 + 圆角
- 白色 thumb 整条 `DragGesture(minimumDistance: 0)`
- 5 分钟 snap，拖动时 stick figure 实时联动
- scrubbing 时显示时段信息 + "回到现在" 按钮

### Widget 扩展

- `OpenRiskAlertIntent`：点击 widget 触发 AppIntent，不弹系统确认框
- `SedentaryTimerLiveActivity`：锁屏久坐计时
- Timeline 每 5 分钟刷新

---

## 主要依赖（无 CocoaPods/SPM）

纯 Apple 系统框架：HealthKit / WidgetKit / SwiftUI / Combine / CoreLocation
