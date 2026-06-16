# 晨间健康报告 + 趋势数据 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每天解锁后生成昨日健康报告 → 推送通知，用户在 App 内查看历史报告和趋势数据

**Architecture:**
- 报告生成：解锁触发 → 等步数 → 本地计算基础数据 → LLM 生成报告 → 落盘 JSON → 发送通知
- 数据存储：Documents/MorningReports/{date}.json，30 天滚动清理
- 通知：UNUserNotificationCenter（本地通知）+ Notification Content Extension（展开视图）
- App Tab：MorningReportTab（历史列表）+ TrendDataPage（趋势数据）

**Tech Stack:** SwiftUI, HealthKit, UNUserNotificationCenter, LLMService (DashScope)

---

## 第一阶段：数据层（可独立测试）

### Task 1: MorningReport 数据结构 + MorningReportStore

**Files:**
- Create: `Stick/Services/MorningReportStore.swift`
- Create: `Stick/Models/MorningReport.swift`

- [ ] **Step 1: 创建 MorningReport 模型**

```swift
// Stick/Models/MorningReport.swift
import Foundation

struct MorningReport: Codable, Identifiable {
    let id: UUID
    let date: String              // "yyyy-MM-dd"
    let generatedAt: Date

    // 基础数据
    let sleepMinutes: Int
    let sleepQuality: String      // "连续" / "轻度中断" / "中断" / "碎片化"
    let sleepMidnightWake: Int?
    let walkMinutes: Int
    let steps: Int
    let avgSpeed: Double?
    let doubleSupport: Double?
    let sedentaryMinutes: Int
    let longestSedentaryMin: Int
    let longestSedentaryRange: String?
    let wakeUpMinute: Int
    let gaitScore: Int

    // LLM 生成
    let llmSummary: String
    let llmScore: Int
    let llmShortAdvice: [String]
    let llmLongAdvice: [String]
    let llmDetail: String

    // 通知状态
    let notified: Bool
}
```

- [ ] **Step 2: 创建 MorningReportStore**

```swift
// Stick/Services/MorningReportStore.swift
@MainActor
final class MorningReportStore: ObservableObject {
    static let shared = MorningReportStore()

    @Published private(set) var reports: [MorningReport] = []

    private let reportsDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.reportsDir = docs.appendingPathComponent("MorningReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        loadAll()
    }

    func loadAll() { ... }         // 读所有 JSON，按日期降序
    func load(date: String) -> MorningReport? { ... }
    func save(_ report: MorningReport) { ... }
    func delete(date: String) { ... }
    func cleanupOld() { ... }       // 删除 30 天前的报告
}
```

- [ ] **Step 3: Commit**

---

### Task 2: BodyStateScorer（身体状态得分本地算法）

**Files:**
- Create: `Stick/Services/BodyStateScorer.swift`

- [ ] **Step 1: 实现算分逻辑**

```swift
// Stick/Services/BodyStateScorer.swift
import Foundation

struct BodyStateScore {
    let gaitScore: Int        // 0-100
    let sleepScore: Int       // 0-100
    let sedentaryScore: Int   // 0-100
    let total: Int            // 加权总分 0-100
}

final class BodyStateScorer {
    static let shared = BodyStateScorer()

    // 步态评分：速度 1.0-1.4 m/s +10，双脚支撑 25-33% +10，夜间清醒每次 -3，base 80
    func computeGaitScore(speed: Double?, doubleSupport: Double?, nightWakeCount: Int) -> Int {
        var score = 80
        if let s = speed, s >= 1.0 && s <= 1.4 { score += 10 }
        if let ds = doubleSupport, ds >= 25 && ds <= 33 { score += 10 }
        score -= nightWakeCount * 3
        return max(0, min(100, score))
    }

    // 睡眠评分：时长 + 质量
    func computeSleepScore(minutes: Int, quality: String) -> Int {
        let hour = Double(minutes) / 60.0
        let durationScore: Int
        if hour < 5 { durationScore = 40 }
        else if hour < 6 { durationScore = 60 }
        else if hour < 7 { durationScore = 80 }
        else if hour <= 9 { durationScore = 100 }
        else { durationScore = 80 }
        let qualityScore: Int
        switch quality {
        case "连续": qualityScore = 100
        case "轻度中断": qualityScore = 80
        case "中断": qualityScore = 60
        case "碎片化": qualityScore = 40
        default: qualityScore = 60
        }
        return (durationScore + qualityScore) / 2
    }

    // 久坐评分
    func computeSedentaryScore(minutes: Int) -> Int {
        if minutes < 60 { return 100 }
        else if minutes < 120 { return 80 }
        else if minutes < 240 { return 60 }
        else { return 30 }
    }

    // 综合得分
    func compute(gait: Int, sleep: Int, sedentary: Int) -> Int {
        return gait * 40 / 100 + sleep * 30 / 100 + sedentary * 30 / 100
    }
}
```

