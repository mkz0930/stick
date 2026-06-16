# 晨间健康报告 + 趋势数据设计方案

**日期**: 2026-06-16
**状态**: 草稿，待确认

---

## 一、整体架构

```
每天解锁 → 步数进来 → LLM 生成报告 → 推送通知 → 用户查看
                        │
                        └── 报告数据落盘（JSON）
                                │
                                ├── MorningReportTab（历史日报列表）
                                └── TrendDataPage（趋势数据页）

侧滑抽屉
├── 连接智能设备
├── 数据记录  ──────────────► DataRecordView（已有）
├── 趋势数据  ──────────────► TrendDataPage（新页面）
└── Chat 历史
```

**夜间/凌晨（04:00 前）解锁**：跳过本次通知，用户可手动在 App 内查看。

**无步数日**：跳过通知，报告内容无意义。

---

## 二、数据存储

### 2.1 报告数据结构（JSON，Documents/MorningReports/）

```swift
struct MorningReport: Codable, Identifiable {
    let id: UUID
    let date: String              // "yyyy-MM-dd"，对应昨天的日期
    let generatedAt: Date        // 生成时间

    // 基础数据（本地计算）
    let sleepMinutes: Int        // 睡眠总时长（分钟）
    let sleepQuality: String     // "连续" / "轻度中断" / "中断" / "碎片化"
    let sleepMidnightWake: Int?  // 夜间清醒分钟数

    let walkMinutes: Int         // 步行总时长（分钟）
    let steps: Int               // 总步数
    let avgSpeed: Double?        // 平均步速 m/s
    let doubleSupport: Double?   // 双脚支撑百分比

    let sedentaryMinutes: Int    // 久坐总时长（分钟）
    let longestSedentaryMin: Int // 最长连续久坐（分钟）
    let longestSedentaryRange: String? // "14:27 — 15:57"

    let wakeUpMinute: Int        // 起床时间（分钟，0-1439）
    let gaitScore: Int           // 步态评分 0-100

    // LLM 生成内容
    let llmSummary: String       // AI 综合评估段落
    let llmScore: Int           // 综合健康得分 0-100
    let llmShortAdvice: [String] // 短期建议（3-4 条）
    let llmLongAdvice: [String]  // 长期建议（3-4 条）
    let llmDetail: String        // 详细分析（LLM 自由文本）

    // 通知状态
    let notified: Bool           // 是否已发送通知
}
```

### 2.2 存储位置

- 路径: `Documents/MorningReports/{yyyy-MM-dd}.json`
- 保留: **30 天**，超期自动删除
- 读取: `MorningReportStore.shared.load(date:)` / `loadAll()`

### 2.3 报告生成时机

1. **解锁触发** — 用户解锁设备
2. **等待新步数** — 等 HealthKit 收到第一条新步数（首次 > 50 步判定为起床）
3. **收集昨日数据** — 读取 HealthStore 昨日全部快照（00:00 ~ 23:59）
4. **LLM 分析** — 拼装 Prompt，调用 `LLMService`，获取结构化报告
5. **落盘 + 发送通知**
6. **发送通知** — `UNUserNotificationCenter` 推送本地通知

---

## 三、通知系统

### 3.1 锁屏通知（UNUserNotificationCenter）

```
┌──────────────────────────────┐
│ 🔥 Stick              今天 07:32 │
│                               │
│ 📊 昨日健康报告已生成          │
│ 查看今日身体状态分析 →          │
└──────────────────────────────┘
```

- **Category**: `MORNING_REPORT`
- **Action**: "查看报告" → 打开 App，路由到 MorningReportTab

### 3.2 通知展开视图（Notification Content Extension）

点开通知直接展开显示报告摘要，无需进 App：

```
┌──────────────────────────────┐
│ 🔥 Stick                     │
│ 📊 昨日健康报告    07:32     │
├──────────────────────────────┤
│ 🌙 睡眠   🚶 步行   💺 久坐   │
│ 6h42m   42m     5.3h         │
│ ████████████████████████████ │
│ （24h 时间条缩略图）            │
│                              │
│ 综合得分: 72 / 100            │
│ 步态良好，但久坐超标严重        │
│                              │
│              [查看完整报告 →]  │
└──────────────────────────────┘
```

