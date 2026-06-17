# Stick 项目 Bug 日志

记录历史上遇到过的所有 bug，包括症状、根因、修复方式。下次遇到类似问题先查这里。

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

<!-- 新 bug 加在上方，时间倒序 -->
