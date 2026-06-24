import Foundation
import SwiftUI

@preconcurrency import Darwin

#if canImport(WidgetKit)
import WidgetKit
#endif

/// 主 app ↔ Widget 共享状态。App Group: `group.com.stick.app.h`
struct SharedStickState: Codable, Equatable {
    /// 状态名（walk / sit / sleep），也用作 widget 路由
    var stateRaw: String
    /// 英文名（WALKING / SITTING / SLEEPING）
    var englishName: String
    /// 动作短语（"能量输出" / "深度专注" / "深度修复"）
    var actionPhrase: String
    /// 心率 (bpm)
    var heartRate: Int
    /// 心情 (良好 / 一般 / 疲惫)
    var mood: String
    /// 行走 / 久坐 / 入睡 累计分钟（用于 widget 第三指标）
    var durationMinutes: Int
    /// 副标题描述
    var subLine: String
    /// 最后更新时间（用于 widget 显示 "X 分钟前更新"）
    var updatedAt: Date
    /// 当前连续久坐秒数（Live Activity 和 Widget 共享）
    var currentSedentarySeconds: Int
    /// 久坐 session 开始时间
    var sedentaryStartTime: Date?

    static let placeholder = SharedStickState(
        stateRaw: "walk",
        englishName: "WALKING",
        actionPhrase: "能量输出",
        heartRate: 92,
        mood: "良好",
        durationMinutes: 18,
        subLine: "步态稳定 · 心率 92 bpm",
        updatedAt: Date(),
        currentSedentarySeconds: 0,
        sedentaryStartTime: nil
    )
}

/// 读写 App Group UserDefaults 的薄封装
enum SharedStateStore {
    static let appGroupID = "group.com.stick.app.h"
    private static let key = "stick.currentState.v1"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func read() -> SharedStickState {
        guard let data = defaults?.data(forKey: key),
              let state = try? JSONDecoder().decode(SharedStickState.self, from: data)
        else { return .placeholder }
        return state
    }

    static func write(_ state: SharedStickState) {
        guard let defaults = defaults else { return }
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
        // 注：caller 负责触发 WidgetCenter.shared.reloadAllTimelines()，并加 50ms 延迟
        // 保证 UserDefaults fsync 完成后再让 widget 读取，避免陈旧 1 帧
    }

    // MARK: - Widget → App：pending risk alert（OpenRiskAlertIntent 写，主 app 读）
    // 写：widget 上点 OpenRiskAlertIntent → 写 sitDuration + heartRate
    // 读：主 app 进入前台时 → 解析 → 弹 WidgetRiskAlertSheet
    // （绕开 widgetURL 的 "在 'Stick' 中打开?" 系统确认框）

    private static let pendingRiskAlertKey = "stick.pendingRiskAlert.v1"

    static func writePendingRiskAlert(sitDurationMinutes: Int, heartRate: Int) {
        let payload: [String: Int] = [
            "sitDurationMinutes": sitDurationMinutes,
            "heartRate": heartRate,
        ]
        defaults?.set(payload, forKey: pendingRiskAlertKey)
    }

    static func readAndClearPendingRiskAlert() -> (sitDurationMinutes: Int, heartRate: Int)? {
        guard let payload = defaults?.dictionary(forKey: pendingRiskAlertKey) as? [String: Int],
              let duration = payload["sitDurationMinutes"],
              let heartRate = payload["heartRate"]
        else { return nil }
        defaults?.removeObject(forKey: pendingRiskAlertKey)
        return (duration, heartRate)
    }

    // MARK: - Widget → App：pending chat seed
    // widget 上的 OpenChatIntent 写 shared state；主 app 启动 / 进入前台时读出并打开 chat

    private static let pendingChatSeedKey = "stick.pendingChatSeed.v1"
    /// Darwin 通知名：widget 写完 seed 后广播，主 app 即使已在前台也能收到
    static let pendingChatSeedNotifyName = "com.stick.app.pendingChatSeed"

