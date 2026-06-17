# progress.md — Stick 当前进度

---

## 做到哪了

### 核心功能（已完成）

- **首页火柴人 + 时间线**：4 状态（走/坐/站/睡）ATLAS 风格火柴人 Canvas 绘制，24h 可拖动时间线（5 分钟 snap）
- **24h 时刻表自动查表**：状态来源非手选，由 `StickState.daySchedule` 驱动
- **HealthKit 数据层**：`HealthKitService` 查询步数/心率/HRV/睡眠/久坐/活动能量；`HealthStore` 聚合快照持久化
- **FeatureRow 数据卡**：3 张卡（walk/sit/sleep 各自显示相关指标），状态色 left border
- **Widget 扩展**：2×2 久坐血小板风险 widget，点击通过 AppIntent 触发不弹系统确认框
- **AI 对话 ChatOverlay**：相机 chip 拍照，直达 ChatOverlay
- **晨间健康报告 MorningReportTab**：MorningReportGenerator + 趋势数据 + 饮食分析
- **数据导出**：HealthKit 原始样本导出（7 天 / 最近 / 今天），输出 dict 不是数组
- **详情页导航**：点功能卡（walk/sit/sleep）或火柴人 → sheet 详情页，`SheetDestination` 路由驱动
- **Widget Live Activity**：久坐秒表 Live Activity 激活链路完成，`LiveActivityManager` 单例管理生命周期

### 迭代中（部分完成）

- **久坐秒表**：首页 sit 卡片显示实时秒表（M:SS），支持 scenePhase 后台回前台继续计时
- **睡眠分析**：夜间清醒检测 + 深睡/浅睡分段 + 睡眠质量评分
- **步态质量**：速度/双支撑时间/步态评分的趋势卡片

### 待完成（规划中）

- 1024×1024 AppIcon（现为占位）
- 横屏适配
- 替换 `Date()` 为真实时间 + 后端 sensor
- thumb 拖动时火柴人关节参数化（smooth pose 插值）

---

## 下一步

当前主要阻塞点均已修复。建议验证：
1. **模拟器**：启动 app 后 Console 应看到 `🧪 DEBUG 模拟器自动注入 7 天 mock 数据` 字样；"导出最近 7 天"应有数据
2. **真机（iOS 16.1+）**：久坐时 Live Activity 应自动激活；详情页 tap 跳转正常
3. **时间线**：拖动 thumb 检查轴坐标是否稳定、步行段是否清晰可见

---

## 阻塞点

- **真机 HealthKit 数据量**：DEBUG 模拟器启动时自动注入 7 天 mock 数据（`injectMockDataIntoHealthKit`）；真机仍依赖真实 HealthKit 数据
- **Widget Live Activity**：iOS 16.1+ 真机验证（模拟器不展示 Live Activity UI）；代码链路已完整

---

## bugs（最新）

> 完整记录见 `bug.md`