- **Notification Content Extension** target: `StickNotificationContent`
- Info.plist 配置 `UNNotificationExtensionCategory = MORNING_REPORT`
- 布局用 SwiftUI `NotificationView`（独立于主 App UI）

### 3.3 发送条件

- 解锁时间 **≥ 07:00**
- 当日 **有步数数据**（`hasStepData` 为 true）
- 报告已生成（不等用户等通知）

---

## 四、MorningReportTab（晨间报告 Tab）

### 4.1 入口

App 内新增 Tab: `MorningReportTab`
底部 TabBar 图标: `chart.bar.doc.horizontal`（SF Symbol）
标题: "报告"

### 4.2 Tab 内容：历史日报列表

```
┌─────────────────────────────────┐
│ 报告                               │
├─────────────────────────────────┤
│                                 │
│ 昨天  06/15                      │
│ 🌙 6h42m  🚶 42m  💺 5.3h       │
│ ████████████████████  72分       │
│                                │
├─────────────────────────────────┤
│ 前天  06/14                      │
│ 🌙 7h12m  🚶 28m  💺 6.1h       │
│ ████████████████████  68分       │
│                                │
├─────────────────────────────────┤
│ …                               │
└─────────────────────────────────┘
```

- 每行: 日期 + 三大指标 + 时间条缩略 + 得分
- 滚动加载，7 天视图（默认）/ 30 天切换
- 点击行 → push 完整报告视图 `MorningReportDetailView`

### 4.3 完整报告视图 MorningReportDetailView

展示内容与 HTML 原型完全一致（见 `/mock/morning-report.html`）：

- 通知横幅风格（锁屏样式）
- 日期 + 问候语
- 三大指标卡片
- 24h 时间条
- 睡眠分析 / 久坐热力图 / 运动分析
- AI 综合评估（得分圆环）
- 短期/长期建议 Tab
- 折叠的 LLM 详细分析
- 底部 Chat 输入框

---

## 五、趋势数据页（TrendDataPage）

### 5.1 入口

侧滑抽屉 → "趋势数据" 菜单项 → 路由到 `TrendDataPage`（独立 NavigationStack）

### 5.2 时间维度切换

```
[今日] [本周] [本月]
```

- **今日**: 当天数据，实时更新（最新快照驱动）
- **本周**: 最近 7 天，每日一条数据
- **本月**: 最近 30 天，按日聚合

### 5.3 三大指标趋势卡片

每张卡片结构（以睡眠为例）：

```
┌─ 睡眠趋势 ─────────────────────────────────┐
│  🌙 睡眠时长                                 │
│  ▂ ▃ ▅ ▇ ▅ ▃ ▂   周均值 6h42m   ↑ +8%     │
│  （7天柱状图，堆叠颜色深浅代表睡眠质量）        │
│  6/10  6/11  6/12  6/13  6/14  6/15  6/16  │
└─────────────────────────────────────────────┘
```

- **睡眠**: 柱状图高度 = 睡眠时长，颜色深浅 = 睡眠质量（连续=深紫，轻度=中紫，碎片化=浅紫）
- **步行**: 柱状图高度 = 步行分钟数，绿色
- **久坐**: 柱状图高度 = 久坐时长，颜色 = 危险程度（<2h=绿，2-4h=黄，>4h=红）

趋势箭头: `↑ 比上周 +8%`，`↓ 比上周 -3%`，`→ 持平`

### 5.4 身体状态得分趋势

```
┌─ 身体状态得分趋势 ─────────────────────────┐
│  ┌──────────────────────────────────────┐ │
│  │         ┌───┐                       │ │
│  │    ┌──┐ │ 72│                       │ │
│  │ ───┤68├──┴───┴──┤ 65 ├──┤ 72       │ │
│  │    └──┘          └──┴──────────     │ │
│  │                                     │ │
│  │  周均值 68.4   趋势: → 持平          │ │
│  └──────────────────────────────────────┘ │
│                                         │
│  影响因素: 步态评分 87 | 睡眠质量 82 | 久坐 55 │
└─────────────────────────────────────────┘
```