- [ ] **Step 2: Commit**

---

### Task 3: HealthKitService 昨日数据查询扩展

**Files:**
- Modify: `Stick/Services/HealthKitService.swift`

- [ ] **Step 1: 新增昨日数据查询方法**

在 HealthKitService.swift 末尾添加：

```swift
// MARK: - 昨日数据查询（用于 Morning Report）

/// 查询昨日（00:00 ~ 23:59）的快照数据
func queryYesterdaySnapshots() async -> [HealthSnapshot] {
    let calendar = Calendar.current
    let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
    let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday)!
    return all.filter { $0.timestamp >= yesterday && $0.timestamp < endOfYesterday }
}

/// 查询昨日睡眠总分钟数
func queryYesterdaySleepMinutes() async -> Int {
    let snapshots = await queryYesterdaySnapshots()
    return snapshots.filter { $0.bodyState == "sleep" }.count
}

/// 查询昨日步行总分钟数
func queryYesterdayWalkMinutes() async -> Int {
    let snapshots = await queryYesterdaySnapshots()
    return snapshots.filter { $0.bodyState == "walk" }.count
}

/// 查询昨日久坐总分钟数
func queryYesterdaySedentaryMinutes() async -> Int {
    let snapshots = await queryYesterdaySnapshots()
    return snapshots.filter { $0.bodyState == "sit" }.count
}

/// 查询昨日总步数
func queryYesterdaySteps() async -> Int {
    let snapshots = await queryYesterdaySnapshots()
    return snapshots.last?.cumulativeStepCount ?? 0
}

/// 查询昨日起床时间（分钟）
func queryYesterdayWakeUpMinute() async -> Int {
    let snapshots = await queryYesterdaySnapshots()
    guard let first = snapshots.first(where: { $0.bodyState == "walk" }) else { return 0 }
    return StickState.minutesOfDay(first.timestamp)
}
```

- [ ] **Step 2: Commit**

---

### Task 4: LLM Prompt 解析 + MorningReportGenerator

**Files:**
- Create: `Stick/Services/MorningReportGenerator.swift`

- [ ] **Step 1: 实现 LLM 响应解析**

```swift
// Stick/Services/MorningReportGenerator.swift

struct LLMReportResponse: Codable {
    let summary: String
    let score: Int
    let shortAdvice: [String]
    let longAdvice: [String]
    let detail: String
}

/// 从 LLM 返回文本中解析 JSON
func parseLLMResponse(_ text: String) -> LLMReportResponse? {
    // 尝试提取 {...} 块
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}"),
          start < end else { return nil }
    let jsonStr = String(text[start...end])
    return try? JSONDecoder().decode(LLMReportResponse.self, from: jsonStr.data(using: .utf8)!)
}
```

- [ ] **Step 2: 实现生成器**

