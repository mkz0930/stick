# bugs.md — 踩坑记录
## 已确认方案

| 日期 | 摘要 | 根因 | 修复 |
|---|---|---|---|
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
