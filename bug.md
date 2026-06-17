# Stick 项目 Bug 日志

记录历史上遇到过的所有 bug，包括症状、根因、修复方式。下次遇到类似问题先查这里。

---

## 2026-06-17 · `observePendingChatSeed` use-after-free 导致闪退

**症状**
- 用户用着用着点开 app 就闪退
- 启动后约 2 秒内必崩
- 崩溃日志：`~/Library/Logs/DiagnosticReports/Stick-2026-06-16-181653.ips`

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
