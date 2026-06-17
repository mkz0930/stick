# Stick 项目 Bug 日志

记录历史上遇到过的所有 bug，包括症状、根因、修复方式。下次遇到类似问题先查这里。

---

## 2026-06-17 · FeatureRow SEDENTARY 行时间数字对不齐（3 根因）

**症状**
- 真机 iPhone 12 上首页 FeatureRow 展开后的 SEDENTARY 行：
  - 累计值（X.Xh）会突然掉一大截
  - 秒表（M:SS）看起来只按分钟跳，秒数不动
  - 从 walk 切到 sit 时数字瞬间从 X.Xh 跳到 0:00 → N:00

**3 个根因**

### 根因 1 · `tick` 从未被赋值，秒表只按分钟跳

`ios/Stick/ContentView.swift:122` 定义了 `@State private var tick: Int = 0`，但全文件 `grep "tick =\|tick +="` **零结果**。`sitDurationText` 里 `_ = tick` 引用但值不变 → SwiftUI 不触发重渲。

实际驱动 body 重渲的是 `now`，但 `now` 只在分钟边界（line 594 `oldMin != newMin`）或启动后 60s 内才更新 → 秒表分钟数字跳、秒数字不动。

**修复**：把 `tick: Int` 改成 `timerTick: Date`，1s timer 每秒写一次（line 594 新增 `timerTick = nowVal`），秒表真正按秒跳。

### 根因 2 · `homeSedentaryMinutes` 写入路径不一致，sleep 校正缺失

`ios/Stick/ContentView.swift` 三处写入 `homeSedentaryMinutes`：
- line 503（onAppear / 模拟器 mock）— 直接 `await ...todaySedentaryMinutes()`，**不扣 sleep**
- line 738（scenePhase 回前台 async let）— **扣 sleep**（736-741 段）
- line 898（模拟器 flask 按钮）— 直接赋值，**不扣 sleep**

→ 启动后 `homeSedentaryMinutes` 包含睡眠时间（7h+），scenePhase 回前台后突然扣掉 → 累计值从 `5.2h` 跳到 `-1.8h → 0h`。

**修复**：在 line 505 和 898 显式减 sleep，跟 line 738/824 模式一致。

**约束**：sleep 校正**不要**移到 `HealthKitService.todaySedentaryMinutes()` 内部 —— `DataRecordView.swift:59-61` 已经手工扣 sleep，挪进去会双重扣减（每天少 7h+）。修正方案是「在每个 ContentView 写入点显式扣」，不是「在函数内部扣」。

### 根因 3 · 切到 sit 时是异步 Task，`displayValue` 100-500ms 跳变

`ios/Stick/ContentView.swift:668-707` `onChange(of: displayState)`：切到 .sit 时是 `Task { ... }`，等异步 `currentSedentarySessionMinutes(hours: 4)` 完成才设 `currentSitStartTime`。

100-500ms 期间 `currentSitStartTime = nil` → `sitDurationText = nil` → `displayValue = nil ?? todaySitDescription = "X.Xh"` → Task 完成后切到秒表 M:SS。

→ 用户看到 `X.Xh → M:SS` 跳变。

**修复**：onChange 切 .sit 时同步设 `currentSitStartTime = Date()`、`currentSitMinutes = 0`（秒表立即从 0:00 起跳），Task 完成后用 `sitMins` 修正。

---

## 2026-06-17 · `DayTimelineView` 触发 SwiftUI "Modifying state during view update" 警告

**症状**
- 真机 iPhone 12 上点开 app，Xcode console 反复刷出 **14 条** `SwiftUI: Modifying state during view update, this will cause undefined behavior.`
- 启动 280ms 内必刷完
- 不是 crash，但 undefined behavior，加新 view 时会埋雷
- 模拟器 100% 复现

**触发链**（subagent 排查得出）
`ios/Stick/Views/DayTimelineView.swift` 用 `@State` 缓存 walk 胶囊，view body 里直接调 `syncWalkCacheIfNeeded(in:)` 写 `@State`：

```swift
// ❌ 旧实现
@State private var cachedWalkSegments: [WalkVisualSegment] = []
@State private var cachedScheduleSig: String = ""

private func syncWalkCacheIfNeeded(in height: CGFloat) {
    let sig = schedule.map { "..." }.joined(separator: "|")
    if sig != cachedScheduleSig {
        cachedScheduleSig = sig                        // ← 在 body 内写 @State
        cachedWalkSegments = computeWalkVisualSegments(in: height)
    }
}

// body 里：
private var track: some View {
    GeometryReader { geo in
        syncWalkCacheIfNeeded(in: geo.size.height)     // ← SwiftUI 反模式
        ...
    }
}
```

启动时 `hk.realDaySchedule` 由 nil → 真实数组连续变化 7 次 → 每次 body 重算触发 2 次 `@State` 写入 → 14 条警告。

