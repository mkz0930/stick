import ActivityKit
import Foundation

/// 久坐 Live Activity 管理器（iOS 16.1+ ActivityKit）。
/// 负责启动、更新、结束 SedentaryTimer Live Activity。
@MainActor
@Observable
final class LiveActivityManager {
    /// 单例
    static let shared = LiveActivityManager()

    /// 当前活跃的 Activity
    private var currentActivity: Activity<SedentaryTimerAttributes>?

    /// Live Activity 是否已启动
    private(set) var isActivityActive: Bool = false

    /// 久坐开始的时刻（用于计算 elapsedSeconds）
    private var sedentaryStartTime: Date?

    /// 更新 Timer（每秒驱动 ContentState 刷新）
    private var updateTimer: Timer?

    private init() {}

    // MARK: - Public

    /// 检查设备是否支持 Live Activity（iOS 16.1+ 且用户已开启）
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 开始久坐 Live Activity（仅在支持且未启动时调用）
    /// - Parameter startTime: 久坐开始时刻
    func startSedentaryActivity(from startTime: Date) {
        guard areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities are disabled")
            return
        }
        guard currentActivity == nil else {
            print("[LiveActivityManager] Activity already running")
            return
        }

        let attributes = SedentaryTimerAttributes(currentState: "sit")
        let initialState = SedentaryTimerAttributes.ContentState(
            elapsedSeconds: 0,
            startTime: startTime
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            sedentaryStartTime = startTime
            isActivityActive = true
            startUpdateTimer()
            print("[LiveActivityManager] Started activity: \(activity.id)")
        } catch {
            print("[LiveActivityManager] Failed to start activity: \(error)")
        }
    }

    /// 更新 Live Activity 的 ContentState（每秒调用）
    func updateSedentaryActivity() {
        guard let activity = currentActivity,
              let startTime = sedentaryStartTime else {
            return
        }

        let elapsedSeconds = Int(Date().timeIntervalSince(startTime))
        let updatedState = SedentaryTimerAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            startTime: startTime
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil)
            )
        }
    }

    /// 结束久坐 Live Activity
    func endSedentaryActivity() {
        guard let activity = currentActivity else {
            return
        }

        stopUpdateTimer()

        // 用真实 startTime（不是 now），避免 widget 看到 1 帧 stale "0 秒" 状态
        let startTime = sedentaryStartTime ?? Date()
        let totalSeconds = Int(Date().timeIntervalSince(startTime))
        let finalState = SedentaryTimerAttributes.ContentState(
            elapsedSeconds: totalSeconds,
            startTime: startTime
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }

        currentActivity = nil
        sedentaryStartTime = nil
        isActivityActive = false
        print("[LiveActivityManager] Ended activity (total: \(totalSeconds)s)")
    }

    // MARK: - Private

    private func startUpdateTimer() {
        stopUpdateTimer()
        // 每秒更新一次 elapsedSeconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSedentaryActivity()
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}