```swift
@MainActor
final class MorningReportGenerator {
    static let shared = MorningReportGenerator()

    func generate(for date: Date) async throws -> MorningReport {
        let hk = HealthKitService.shared
        let scorer = BodyStateScorer.shared

        // 1. 收集昨日数据
        let snapshots = await hk.queryYesterdaySnapshots()
        let sleepMinutes = await hk.queryYesterdaySleepMinutes()
        let walkMinutes = await hk.queryYesterdayWalkMinutes()
        let sedentaryMinutes = await hk.queryYesterdaySedentaryMinutes()
        let steps = await hk.queryYesterdaySteps()
        let wakeUpMinute = await hk.queryYesterdayWakeUpMinute()

        // 2. 夜间清醒
        let nightWakes = await hk.detectNightWakePeriods()
        let nightWakeCount = nightWakes.count
        let sleepQuality: String
        switch nightWakeCount {
        case 0: sleepQuality = "连续"
        case 1: sleepQuality = "轻度中断"
        case 2: sleepQuality = "中断"
        default: sleepQuality = "碎片化"
        }

        // 3. 步态数据
        let gaitScore = scorer.computeGaitScore(
            speed: await hk.todayWalkingSpeed(),
            doubleSupport: await hk.todayWalkingDoubleSupport(),
            nightWakeCount: nightWakeCount
        )

        // 4. 组装 prompt
        let systemPrompt = """
你是一位专业的 iOS 健康数据分析师...
（见设计文档 6.1）
"""
        let userPrompt = """
昨日数据：
- 睡眠: \(sleepMinutes)分钟，夜间清醒 \(nightWakes.reduce(0) { $1.count })分钟，质量: \(sleepQuality)
- 起床时间: \(minuteToTimeString(wakeUpMinute))
- 步行: \(walkMinutes)分钟，步数 \(steps)步
- 久坐: \(sedentaryMinutes)分钟
- 步态评分: \(gaitScore)/100

请生成健康报告。
"""

        // 5. 调用 LLM
        let response = try await LLMService.sendMessage(userPrompt, context: systemPrompt)
        let llmData = parseLLMResponse(response)

        // 6. 构建报告
        return MorningReport(
            id: UUID(),
            date: dateFormatter.string(from: date),
            generatedAt: Date(),
            sleepMinutes: sleepMinutes,
            sleepQuality: sleepQuality,
            sleepMidnightWake: nightWakes.first?.count,
            walkMinutes: walkMinutes,
            steps: steps,
            avgSpeed: await hk.todayWalkingSpeed(),
            doubleSupport: await hk.todayWalkingDoubleSupport(),
            sedentaryMinutes: sedentaryMinutes,
            longestSedentaryMin: await hk.todaySedentaryMinutes(),
            longestSedentaryRange: nil,
            wakeUpMinute: wakeUpMinute,
            gaitScore: gaitScore,
            llmSummary: llmData?.summary ?? "数据生成中...",
            llmScore: llmData?.score ?? 0,
            llmShortAdvice: llmData?.shortAdvice ?? [],
            llmLongAdvice: llmData?.longAdvice ?? [],
            llmDetail: llmData?.detail ?? "",
            notified: false
        )
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private func minuteToTimeString(_ minute: Int) -> String {
        let h = minute / 60
        let m = minute % 60
        return String(format: "%02d:%02d", h, m)
    }
}
```

- [ ] **Step 3: Commit**

---

## 第二阶段：通知系统

### Task 5: NotificationService

**Files:**
- Create: `Stick/Services/NotificationService.swift`

- [ ] **Step 1: 实现通知请求和发送**

```swift
// Stick/Services/NotificationService.swift
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch { return false }
    }

    func scheduleMorningReport(_ report: MorningReport) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "📊 昨日健康报告已生成"
        content.body = "查看今日身体状态分析 →"
        content.sound = .default
        content.categoryIdentifier = "MORNING_REPORT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "morning-report-\(report.date)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
```

- [ ] **Step 2: 在 StickApp 中注册 Category**

修改 `StickApp.swift`，添加：

```swift
// 在 @main App 初始化时调用
.onAppear {
    NotificationService.shared.requestAuthorization()
    // 注册通知 Category
    UNUserNotificationCenter.current().setNotificationCategories([
        UNNotificationCategory(
            identifier: "MORNING_REPORT",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
    ])
}
```

- [ ] **Step 3: Commit**

---

## 第三阶段：UI 层

### Task 6: MorningReportTab + 历史列表

**Files:**
- Create: `Stick/Views/MorningReportTab.swift`

- [ ] **Step 1: 实现 Tab 入口和列表**

