# bugs.md — 踩坑记录
## 已确认方案

| 日期 | 摘要 | 根因 | 修复 |
|---|---|---|---|
| 2026-06-18 | `SharedStateStore.isChatObserverRegistered` 静态布尔值并发竞态：Darwin notify callback 在任意线程读取，主线程写入 | `nonisolated(unsafe)` 静态变量无锁保护 | 添加 `NSLock`（`observerRegisteredLock`）保护 check-and-set 合入 `36445b0` |
| 2026-06-18 | `HealthStore` / `HealthKitService` 导入了 `Combine` 但未使用任何 Combine 类型 | 死 import 增加编译时间 | 删除未使用 import，合入 `1da3c7c` |
| 2026-06-18 | `WidgetGalleryView` 导入了 `WidgetKit` 但未使用任何 WidgetKit 类型 | 死 import 增加编译时间 | 删除未使用 import，合入 `1e9c033` |
| 2026-06-18 | `ChatOverlay` 3 处 `try! NSRegularExpression` 强制 try，正则初始化失败会直接 crash | `try!` 无降级处理 | 改为 `try?` + nil 检查，失败时跳过该处理步骤，合入 `c79eb90` |
| 2026-06-18 | `LLMService.sendMessageStreamWithSearch` 中 `fullText`/`collectedData` 累积但从未读取 | 流式处理代码冗余累加 | 删除未使用变量，合并嵌套结构，合入 `ce40f52` |
| 2026-06-18 | `HealthKitService.captureSnapshot()` async 函数在后台线程执行 `self.lastSnapshot` 和 `self.lastMovementTime` 赋值，可能导致 SwiftUI 视图更新在错误线程触发 | async 函数可能在后台线程执行，`@Published` 属性赋值非线程安全 | 用 `Task { @MainActor in }` 包装赋值操作，合入 `ad321d4` |
| 2026-06-18 | `RealHealthAnalyzer` `completeness / checkCount` 除零崩溃，新装 app 无历史数据时 `checkCount>0` 但 `completeness==0` | `checkCount>0` 但 `completeness==0` 时触发除零 | 增加 `checkCount>0` 守卫，合入 `b910989` |
| 2026-06-18 | `DayPlaybackSheet` `simulatedMinute` 在 `progress=1.0` 时为 1440，但 `.sleep` 最后段条件 `simulatedMinute < endMinute`（即 `1440 < 1440`）永不成，导致 fallback 到 `.walk` | `min/max` 边界处理错误：最后段覆盖到 1440 但 1440 无法严格小于 1440 | 改为 `min(Int(progress * 1440), 1439)`，合入 `4e2ae58` |
| 2026-06-18 | `DayTimelineView` `scrubOffset` 上限 `1440`，拖到 y=0 时 thumb 与 `00:00(now)` 位置重叠 | `abs = (1440 + stableNowMinute) % 1440 = stableNowMinute`，1440 和 0 都映射到当前分钟 | 改为上限 `1439`，正确显示 23:59，合入 `1e0a0fe` |
| 2026-06-18 | `MockHealthDataLoader` `buckets[key]!` force unwrap；`HealthExport/HealthTypeBlock/HealthDataPoint.encode(to:)` 用 `fatalError()` 占位，若触发直接 crash | `buckets[key]` 可能为 nil；Codable encode 用占位实现 | `buckets[key] ?? Bucket()`；实现正确的 Codable encode，合入 `0ed0429` |
| 2026-06-18 | `analyzeYesterdayHeartRateZones` 2 处 `calendar.date(byAdding:)!` force unwrap | `calendar.date` 可能返回 nil | 改为 `guard let` + `return nil`，合入 `ff9b9a3` |
| 2026-06-18 | `HealthKitService`/`HealthTrendAnalyzer`/`MorningReportStore` 9 处 `calendar.date(byAdding:...)!` force unwrap | `calendar.date` 在极端情况可能返回 nil | 改为 `guard let` + 优雅降级（return nil/0/[]），合入 `646e147` |
| 2026-06-18 | `ContentView` 同时有 `@StateObject var hk` 和 `@ObservedObject var hkService = .shared`，两套观察同一单例，浪费资源且语义混乱 | 同一单例被两个属性观察 | 删除冗余的 `hkService` 属性，统一使用 `hk`，合入 `112833f` |
| 2026-06-18 | `HealthKitService.guessWakeUpTime()` 3 处 `calendar.date()!` force unwrap，若日期计算失败会直接 crash | `calendar.date()` 在极端边界情况可能返回 nil | 改为 `guard let` + `return nil`，失败时优雅降级，合入 `e989091` |
| 2026-06-18 | `HealthKitService.exportTodayData()` 函数声明 `URL?`，但内部 `await exportRecentData(days: 1)` 缺少 `return`，导致"导出今日数据"永远返回 `nil` | 缺少 `return` 语句 | 添加 `return`，合入 `db34cd9` |
| 2026-06-18 | `StateInference.swift` 19 处 `score[.X]!` force unwrap，enum 新增状态时若忘记更新字典初始化会 crash | `score` 字典初始化虽含全部 key，但 force unwrap 模式脆弱 | 改为 `score[.X, default: 0]` 下标语法，合入 `ba6e5af` |
| 2026-06-18 | `MorningReportGenerator.parseLLMResponse` 中 `jsonStr.data(using: .utf8)!` 强制解包，若 LLM 返回无效 UTF-8 字符会直接 crash | `data(using: .utf8)` 在字符串含非法字符时返回 nil | 改为 `guard let` 安全解包，失败优雅降级返回 nil，合入 `2ec115a` |
| 2026-06-18 | `HealthAnalyzer.lastNightSleeps` 窗口上限用 `todayNoon.addingTimeInterval(24*3600)`（明天 noon），导致下午的午睡被归入昨夜睡眠，干扰睡眠时长 < 6h 判断 | 窗口应为 [昨天 noon, 今天 noon) 而非 [昨天 noon, 明天 noon) | 改为 `< todayNoon`，正确覆盖跨日窗口，合入 `7aa0467` |
| 2026-06-18 | `SleepParser.swift:92` `bedTime!` 强制解包，`bedTime` 是 `Date?` 类型但 `bed` 已在 if let 中解包 | 有已解包的 `bed` 变量却仍用 forced unwrap | 改用 `bed` 变量，合入 `fcd4e2a` |
| 2026-06-18 | `ObserverBox` 标注 `Sendable` 但含可变存储 `_handler`，Swift 6 严格并发检查报错 | Swift 6 要求 `Sendable` 类的所有存储属性必须不可变 | 移除 `ObserverBox` 的 `Sendable` conformance，合入 `77e9437` |
| 2026-06-18 | `SharedStateStore.ObserverBox`/`chatObserverBox`/`isChatObserverRegistered` 缺 `NSLock`/`nonisolated(unsafe)`，Darwin 通知回调（`CFNotificationCenterAddObserver`）与主线程更新存在数据竞争 | Darwin callback 在独立线程执行，主线程 `handler` 赋值无锁保护 | 添加 `NSLock` 保护 `handler` 读写，`nonisolated(unsafe)` 标记只写一次的静态属性，合入 `b1905c4` |
| 2026-06-17 | 30s 久坐 timer 的 `prevMinutes` 在 Task 创建前捕获，Task 异步执行期间 `onChange(of: hkService.lastMovementTime)` 可能已修改 `currentSitMinutes`，导致比较时用到 stale 数据，错误更新 `currentSitStartTime` | `prevMinutes = currentSitMinutes` 在 Task 外捕获，但 Task 异步期间 `lastMovementTime` onChange 可修改 `currentSitMinutes` | 把 `prevMinutes` 读取移入 Task 内部，用 `MainActor.run` 保证原子性，合入 main |
| 2026-06-17 | `todaySleepHours()` 累加所有 sleepAnalysis 样本时长，包括 Awake（value=4）和 InBed（value=0,1）状态 | 只按 sample.endDate - startDate 累加，未过滤 sample.value 类型 | 只统计 Asleep（value=2,3,5,6），排除 Awake 和 InBed，合入 main |
| 2026-06-17 | `lastSitAnalysisTime` 初始化为 `.distantPast` 导致首次 timer 触发时分析立即执行（0 秒等待） | `.distantPast` 使 `Date().timeIntervalSince(.distantPast) >= 30` 首次即真 | 改为 `Date()` 使首次 timer 触发时距初始化仅 ~0 秒，分析等待 30 秒后再执行，合入 `2917c3a` |
| 2026-06-17 | StickFigureView `drawSleep` / `drawWalk` 脚部坐标超出 240×320 | drawSleep: knee.x=240 导致 foot 右侧最远 x=256 超 16px；drawWalk 左脚 y=322 超 2px | knee.x→232，foot 右侧收窄到 x=240；左脚 ankle.y→318，foot 起点 y→318，合入 main |
| 2026-06-17 | `computeDaySchedule` 凌晨 00:00-07:00 被误判为 .sit 而非 .sleep | gap 检测逻辑跨午夜计算错误（minute - lastActiveMinute 在午夜边界产生负数） | 增加独立夜间小时判断（h >= 22 \|\| h < 7），合入 `1f5b0d2` |
| 2026-06-17 | drawScene ground=322 超出 240×320 坐标系 | 硬编码坐标值不符注释约定 | 统一改为 ground=320，合入 `b6379ec` |
| 2026-06-17 | Widget 背景色硬编码暖白色 | 未使用 Theme 变量 | 改用 `Theme.darkPanel`（navy)，合入 `2b40acf` |

## 失败方案

## 已知风险
