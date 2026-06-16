# 饮食记录 + 血氧提取 设计方案

**日期**: 2026-06-15
**状态**: 草稿，待确认

---

## 一、血氧提取（BodyMetricsStore 扩展）

### 1.1 需求

在 `BodyMetricsStore.extract(from:)` 中新增血氧 regex，从用户自然语言输入中提取血氧值并持久化到 UserDefaults。

### 1.2 支持的模式

| 模式 | 示例 |
|---|---|
| 血氧 XX% | "血氧 98%"、"血氧98%" |
| 血氧 XX | "血氧 95"、"血氧:95" |
| 带单位 | "血氧 97%"、"血氧 94％" |

### 1.3 验证规则

- 阈值范围: 90% ~ 100%（低于 90% 为异常，不记录）
- 存储字段: `bloodOxygen: Int?`
- 已有值不覆盖（除非用户明确说出新值）

### 1.4 UserDefaults Key

- key: `"body.bloodOxygen"`
- init 读取、save 写入

---

## 二、饮食记录（FoodLogStore + DataRecordView）

### 2.1 存储结构

**FoodLogStore** (`@MainActor final class`):

```swift
struct FoodEntry: Identifiable, Codable {
    let id: UUID
    let meal: MealType       // breakfast / lunch / dinner
    let foodName: String     // 食物名称（LLM 识别结果）
    let calories: Int?       // 热量 kcal（LLM 估算，可能为 nil）
    let timestamp: Date
}

enum MealType: String, Codable {
    case breakfast, lunch, dinner
}
```

**持久化**: JSON 编码存 UserDefaults，key = `"food.log"`，每天独立一条记录（按日期分组）。

### 2.2 餐次判断规则

根据拍照时间（`Date()`）判断餐次：

| 时段 | 餐次 |
|---|---|
| 06:00 ~ 09:00 | breakfast |
| 11:00 ~ 13:00 | lunch |
| 17:00 ~ 20:00 | dinner |
| 其他时段 | 归入最近的一餐（20点前归晚餐，20点后归次日早餐的逻辑不采用；一律按时间判断，未命中则不记录） |

> 注：用户手动文字输入食物时（如"中午吃了米饭和青菜"），不触发自动餐次判断，沿用对话分析流程——由 LLM 返回结构化数据后判断餐次。

### 2.3 LLM 视觉分析流程

1. 用户拍照 → `ChatOverlay` 调用 `LLMService.sendMessageStreamWithImage`
2. LLM 返回文字描述（含食物名称、热量估算）
3. **不等待用户确认**，直接从 LLM 返回内容中解析食物名称和热量
4. 解析成功后 → 构建 `FoodEntry` → 写入 `FoodLogStore`

**解析策略**（从 LLM 回复文本中 regex 提取）：

- 热量 pattern: `(\d+)\s*(?:千卡|kcal|卡路里|卡|热量)` → 提取数字
- 食物名称 pattern: 冒号/逗号/换行分隔，取含食物名的片段
- 如果 LLM 回复不含热量但含食物名 → 记录食物名，`calories = nil`
- 如果 LLM 未识别出食物 → 不记录

### 2.4 DataRecordView 饮食卡片 UI

```
┌─────────────────────────────────┐
│ 🍴 饮食记录                       │
│                                │
│ 今日摄入        目标            │
│ 1350 kcal    1800 kcal         │
│ ████████████░░░░░░░  75%       │
│                                │
│ 早餐  520 kcal                  │
│   · 馒头 × 1 + 鸡蛋 × 1        │
│ 午餐  650 kcal                  │
│   · 米饭 + 青菜 + 鸡腿 × 1      │
│ 晚餐  180 kcal                  │
│   · 苹果 × 1                   │
└─────────────────────────────────┘
```

**布局说明**：
- 顶行: 总热量数值 + 目标值 + 进度条（横向进度条，75% 填充）
- 各餐明细: 餐次名 + kcal + 食物名称列表（用 `·` 前缀）
- kcal 为 nil 时显示 `"-- kcal"`
- 无记录时显示 `"暂无数据"`

### 2.5 每日目标热量

- 固定值: **1800 kcal**（不提供用户设置入口）
- 进度条 = min(今日总热量 / 1800, 100%)

### 2.6 今日总热量计算

- 遍历今日所有 `FoodEntry`（`timestamp` 在当天 00:00 ~ 23:59 内）
- `totalCalories = entries.compactMap { $0.calories }.reduce(0, +)`
- kcal 为 nil 的 entry 不计入总量但保留食物名称

---

## 三、文件变更清单

| 操作 | 文件 |
|---|---|
| 修改 | `Stick/Services/BodyMetricsStore.swift` — 新增 `bloodOxygen` property + regex |
| 新增 | `Stick/Services/FoodLogStore.swift` — 饮食记录存储（餐次/食物/热量/时间戳） |
| 修改 | `Stick/Views/DataRecordView.swift` — 饮食 card 接入 FoodLogStore |
| 修改 | `Stick/Views/ChatOverlay.swift` — 拍照食物后直接存储（不确认） |

---

## 四、依赖关系

```
ChatOverlay
  └── send(imageData:) → LLMService.sendMessageStreamWithImage
        └── 流式解析 LLM 回复 → FoodLogStore.addEntry()

BodyMetricsStore
  └── extract(from:) → bloodOxygen 写入

DataRecordView
  └── 消费 FoodLogStore.entries → 渲染饮食 card
```

---

## 五、数据流

```
用户拍照
    │
    ▼
ChatOverlay.send(imageData:)
    │
    ▼
LLMService.sendMessageStreamWithImage (视觉模型 qwen-vl-plus)
    │
    ▼
流式解析 LLM 回复 → FoodEntry (meal + foodName + calories)
    │
    ├── calories 有值  → 直接写入 FoodLogStore
    └── calories 为 nil → 写入 FoodEntry(calories: nil)，仍显示食物名

FoodLogStore → UserDefaults["food.log"]
    │
    ▼
DataRecordView 消费 FoodLogStore.todayEntries → 渲染饮食卡片
```

---

## 六、待确认点（实现前需确认）

1. **LLM 回复解析**: 当前 `visionSystemPrompt` 返回自由文本，不是结构化 JSON。从自由文本中 regex 提取食物名和热量的策略是否可行？是否需要改 LLM prompt 让它输出更易解析的格式？
2. **同餐多次拍照**: 用户早餐拍了两次 → 两条 FoodEntry 或合并为一条（合并取合计热量）？
3. **旧数据清理**: FoodLogStore 保留多少天历史？（建议保留 30 天，避免 UserDefaults 无限膨胀）
4. **DataRecordView 饮食卡片**: 进度条颜色是否复用现有 `Theme.dashDiet`？进度条超出 100% 时是否变红/橙色警示？