**修复**（commit `719fbda`）
直接删缓存，body 里 `let` 算：

```swift
// ✅ 新实现
private var track: some View {
    GeometryReader { geo in
        let height = geo.size.height
        let walkSegments = computeWalkVisualSegments(in: height)  // 纯计算
        ...
    }
}
```

schedule 变化已经由 `View.Equatable` + ContentView 的 `.equatable()` 守门，walk 胶囊重算 < 1ms 可忽略。

**验证**
- sim 上 `xcrun simctl spawn log stream --predicate 'subsystem == "com.apple.runtime-issues" AND category == "SwiftUI"'` 监控 60s
- 修复前：启动 280ms 内 14 条
- 修复后：60s 内 0 条

**关键教训**
- **永远不要在 view body 里写 `@State`** —— 哪怕是「缓存」目的也不行。`@State` 是 view 自己的 source-of-truth，body 是只读派生计算。要缓存就放到 `let` + computed property，或者用 `Equatable` view 配合 stable input
- 任何「在 body 内调函数写 @State」的代码都是反模式，必须删
- SwiftUI runtime warning 用 `subsystem=="com.apple.runtime-issues" AND category=="SwiftUI"` predicate 过滤最干净

---

## 2026-06-17 · `detectNightWakePeriods` 跨午夜 Range 崩溃（真机 iPhone 12）

**症状**
- 真机 `马振坤的iPhone`（iPhone 12, iPhone13,2, iOS 26.5）点开 app 立刻闪退
- 崩溃只发生在真机（有跨午夜的 sleep samples），模拟器无 HealthKit mock 触发不到
- 设备 crash logs：`/tmp/device-crashes/Stick-2026-06-17-095129.ips` 等多条（pull 命令：`xcrun devicectl device copy from --device $UDID --domain-type systemCrashLogs --source / --destination /tmp/`）

**崩溃签名**
```
Swift/arm64e-apple-ios.swiftinterface:6292: Fatal error: Range requires lowerBound <= upperBound
EXC_BREAKPOINT (SIGTRAP)
```

**触发栈**
```
_assertionFailure
closure #1 in closure #1 in HealthKitService.detectNightWakePeriods()
HKSampleQuery completion callback
```

**根因**
文件 `ios/Stick/Services/HealthKitService.swift` line ~520 的 `detectNightWakePeriods()` 用 `StickState.minutesOfDay(s.startDate)`（返回 0-1439 的「分钟-of-day」）做连续性判断：

```swift
let m = StickState.minutesOfDay(s.startDate)
...
} else if m - (cLast ?? 0) <= 10 {       // ← bug
    cLast = m
} else {
    if let s = cStart, let l = cLast {
        ranges.append(s...l)              // ← cStart=1435 > cLast=1 → 断言炸
    }
}
```

跨午夜的 sleep samples（如 23:55 的 awake → 00:01 的下一段）：
- `m = 1`，`cLast = 1435`，`m - cLast = -1434`
- `-1434 ≤ 10` 被误判为「连续 10 分钟内」
- 闭合时 `cStart = 1435, cLast = 1`，`1435...1` 触发 `lowerBound ≤ upperBound` 断言

**修复**（commit `d6442b1`）
改用 `Date.timeIntervalSince` 算真实秒数差，加一个 `lastDate: Date?` 跟踪：

```swift
var lastDate: Date? = nil
for s in samples {
    let m = StickState.minutesOfDay(s.startDate)
    if cStart == nil {
        cStart = m; cLast = m; lastDate = s.startDate
    } else if let last = lastDate,
              s.startDate.timeIntervalSince(last) / 60.0 <= 10 {
        cLast = m; lastDate = s.startDate
    } else {
        if let s = cStart, let l = cLast { ranges.append(s...l) }
        cStart = m; cLast = m; lastDate = s.startDate
    }
}
```

**关键教训**
- **凡是「时间连续性 / 区间判断」都要用绝对 Date.timeIntervalSince，绝不能只用「分钟-of-day / 小时-of-day」差**——后者在跨午夜时会出现负大数
- 真机专属 bug：模拟器没 HealthKit 真实数据测不到跨午夜 samples，必须真机回归
- 真机装新 build 命令：
  ```bash
  xcodebuild -project Stick.xcodeproj -scheme Stick \
    -destination "platform=iOS,id=$UDID" -configuration Debug \
    -allowProvisioningUpdates build
  xcrun devicectl device install app --device $UDID "$APP_PATH"
  xcrun devicectl device process launch --device $UDID com.stick.app.h
  ```
- 拉真机 crash log 命令：`xcrun devicectl device copy from --device $UDID --domain-type systemCrashLogs --source / --destination /tmp/`

---

## 2026-06-17 · `observePendingChatSeed` use-after-free 导致闪退

