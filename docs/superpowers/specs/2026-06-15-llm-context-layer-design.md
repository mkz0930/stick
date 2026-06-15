# LLM Context Layer 设计文档

## 目标

让 LLM 更懂用户，通过三层结构化上下文注入：用户关注标签 → 健康趋势语义化 → 短期/长期画像分层。

## 架构概览

```
用户发消息
    │
    ├─► TopicExtractor.extract(text)
    │       └─► UserInterestTagStore.record(tags)
    │               ├─ shortTermScores (周重置)
    │               └─ longTermScores  (年重置)
    │                       ↓
    │               topTags(5) → buildContext() → 【用户关注标签】
    │
    ├─► HealthStore
    │       └─► HealthTrendAnalyzer.analyze(today, all)
    │               └─ semanticLines → buildContext() → 【健康趋势语义化】
    │
    └─► UserProfileStore
            ├─ shortTermScores (周/月衰减)
            │       └─ topShortTermTags(3) → buildContext() → 【当前关注焦点】
            └─ profile (年触发总结)
                    └─ profileContextBlock() → buildContext() → 【用户长期画像】
```

## 新增文件

### 1. `Services/HealthTrendAnalyzer.swift`

输入：`today: [HealthSnapshot]`, `all: [HealthSnapshot]`

输出：
```swift
struct HealthTrend {
    let sedentaryStreakMinutes: Int?   // 连续久坐分钟数，nil=无连续段
    let sedentaryDays: Int              // 连续久坐超标天数（>2h/天）
    let stepTrendPct: Int               // 今日 vs 昨日步数 %
    let avgStepDiffPct: Int            // 今日 vs 7日平均 %
    let sleepDebtMinutes: Int?         // 睡眠缺口（目标7.5h），nil=无法计算
    let semanticLines: [String]         // LLM可直接引用的语义句数组
}
```

**语义句示例：**
- "你已连续久坐 3 小时 20 分钟，期间未起身活动"
- "今日步数 3,200 步，比昨日低 18%"
- "本周睡眠缺口累计达 2.5 小时"

**注入位置：** `buildContext()` 里追加 `【健康趋势语义化】` 段落

---

### 2. `Services/TopicExtractor.swift`

纯规则函数，零延迟：
```swift
enum TopicExtractor {
    static let taxonomy: [String: [String]] = [
        "眼部健康": ["眼睛", "眼干", "眼涩", "视力", "屏幕", "蓝光", "眼疲劳"],
        "骨骼健康": ["腰", "颈椎", "背", "肩", "骨头", "关节", "腰疼", "腰痛"],
        "睡眠问题": ["睡不着", "失眠", "困", "睡眠", "早醒", "深睡", "熬夜"],
        "心血管": ["心率", "血压", "胸闷", "心脏"],
        "消化系统": ["胃", "便秘", "消化", "腹胀", "午饭", "午饭"],
        "运动健身": ["跑步", "走路", "步数", "运动", "拉伸", "锻炼"],
        "情绪压力": ["焦虑", "压力", "烦躁", "心情", "低落", "情绪"],
        "饮食营养": ["咖啡", "茶", "水", "吃饭", "蔬菜", "维生素"],
    ]

    static func extract(from text: String) -> [String]
}
```

---

### 3. `Services/UserInterestTagStore.swift`

```swift
@MainActor
final class UserInterestTagStore: ObservableObject {
    static let shared = UserInterestTagStore()

    // 短期（周重置）
    @Published private(set) var shortTermScores: [String: Double] = [:]
    // 长期（年重置）
    @Published private(set) var longTermScores: [String: Double] = [:]

    private let shortTermKey = "stick.tags.shortterm.v1"
    private let longTermKey  = "stick.tags.longterm.v1"

    /// 每次用户发消息时调用
    func record(tags: [String])

    /// 返回短期权重最高的标签
    func topShortTermTags(limit: Int = 5) -> [String]

    /// 返回长期权重最高的标签
    func topLongTermTags(limit: Int = 5) -> [String]

    /// 周重置
    func resetShortTerm()

    /// 年重置（首条消息算起365天）
    func resetLongTermIfExpired()
}
```

权重计算：同标签重复出现 → +1.0 分，7天后衰减50%

---

### 4. `Models/PersistedChatMessage` 改造

`PersistedChatMessage` 新增 `tags: [String]` 字段，随消息一起写入 ChatHistoryStore，不额外存储。

---

## 改造文件

### `Services/UserProfileStore.swift`

- `summaryInterval` 从 10 改为 **50**（50条 user 消息触发长期总结，降低频率）
- 新增 `shortTermScores: [String: Double]`（周衰减）
- 新增 `topShortTermTags(limit: Int) -> [String]`
- 长期 profile **按年**触发总结（`resetYearly`）

### `Views/ChatOverlay.swift`

`send()` / `sendDirect()` 中新增：
```swift
// 提取标签并记录
let tags = TopicExtractor.extract(from: text)
UserInterestTagStore.shared.record(tags: tags)
UserInterestTagStore.shared.resetShortTermIfExpired()
```

`buildContext()` 改为：
```
【用户关注标签】(topShortTermTags + topLongTermTags)
【健康趋势语义化】(HealthTrendAnalyzer)
【当前关注焦点】(topShortTermTags(3))
【用户长期画像】(profileContextBlock)
【今日健康数据】(原有)
【用户最近问题】(原有)
```

---

## Prompt 注入顺序（buildContext）

```
{profileContextBlock}          ← 长期画像（放在最前，上下文铺垫）

{短/长期标签 block}
【用户关注标签】
- 短期：{topShortTermTags}
- 长期：{topLongTermTags}

{健康趋势 block}
【健康趋势语义化】
{HealthTrend.semanticLines}

{今日数据 block}
【今日健康数据】
（原有 6 项数据）

{最近问题 block}
【用户最近问题】
（原有最近 10 条）

{系统指令}
- 当前时间: {time} ({period})
- 当前姿态: {state}
- 用户类型: 职场白领
- 备注: 给出符合该时段 + 该姿态 + 关注标签的即时可行建议
```

---

## 重置策略

| 维度 | 周期 | 触发条件 |
|------|------|---------|
| 短期标签 | 周 | 每 7 天 或 App 启动时检查 |
| 长期标签 | 年 | 首条消息起 365 天 |
| 用户画像 | 年 | 50 条 user 消息 且 超过 365 天 |

---

## 存储键

| Key | 位置 | 内容 |
|-----|------|------|
| `stick.chat.history.v1` | UserDefaults | 聊天历史（含 tags） |
| `stick.userprofile.v1` | UserDefaults | 长期画像文本 |
| `stick.tags.shortterm.v1` | UserDefaults | 短期标签分数 JSON |
| `stick.tags.longterm.v1` | UserDefaults | 长期标签分数 JSON |
| `Documents/health-snapshots.json` | Documents | 健康快照 |