**身体状态得分计算（本地算法）**:

```
gaitScore      = 步态评分（来自 HKQuantityTypeIdentifierWalkingSpeed + WalkingDoubleSupport）
sleepScore     = 睡眠时长评分 + 睡眠质量修正
sedentaryScore = 久坐风险评分

身体状态得分 = gaitScore × 0.4 + sleepScore × 0.3 + sedentaryScore × 0.3
```

| 维度 | 指标 | 计算方式 |
|---|---|---|
| 步态评分 | gaitScore | 速度 1.0-1.4 m/s +10，双脚支撑 25-33% +10，夜间清醒每次 -3，base 80 |
| 睡眠时长 | sleepMinutes | <5h = 40分，5-6h = 60分，6-7h = 80分，7-9h = 100分 |
| 睡眠质量 | sleepQuality | 连续=100，轻度中断=80，中断=60，碎片化=40 |
| 久坐风险 | sedentaryMinutes | <60min=100，60-120=80，120-240=60，>240=30 |

**LLM 综合得分** = 直接复用 Morning Report 的 `llmScore`，与本地算法得分并列展示，互相验证。

### 5.5 历史日报列表（趋势页内嵌）

```
┌─ 历史日报 ────────────────────────────────┐
│  06/15  昨天        72分  详情 →         │
│  06/14  前天        68分  详情 →         │
│  06/13  大前天      65分  详情 →         │
│  …                                       │
└───────────────────────────────────────────┘
```

- 每日一行，点击 → push `MorningReportDetailView`
- 支持删除操作（滑动删除）

---

## 六、Prompt 设计（LLM 分析）

### 6.1 系统 Prompt（固定结构）

```
你是一位专业的 iOS 健康数据分析师。根据用户昨日的 HealthKit 数据，
生成一份晨间健康报告。

数据来源：步数、步行速度、双脚支撑百分比、睡眠分析、耳机音量暴露（夜间清醒判断）、久坐时长。

输出格式（严格按以下 JSON 结构返回，不要输出任何其他内容）：

{
  "summary": "综合评估段落（50-80字）",
  "score": 综合健康得分（0-100整数）,
  "shortAdvice": ["短期建议1", "短期建议2", "短期建议3"],
  "longAdvice": ["长期建议1", "长期建议2", "长期建议3"],
  "detail": "详细分析段落（150-200字），涵盖睡眠结构、久坐风险、运动充足性、步态与疲惫度"
}

注意事项：
- score 必须与 summary 文字内容一致
- shortAdvice 3-4 条，具体可执行
- longAdvice 3-4 条，面向健康管理长期目标
- detail 段落要引用具体数据（如具体时间、分钟数）
```

### 6.2 用户 Prompt（注入数据，每日变化）

```
昨日数据：
- 睡眠: {sleepMinutes}分钟，夜间清醒 {sleepMidnightWake}分钟，质量: {sleepQuality}
- 起床时间: {wakeUpTime}
- 步行: {walkMinutes}分钟，步数 {steps}步，平均步速 {avgSpeed}m/s，双脚支撑 {doubleSupport}%
- 久坐: {sedentaryMinutes}分钟，最长连续 {longestSedentaryMin}分钟（{longestSedentaryRange}）
- 步态评分: {gaitScore}/100

请生成健康报告。
```

---

## 七、文件变更清单