    /// widget 上的 OpenChatIntent 调 perform() 时写入
    static func writePendingChatSeed(_ seed: String) {
        guard !seed.isEmpty else { return }
        defaults?.set(seed, forKey: pendingChatSeedKey)
        // 跨进程通知：即使主 app 已经在前台，也能立即唤醒 drain
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(pendingChatSeedNotifyName as CFString),
            nil, nil, true
        )
    }

    /// 主 app 读出后立即清空，避免下次启动重复打开
    static func readAndClearPendingChatSeed() -> String? {
        guard let seed = defaults?.string(forKey: pendingChatSeedKey),
              !seed.isEmpty else { return nil }
        defaults?.removeObject(forKey: pendingChatSeedKey)
        return seed
    }

    /// 持有 observer box 避免被释放（observePendingChatSeed 内部使用）
    private static let chatObserverBox = ObserverBox({})
    /// 保证 CF observer 只注册一次，避免 SwiftUI .onAppear 多次触发导致前一个 box 被释放、悬空指针崩溃
    /// 用锁保护：CF callback（任意线程）写，主线程读写
    private static var isChatObserverRegistered = false
    private static let observerRegisteredLock = NSLock()

    /// 主 app 监听 widget 写入事件（即使在前台也能收到）
    static func observePendingChatSeed(_ handler: @escaping () -> Void) {
        // 永远更新 box 里持有的 handler（最新注册者生效）
        // 但 CF observer 只注册一次，避免重复注册覆盖前一个 box 引发 use-after-free
        chatObserverBox.updateHandler(handler)

        observerRegisteredLock.lock()
        guard !isChatObserverRegistered else {
            observerRegisteredLock.unlock()
            return
        }
        isChatObserverRegistered = true
        observerRegisteredLock.unlock()

        let observer = Unmanaged.passUnretained(chatObserverBox).toOpaque()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<ObserverBox>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    box.handler()
                }
            },
            pendingChatSeedNotifyName as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// 用于跨进程回调持有闭包
    /// 用 NSLock 保护 handler 的读写，确保从 Darwin callback（任意线程）读取时数据安全
    /// 注意：不标注 Sendable，因为 @Sendable 要求所有存储属性不可变，
    /// 而此类需要通过 updateHandler 更新闭包。lock 已提供线程安全保证。
    private final class ObserverBox {
        private let lock = NSLock()
        private var _handler: () -> Void
        var handler: () -> Void {
            lock.lock()
            defer { lock.unlock() }
            return _handler
        }
        init(_ handler: @escaping () -> Void) { self._handler = handler }
        func updateHandler(_ handler: @escaping () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            self._handler = handler
        }
    }
}

// MARK: - Theme（主 app + Widget 共享，避免重复定义）

enum Theme {
    /// 页面渐变背景（白到极浅冷灰）
    static let bgTop    = Color(red: 1.00,  green: 1.00,  blue: 1.00)
    static let bgBottom = Color(red: 0.97,  green: 0.98,  blue: 0.99)

    /// 卡片
    static let card       = Color.white
    static let cardBorder = Color.black.opacity(0.04)

    /// 文字
    static let navy  = Color(red: 0.30, green: 0.36, blue: 0.44)  // #4D5C70
    static let slate = Color(red: 0.50, green: 0.56, blue: 0.62)  // #7F8E9E
    static let mist  = Color(red: 0.68, green: 0.73, blue: 0.78)  // #AEBAC7

    /// 网格 / 分割
    static let grid       = Color.black.opacity(0.015)
    static let gridStrong = Color.black.opacity(0.025)
    static let border     = Color.black.opacity(0.04)
    static let borderSoft = Color.black.opacity(0.025)
    static let divider    = Color.black.opacity(0.04)

    /// 深色面板
    static let darkPanel = navy
    static let darkText  = Color.white
    static let darkMuted = mist

    /// 火柴人描边默认色（柔和深灰）
    static let figureStroke = navy
    /// 火柴人内部填充（头/手/脚）默认色：纯白
    static let figureFill   = Color.white

    /// 健康仪表盘 — 卡片图标色（数据记录页用）
    static let dashSleep    = Color(red: 0.55, green: 0.50, blue: 0.90)   // 睡眠 紫
    static let dashSteps    = Color(red: 0.20, green: 0.75, blue: 0.50)   // 步数/运动 绿
    static let dashDiet     = Color(red: 0.55, green: 0.50, blue: 0.90)   // 饮食 紫
    static let dashBody     = Color(red: 0.20, green: 0.75, blue: 0.50)   // 身材 绿
    static let dashBlood    = Color(red: 0.55, green: 0.50, blue: 0.90)   // 血压/血糖 紫
    static let dashSedentary = Color(red: 0.92, green: 0.55, blue: 0.20)   // 久坐 橙

    /// 状态色（stick figure 关节 / 强调点 / 状态徽章）
    static let stateWalk  = Color(red: 0.02, green: 0.59, blue: 0.41)  // #059669
    static let stateStand = Color(red: 0.55, green: 0.71, blue: 0.06)
    static let stateSit   = Color(red: 0.92, green: 0.34, blue: 0.05)  // #EA580C
    static let stateSleep = Color(red: 0.70, green: 0.60, blue: 0.98)

    /// 状态软色（背景柔光 / 卡片左 border）
    static let stateWalkSoft  = Color(red: 0.85, green: 0.94, blue: 0.90)
    static let stateStandSoft = Color(red: 0.93, green: 0.97, blue: 0.85)
    static let stateSitSoft   = Color(red: 0.99, green: 0.91, blue: 0.83)
    static let stateSleepSoft = Color(red: 0.95, green: 0.93, blue: 1.0)

    /// 风险 / 警示色
    static let riskHigh = Color(red: 0.95, green: 0.30, blue: 0.20)  // 警示红
    static let riskWarn = Color(red: 0.96, green: 0.62, blue: 0.10)  // 橙
    static let riskOk   = Color(red: 0.02, green: 0.59, blue: 0.41)  // 绿
    static let riskInfo = Color(red: 0.62, green: 0.82, blue: 0.98)  // 蓝
}
