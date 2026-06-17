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