| 日期 | 摘要 | 状态 |
|---|---|---|
| 2026-06-18 | `MorningReportTrigger` 删除未使用 `import Combine`（死代码） | 已修复，合入 `8070d85` |
| 2026-06-18 | `ChatOverlay` 3 处 `try! NSRegularExpression` → `try?` + 优雅降级 | 已修复，合入 `c79eb90` |
| 2026-06-18 | `LLMService.sendMessageStreamWithSearch` 删除未使用 `fullText`/`collectedData` 死代码 | 已修复，合入 `ce40f52` |
| 2026-06-18 | `SleepParser` `looksLikeSleepMessage` 数组删除重复关键词 "眠" | 已修复，合入 `7d18983` |
| 2026-06-18 | `HealthKitService.captureSnapshot()` 竞态条件：async 函数后台线程赋值 `@Published` 属性 | 已修复，合入 `ad321d4` |
| 2026-06-18 | `ChatHistoryStore` 删除未使用 `import SwiftUI`（纯数据层 service） | 已修复，合入 `f11f75c` |
| 2026-06-18 | `RealHealthAnalyzer` `completeness / checkCount` 除零崩溃风险，新装 app 无历史数据时可能触发 | 已修复，合入 `b910989` |
| 2026-06-18 | `DayPlaybackSheet` `simulatedMinute` 在 `progress=1.0` 时计算出 1440，导致最后睡眠段永远无法匹配，fallback 到 `.walk` | 已修复，合入 `4e2ae58` |
| 2026-06-18 | `LocationService` 删除未使用变量 `lastGeocodeCity`（死代码） | 已修复，合入 `5595842` |
| 2026-06-18 | `DayTimelineView` `scrubOffset` 上限 `1440` 改为 `1439`，消除拖到最顶时与 00:00(now) 位置重叠 | 已修复，合入 `1e0a0fe` |
| 2026-06-18 | `MockHealthDataLoader` `buckets[key]!` force unwrap → `?? Bucket()`；`HealthExport/HealthTypeBlock/HealthDataPoint.encode(to:)` `fatalError()` 占位 → 正确 Codable 实现 | 已修复，合入 `0ed0429` |
| 2026-06-18 | `HealthKitService.analyzeYesterdayHeartRateZones` 2 处 `calendar.date(byAdding:)!` → `guard let` | 已修复，合入 `ff9b9a3` |
| 2026-06-18 | `HealthKitService`/`HealthTrendAnalyzer`/`MorningReportStore` 9 处 `calendar.date(byAdding:...)!` → `guard let` | 已修复，合入 `646e147` |
| 2026-06-18 | `ContentView` 冗余单例属性：`@ObservedObject hkService` 与 `@StateObject hk` 同时存在，浪费资源且语义混乱 | 已修复，合入 `112833f` |
| 2026-06-18 | `HealthKitService.guessWakeUpTime()` 3 处 `calendar.date()!` force unwrap → `guard let` 安全解包 | 已修复，合入 `e989091` |
| 2026-06-18 | `HealthKitService.exportTodayData()` 缺少 `return`，导致"导出今日数据"永远返回 `nil` | 已修复，合入 `db34cd9` |
| 2026-06-18 | `StateInference.swift` 19 处 `score[.X]!` force unwrap → `score[.X, default: 0]` 更安全 | 已修复，合入 `ba6e5af` |
| 2026-06-18 | `MorningReportGenerator.parseLLMResponse` `jsonStr.data(using: .utf8)!` 强制解包，若 LLM 返回无效 UTF-8 会崩溃 | 已修复，合入 `2ec115a` |
| 2026-06-18 | `HealthAnalyzer.lastNightSleeps` 窗口上限误用明天 noon，午睡被归入昨夜睡眠，影响睡眠时长 < 6h 判断 | 已修复，合入 `7aa0467` |
| 2026-06-18 | `SleepParser.swift:92` `bedTime!` 强制解包 → 改用已解包的 `bed` 变量 | 已修复，合入 `fcd4e2a` |
| 2026-06-18 | `ObserverBox` 遵循 `Sendable` 但含可变存储（`_handler`），Swift 6 报错 | 已修复，合入 `77e9437` |
| 2026-06-18 | `SharedStateStore.ObserverBox`/`chatObserverBox`/`isChatObserverRegistered` 缺 `NSLock`/`nonisolated(unsafe)`，Darwin 回调与主线程存在数据竞争 | 已修复，合入 `b1905c4` |
| 2026-06-18 | ContentView 久坐 timer `prevMinutes` 在 Task 创建前捕获，异步期间 `onChange` 可修改 `currentSitMinutes` 导致比较用到 stale 数据 | 已修复，合入 `de16078` |
| 2026-06-18 | `HealthKitService.todaySedentaryMinutes` 闭包中未使用的 `error` 参数 | 已修复，合入 `d7d8f28` |
| 2026-06-17 | `HealthKitService.captureSnapshot` 正念分钟错误使用 `.appleExerciseTime` 类型 | 已修复，合入 `ee3149c` |
| 2026-06-17 | `HealthKitService.todaySleepHours()` 把 Awake/InBed 也算成睡眠，导致睡眠时长高估 | 已修复，合入 `624f865` |
| 2026-06-17 | ChatOverlay `onChange` iOS 17 弃用警告 + Swift 6 并发捕获警告 | 已修复，合入 `117c1ff` |
| 2026-06-17 | ContentView `displayState` 查找最新快照 O(n log n) → O(n) 优化 | 已修复，合入 `e9049ee` |
| 2026-06-17 | DayTimelineView `onChange` iOS 17 弃用警告 + `@ViewBuilder` 警告 + `seg.stepCount!` 强制解包等多项清理 | 已修复，合入 `4d2aa15` |
| 2026-06-17 | ContentView `stageScrubBadge` swipe 后显示旧 state 而非 targetState | 已修复，合入 `77fc8d1` |
| 2026-06-17 | `StateInference.score.max(by:)!` 强制解包风险，改为 guard let 安全解包 | 已修复，合入 `e5aea04` |
| 2026-06-17 | ContentView `stageScrubBadge` 在 `seg=nil` 时显示时间徽章而非状态徽章 | 已修复，合入 `c31fb47` |
| 2026-06-17 | `ContentView.lastSitAnalysisTime` 初始化 `.distantPast` 导致首次 timer 立即触发 30 秒分析 | 已修复，合入 `2917c3a` |
| 2026-06-17 | StickFigureView `drawSleep` / `drawWalk` 脚部坐标超出 240x320 坐标系（sleep foot x=256 超 16px，walk 左脚 y=322 超 2px） | 已修复，合入 main |
| 2026-06-17 | `HealthKitService.computeDaySchedule` 凌晨 00:00-07:00 被误判为 `.sit` 而非 `.sleep` | 已修复，合入 `1f5b0d2` |
| 2026-06-17 | ContentView `StageHeroView` 中 `stateBadge` 未使用（27行死代码） | 已修复，合入 `2ec3961` |
| 2026-06-17 | ContentView `StageHeroView` 中 `noDataStage`/`noDataBadge` 未使用（75行死代码） | 已修复，合入 `b1c3143` |
| 2026-06-17 | ContentView `minutesToDate` 函数未使用（死代码） | 已修复，合入 `ce6e02d` |
| 2026-06-17 | StickFigureView `drawScene` ground 坐标不统一（322/318/320 混用） | 已修复，合入 `b6379ec` |
| 2026-06-17 | ContentView `primaryHeartRate/Duration` 整数解析用 `split(" ").first` 不健壮 | 已修复，合入 `2384c2b` |
| 2026-06-17 | FeatureRow `autoCollapseTimer` 在折叠态误触发，导致 UI 抖动 | 已修复，合入 `8988d76` |
| 2026-06-17 | FeatureRow alerts 展开/收起缺显式动画，列表切换跳变 | 已修复，合入 `b3d7594` |
| 2026-06-17 | `StickRiskAlertWidgetView.swift` 重复 `// MARK: - Preview` 注释 | 已修复，合入 `0f24fea` |
| 2026-06-17 | App Group ID 文档错误（CLAUDE.md 写 `group.com.example.stick`，代码用 `group.com.stick.app.h`） | 已修复，合入 `f7ab5b8` |
| 2026-06-17 | Widget 背景色硬编码暖白色 | 已修复，合入 `2b40acf` |
| 2026-06-17 | FeatureRow 展开 alerts 时需点两次 chevron 才能显示列表 | 已修复，合入 `f170861` |
| 2026-06-17 | DayTimelineView 残留死代码（`shareMessage`/`backToNowButton` 未使用） | 已修复，合入 `9090be7` |
| 2026-06-17 | DEBUG 模拟器启动时未自动注入 7 天 mock 数据，导致"导出最近 7 天"无数据 | 已修复，合入 `6441b3f` |
| 2026-06-17 | FeatureRow SEDENTARY 行时间数字对不齐（3 根因：tick 未赋值/sleep 校正不一致/异步 Task 跳变） | 已修复，合入 `561831c` |
| 2026-06-17 | DayTimelineView body 内写 @State 触发 SwiftUI 警告 | 已修复，合入 `719fbda` |
| 2026-06-17 | `detectNightWakePeriods` 跨午夜 Range 崩溃 | 已修复，合入 `d6442b1` |
| 2026-06-17 | `observePendingChatSeed` use-after-free 闪退 | 已修复，合入 `2030e21` |
| 2026-06-17 | `exportTodayData()` 误用 HealthStore 输出数组 | 已修复，合入 `74e06fd` |