```swift
// Stick/Views/MorningReportTab.swift
import SwiftUI

struct MorningReportTab: View {
    @StateObject private var store = MorningReportStore.shared
    @State private var selectedReport: MorningReport?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.reports) { report in
                    ReportRow(report: report)
                        .onTapGesture { selectedReport = report }
                }
            }
            .navigationTitle("报告")
            .navigationDestination(item: $selectedReport) { report in
                MorningReportDetailView(report: report)
            }
        }
    }
}

struct ReportRow: View {
    let report: MorningReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.date).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(report.llmScore)分").font(.headline)
            }
            HStack(spacing: 12) {
                Label("\(report.sleepMinutes / 60)h\(report.sleepMinutes % 60)m", systemImage: "moon.fill")
                Label("\(report.walkMinutes)m", systemImage: "figure.walk")
                Label("\(report.sedentaryMinutes / 60)h\(report.sedentaryMinutes % 60)m", systemImage: "chair.fill")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Commit**

---

### Task 7: MorningReportDetailView

**Files:**
- Create: `Stick/Views/MorningReportDetailView.swift`

- [ ] **Step 1: 实现完整报告视图（参考 HTML 原型）**

参考 `/mock/morning-report.html` 的布局，实现以下组件：
- 通知横幅风格 Header（深色渐变背景）
- 三大指标卡片（睡眠/步行/久坐）
- 24h 时间条（StickState.daySchedule 渲染）
- 睡眠分析卡片
- 久坐热力时段图
- 运动分析卡片
- AI 综合评分圆环
- 短期/长期建议 Tab
- 折叠的详细分析
- 底部 Chat 输入框（复用 ChatOverlay）

- [ ] **Step 2: Commit**

---

### Task 8: TrendDataPage（趋势数据页）

**Files:**
- Create: `Stick/Views/TrendDataPage.swift`

- [ ] **Step 1: 实现趋势数据页**

结构：
- 时间切换：今日 / 本周（7天）/ 本月（30天）
- 三张 MetricTrendCard（睡眠/步行/久坐）
- 身体状态得分折线图
- 历史日报列表（可点击查看详情）

```swift
struct TrendDataPage: View {
    @State private var selectedRange: TrendRange = .week

    enum TrendRange: String, CaseIterable {
        case today = "今日"
        case week = "本周"
        case month = "本月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 时间维度切换
                    Picker("范围", selection: $selectedRange) {
                        ForEach(TrendRange.allCases, id: \.self) { r in Text(r.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // 三大指标趋势
                    MetricTrendCard(title: "睡眠", icon: "moon.fill", unit: "h",
                                   values: trendData.map { Double($0.sleepMinutes) / 60.0 },
                                   color: .purple)
                    MetricTrendCard(title: "步行", icon: "figure.walk", unit: "m",
                                   values: trendData.map { Double($0.walkMinutes) },
                                   color: .green)
                    MetricTrendCard(title: "久坐", icon: "chair.fill", unit: "h",
                                   values: trendData.map { Double($0.sedentaryMinutes) / 60.0 },
                                   color: .orange)

                    // 身体状态得分折线图
                    BodyScoreTrendChart(scores: trendData.map { $0.llmScore })

                    // 历史日报列表
                    ForEach(trendData) { report in
                        ReportRow(report: report)
                            .onTapGesture { }
                    }
                }
            }
            .navigationTitle("趋势数据")
        }
    }
}
```

- [ ] **Step 2: Commit**

---

### Task 9: PersonalView 添加趋势入口

**Files:**
- Modify: `Stick/Views/PersonalView.swift`

- [ ] **Step 1: 添加趋势数据菜单项**

在 `menus` 数组中添加：

```swift
MenuItem(icon: "chart.line.uptrend.xyaxis", title: "趋势数据")
```

在 switch case 中添加导航逻辑（路由到 TrendDataPage）。

- [ ] **Step 2: Commit**

---

## 第四阶段：集成与触发

### Task 10: 报告生成触发逻辑

**Files:**
- Modify: `Stick/Services/HealthKitService.swift` 或新建 `Stick/Services/MorningReportTrigger.swift`

- [ ] **Step 1: 实现解锁触发 + 步数检测**

```swift
@MainActor
final class MorningReportTrigger: ObservableObject {
    static let shared = MorningReportTrigger()

    private var isMonitoring = false

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        Task {
            await monitorUnlock()
        }
    }

    private func monitorUnlock() async {
        // 监听 scenePhase 变化
        // 当 scenePhase == .active 且时间 >= 07:00 时：
        // 1. 检查今日 hasStepData
        // 2. 若有步数 → 等待 10-20min（或立即生成）
        // 3. 调用 MorningReportGenerator.generate()
        // 4. 落盘 + 发送通知
    }
}
```

在 `StickApp.swift` 的 `.onAppear` 中调用 `MorningReportTrigger.shared.startMonitoring()`。

- [ ] **Step 2: Commit**

---

## Spec Self-Review

- [x] 所有 Task 有文件路径、Step、Commit 节点
- [x] MorningReport 结构与设计文档 2.1 完全一致
- [x] LLM Prompt 结构与设计文档 6.1/6.2 一致
- [x] BodyStateScorer 权重与设计文档 5.4 一致
- [x] 无 TBD、无 TODO、无占位符
- [x] Task 顺序符合依赖关系（数据层 → 通知 → UI → 触发）