| 操作 | 文件 |
|---|---|
| 新增 | `Stick/Services/MorningReportStore.swift` — 报告存储（load/save/delete，30天清理） |
| 新增 | `Stick/Services/MorningReportGenerator.swift` — 报告生成逻辑（数据收集+LLM调用+落盘） |
| 新增 | `Stick/Services/NotificationService.swift` — UNUserNotificationCenter 管理 |
| 新增 | `Stick/Services/BodyStateScorer.swift` — 身体状态得分本地算法 |
| 修改 | `Stick/Services/HealthKitService.swift` — 新增昨日数据查询方法 |
| 新增 | `Stick/Views/MorningReportTab.swift` — 报告 Tab 入口 + 历史列表 |
| 新增 | `Stick/Views/MorningReportDetailView.swift` — 完整报告视图 |
| 新增 | `Stick/Views/TrendDataPage.swift` — 趋势数据页 |
| 新增 | `Stick/Views/Components/MetricTrendCard.swift` — 指标趋势柱状卡片组件 |
| 新增 | `Stick/Views/Components/BodyScoreTrendChart.swift` — 身体得分折线图组件 |
| 新增 | `StickNotificationContent/` — Notification Content Extension target |
| 修改 | `Stick/Views/PersonalView.swift` — 趋势数据入口 |
| 修改 | `Stick/StickApp.swift` — 注册 Notification Category |
| 修改 | `Stick/Info.plist` — 新增 Notification Content Extension 配置 |
| 新增 | `Stick/MorningReportEntry.swift` — AppIntent，打开报告 Tab |

---

## 八、依赖关系

```
解锁触发
    │
    ├── HealthKitService.hasStepData(today)
    │
    ├── MorningReportGenerator.generate(for: yesterday)
    │       │
    │       ├── HealthKitService.queryYesterdaySnapshots()
    │       │
    │       ├── LLMService.sendMessage(prompt) → parse JSON
    │       │
    │       ├── BodyStateScorer.compute(snapshots, gaitScore) → bodyStateScore
    │       │
    │       ├── MorningReportStore.save(report) → Documents/MorningReports/{date}.json
    │       │
    │       └── NotificationService.notify(report) → UNUserNotificationCenter
    │
    └── MorningReportTab
            ├── MorningReportStore.loadAll() → [MorningReport]（历史列表）
            └── MorningReportDetailView（点进去的详情）

TrendDataPage
    ├── MorningReportStore.loadAll() → 30天数据
    ├── MorningReportStore.loadRange(7days) / loadRange(30days)
    └── BodyStateScorer.computeTrend([report]) → 趋势分析
```

---

## 九、技术实现要点

### 9.1 解锁检测

- iOS 无直接"解锁完成"API，用 **CoreTiming** 监听 `com.apple.springboard.unlock` 事件
- 或用 **_background task** 注册 `BGAppRefreshTask`，系统在用户活动时触发
- 备用方案：**LocalAuthentication** 每次 `LAContext.evaluatePolicy` 成功后视为一次活跃使用

### 9.2 起床判断

复用 `HealthKitService.queryWakeUpTime()` — 扫描当日第一条 >50 步的时间作为起床时间，步数进来后才会触发。

### 9.3 报告生成时机控制

```
解锁
  │ sleep 10-20min
  │
  ├─ 步数进来（hasStepData = true）→ 生成 + 通知
  └─ 超过 30min 无步数 → 生成（起床晚或无活动日）
```

### 9.4 Notification Content Extension

- Target name: `StickNotificationContent`
- Widget-like SwiftUI view，读取 `UNNotification` attachment 或共享 App Group 数据
- 不进主 App 直接展示完整报告卡片

### 9.5 本地算分 vs LLM 评分

| 维度 | 本地算法 | LLM 评分 |
|---|---|---|
| 速度 | 即时 | 慢（需 API） |
| 可解释性 | 透明，公式可见 | 黑盒 |
| 综合判断 | 固定权重 | 语义理解 |

两者并列展示，本地算法作为即时预览，LLM 评分作为最终报告分数。

---

## 十、Spec Self-Review

- [x] 所有 JSON 字段可解析，无 TBD
- [x] 解锁触发 / 起床判断 / 通知发送三个阶段无矛盾
- [x] Notification Content Extension 与主 App 数据共享路径明确（App Group UserDefaults）
- [x] 30 天存储 + 清理逻辑已说明
- [x] LLM Prompt 结构固定，适合历史对比
- [x] 趋势页三大指标 + 身体得分 + 历史列表，scope 聚焦