**崩溃签名**
```
EXC_BAD_ACCESS (SIGSEGV) at 0x0000000000000008
  KERN_INVALID_ADDRESS at offset 8  → null pointer deref
```

**触发栈**
```
swift_retain  ←  closure #1 in closure #1 in
                static SharedStateStore.observePendingChatSeed(_:)
                ←  SharedState.swift:126
```

**根因**
`ios/SharedKit/SharedState.swift` 的 `observePendingChatSeed`：

```swift
// ❌ 旧实现
static func observePendingChatSeed(_ handler: @escaping () -> Void) {
    let box = ObserverBox(handler)
    observerBoxHolder = box                  // ← 覆盖就释放旧的
    let observer = Unmanaged.passUnretained(box).toOpaque()
    CFNotificationCenterAddObserver(center, observer, { ... }, ...)
}
```

调用方 `StickApp.swift:20` 的 `.onAppear` 在 view 生命周期里会触发多次，每次都跑 `observePendingChatSeed`：
1. 第一次：建 box1，`observerBoxHolder = box1`，注册 CF observer（指向 box1）
2. view 重新出现：建 box2，`observerBoxHolder = box2`，**box1 被 ARC 释放**，但 CF observer 还指向 box1 的内存
3. widget 写 seed 触发 darwin 通知 → C 回调里 `Unmanaged.fromOpaque(observer).takeUnretainedValue()` 读已释放内存 → `swift_retain` 命中 null+8 → SIGSEGV

**修复**（commit `2030e21`）
```swift
// ✅ 新实现
private static let chatObserverBox = ObserverBox({})
private static var isChatObserverRegistered = false

static func observePendingChatSeed(_ handler: @escaping () -> Void) {
    chatObserverBox.updateHandler(handler)   // handler 可替换

    guard !isChatObserverRegistered else { return }
    isChatObserverRegistered = true          // CF observer 只注册一次

    let observer = Unmanaged.passUnretained(chatObserverBox).toOpaque()
    CFNotificationCenterAddObserver(center, observer, { ... }, ...)
}

private final class ObserverBox {
    var handler: () -> Void                   // let → var
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func updateHandler(_ handler: @escaping () -> Void) { self.handler = handler }
}
```

**关键教训**
- SwiftUI `.onAppear` 不是「只触发一次」的保证，navigation / sheet / 视图重建都会让它重跑
- 用 `static var X = X()` + `static var registered = false` 守门，是给静态函数注册全局 observer 的标准模式
- `CFNotificationCenterAddObserver` 注册的 C function 指针的生命周期**不会自动跟随 Swift 闭包 context**，必须自己保证 observer 关联的对象不被释放

---

## 2026-06-17 · `exportTodayData()` 返回 HealthStore 快照数组（误用数据源）

**症状**
- 真机点"今天"导出按钮，下载下来的 `Stick_Export_<ISO>.json` 文件只有 20+ 条记录（且全是 sit 状态的本地快照）
- 导出文件结构是数组 `[{"id":"...","bodyState":"sit","timestamp":"...","incrementalStepCount":0,...}]`，不是预期的 dict `{导出时间, 数据类型:[...]}`
- 同一时段点"7天"按钮能正常导出多类型数据

**根因**
文件 `ios/Stick/Services/HealthKitService.swift` 的 `exportTodayData()` 在某次编辑后被改成了：

```swift
func exportTodayData() async -> URL? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    let data = (try? encoder.encode(HealthStore.shared.today)) ?? Data()   // ← bug
    ...
}
```

`HealthStore.shared.today` 是 app 每分钟抓 HK 后聚合的 `HealthSnapshot` 数组，仅覆盖 app 运行时长（真机可能只 1 天），用于 export 会严重不完整。

**为什么 `exportLast7Days()` 不受影响**：它单独定义在主类里，调 `exportHealthRange` 查 HK 原始样本；只有 `exportTodayData()` 被改坏了。

**修复**（commit `74e06fd`）
删掉导 HealthStore 的版本，改回 `await exportRecentData(days: 1)` 走 HK 路径：

```swift
func exportTodayData() async -> URL? {
    await exportRecentData(days: 1)
}
```

**关键教训**
- **export 函数必须查 HealthKit，不能查 HealthStore**。HealthStore 是聚合缓存，新装 app 数据极少。
- 输出 JSON 是 `[...]` 数组 → 错（这是 HealthStore 快照）。
- 输出 JSON 是 `{导出时间, 数据类型:[...]}` dict → 对（这是 HK 多类型分组）。
- 编辑已有 export 函数前先看 `exportHealthRange` 模板，确认走 HK 原始样本。

详细架构说明 + mock 注入调试约定见 `~/.claude/projects/-Users-horse-work-stick/memory/healthkit_vs_healthstore.md`。

---

<!-- 新 bug 加在上方，时间倒序 -->
