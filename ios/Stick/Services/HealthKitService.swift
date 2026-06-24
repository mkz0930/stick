//
//  HealthKitService.swift
//  抓取 HealthKit 数据 (心率/步数/睡眠/久坐/活动)
//

import Foundation
import HealthKit
import UIKit

/// HealthKit 数据快照 (1 分钟一条)
struct HealthSnapshot: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let heartRate: Double?           // bpm
    /// 今日累计步数 (从 dayStart 到 timestamp 的 sum)
    let cumulativeStepCount: Int?
    /// 相对上一条 snapshot 的新增步数 (= currentCumulative - previousCumulative)
    let incrementalStepCount: Int
    let activeEnergy: Double?         // 千卡
    let bodyState: String             // walk / sit / sleep
    let heartRateVariability: Double? // ms
    let restingHeartRate: Double?     // 静息心率
    let standHours: Int?              // 站立小时
    let exerciseMinutes: Double?      // 锻炼分钟
    let mindfulMinutes: Double?       // 正念分钟
    let respiratoryRate: Double?      // 呼吸频率
    let distance: Double?             // 距离 (米)
    let flightsClimbed: Int?          // 爬楼层
    let sourceName: String?           // 数据来源设备 (iPhone / Apple Watch)

    init(timestamp: Date = Date(),
         heartRate: Double? = nil,
         cumulativeStepCount: Int? = nil,
         incrementalStepCount: Int = 0,
         activeEnergy: Double? = nil,
         bodyState: String = "sit",
         heartRateVariability: Double? = nil,
         restingHeartRate: Double? = nil,
         standHours: Int? = nil,
         exerciseMinutes: Double? = nil,
         mindfulMinutes: Double? = nil,
         respiratoryRate: Double? = nil,
         distance: Double? = nil,
         flightsClimbed: Int? = nil,
         sourceName: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.cumulativeStepCount = cumulativeStepCount
        self.incrementalStepCount = incrementalStepCount
        self.activeEnergy = activeEnergy
        self.bodyState = bodyState
        self.heartRateVariability = heartRateVariability
        self.restingHeartRate = restingHeartRate
        self.standHours = standHours
        self.exerciseMinutes = exerciseMinutes
        self.mindfulMinutes = mindfulMinutes
        self.respiratoryRate = respiratoryRate
        self.distance = distance
        self.flightsClimbed = flightsClimbed
        self.sourceName = sourceName
    }
}

@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    /// Xcode Canvas Preview 用的 no-op 实例：不构造 HKHealthStore（避免 framework import 卡 preview）
    static let noop = HealthKitService(isPreview: true)

    /// 真实例用 .shared；preview 用 .noop（避开 HKHealthStore() 初始化）
    private let isPreview: Bool
    /// HKHealthStore 是 thread-safe reference type，标 `nonisolated` 让 query helper 能脱离 main actor
    /// 解决 ios-dev rule 6: 所有 HKHealthStore calls off main
    private nonisolated let store: HKHealthStore?

    private init(isPreview: Bool = false) {
        self.isPreview = isPreview
        self.store = isPreview ? nil : HKHealthStore()
    }

    // MARK: - HKObjectType 查询 helper
    // HKObjectType 系统常量访问是线程安全的，标 `nonisolated` 让 query helper 能在任意 actor 上调用
    private nonisolated func quantityType(_ id: HKQuantityTypeIdentifier) -> HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: id)
    }

    private nonisolated func categoryType(_ id: HKCategoryTypeIdentifier) -> HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: id)
    }

    private(set) var lastSnapshot: HealthSnapshot?
    private(set) var isAuthorized: Bool = false
    private(set) var error: String?
    /// 最后检测到明显步数的时间（incrementalStepCount > 10），用于立即打断久坐计时
    private(set) var lastMovementTime: Date? = nil
    /// 基于今天真实 HealthKit 步数数据生成的 24h 时刻表
    var realDaySchedule: [StickState.DaySegment]? = nil

    private var timer: Timer?
    /// background / foreground NotificationCenter 订阅持有（避免 ARC 立即释放 + 重复注册）
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// 当前 timer 间隔（resume 时复用）
    private var autoCaptureInterval: TimeInterval = 60

    /// single-flight 锁：保存当前在跑的 sit metrics 更新 Task。
    /// 5 个写入源（Timer 1s / Timer 30s / scenePhase / .task / lastMovementTime onChange）
    /// 同时调 `scheduleSitMetricsUpdate(...)` 时，只允许一个 Task 真正跑 HealthKit 查询，
    /// 其余调用直接返回。锁放在 HealthKitService（actor-isolated），避开 HomeState struct
    /// 重组时 Task 引用丢失导致的死锁。
    private var sitMetricsTask: Task<Void, Never>?

    // 写读的类型
    private let readTypes: Set<HKObjectType> = {
        var s: Set<HKObjectType> = []
        // 基础: 心率/步数/活动能量/HRV
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate)                  { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount)                  { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)        { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)  { s.insert(t) }
        // 苹果手表 / iPhone
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate)         { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .appleStandTime)            { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)         { s.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .mindfulSession)            { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .respiratoryRate)          { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)   { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .flightsClimbed)           { s.insert(t) }
        // 睡眠分析
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)            { s.insert(t) }
        // 步行 mobility (纯 iPhone，iOS 15+) — 仅添加 SDK 支持的类型
        if let t = HKObjectType.quantityType(forIdentifier: .walkingSpeed) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .walkingDoubleSupportPercentage) { s.insert(t) }
        // 听力保护
        if let t = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure) { s.insert(t) }
        return s
    }()

    /// 写入类型（仅 mock 注入时使用）。需要额外请求写权限。
    private nonisolated let writeTypes: Set<HKSampleType> = {
        var s: Set<HKSampleType> = []
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount)                { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)      { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate)               { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)  { s.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)           { s.insert(t) }
        return s
    }()

    // MARK: - 授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            error = "HealthKit 不可用"; return
        }
        do {
            guard let store else { isAuthorized = false; return }
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            self.error = "授权失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 抓取

    /// 抓取一次全天累计数据 → 合成快照（步数/距离/楼层从当日 00:00 起累计）
    func captureSnapshot() async -> HealthSnapshot {
        let now = Date()
        let from = now.addingTimeInterval(-60)
        let dayStart = Calendar.current.startOfDay(for: now)
        async let hr    = recentAverage(.heartRate, from: from, unit: HKUnit.count().unitDivided(by: .minute()))
        // 步数：全天累计（直接从 dayStart 起，避免漏计）
        async let steps = recentSum(.stepCount, from: dayStart, unit: .count())
        async let energy = recentSum(.activeEnergyBurned, from: from, unit: .kilocalorie())
        async let hrv   = recentAverage(.heartRateVariabilitySDNN, from: from, unit: HKUnit.secondUnit(with: .milli))
        // 累计型: 站立小时 / 锻炼分钟 / 正念分钟 — 取今日累计
        async let stand = recentSum(.appleStandTime, from: dayStart, unit: .hour())
        async let exercise = recentSum(.appleExerciseTime, from: dayStart, unit: .minute())
        async let mindful = recentMindfulMinutes(from: dayStart)
        async let resp = recentAverage(.respiratoryRate, from: from, unit: HKUnit.count().unitDivided(by: .minute()))
        // 距离和爬楼也应是全天累计
        async let dist = recentSum(.distanceWalkingRunning, from: dayStart, unit: .meter())
        async let flights = recentSum(.flightsClimbed, from: dayStart, unit: .count())
        // 静息心率: 当日平均
        async let rhr = recentAverage(.restingHeartRate, from: dayStart, unit: HKUnit.count().unitDivided(by: .minute()))

        let bodyState = currentState
        let source = sourceName()
        // 今日累计步数；incremental = currentCumulative - previousCumulative
        // 修复 bug: 旧版每条 snapshot 都存全天累计，sum 后 480x 膨胀。
        // 现在 incremental 是「本分钟相对上分钟的新增步数」；cumulative 是「今日总步数」。
        let currentCumulative = (await steps).map { Int($0) }
        let prevCumulative = self.lastSnapshot?.cumulativeStepCount ?? currentCumulative ?? 0
        let incremental = max(0, (currentCumulative ?? 0) - prevCumulative)
        let snapshot = HealthSnapshot(
            timestamp: now,
            heartRate: await hr,
            cumulativeStepCount: currentCumulative,
            incrementalStepCount: incremental,
            activeEnergy: await energy,
            bodyState: bodyState,
            heartRateVariability: await hrv,
            restingHeartRate: await rhr,
            standHours: (await stand).map { Int($0) },
            exerciseMinutes: await exercise,
            mindfulMinutes: await mindful,
            respiratoryRate: await resp,
            distance: await dist,
            flightsClimbed: (await flights).map { Int($0) },
            sourceName: source
        )
        // 必须切回主线程写入：@Observable 触发视图更新在 SwiftUI 主线程上派发，避免后台线程触发 UI 刷新
        await Task { @MainActor in
            self.lastSnapshot = snapshot
            // 增量步数 > 10 → 打断久坐
            if incremental > 10 {
                self.lastMovementTime = now
            }
        }.value
        return snapshot
    }

    /// 数据来源设备 (iPhone / Apple Watch / 等)
    private func sourceName() -> String? {
        guard let type = quantityType(.heartRate) else { return nil }
        let q = HKSampleQuery(
            sampleType: type,
            predicate: HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-120), end: nil, options: []),
            limit: 1,
            sortDescriptors: nil
        ) { _, samples, _ in
            // not used (synchronous return needed) - just trigger
        }
        store?.execute(q)
        return "HealthKit"
    }

    private nonisolated func recentAverage(_ id: HKQuantityTypeIdentifier, from: Date, unit: HKUnit) async -> Double? {
        guard let type = quantityType(id) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: [])
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stat, _ in
                let val = stat?.averageQuantity()?.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            // 跳出 main actor：把 execute 派发到 global queue 让 callback 跑在 background thread，
            // 满足 ios-dev rule 6 (All HKHealthStore calls off main)
            DispatchQueue.global(qos: .userInitiated).async { [weak store] in
                store?.execute(q)
            }
        }
    }

    private nonisolated func recentSum(_ id: HKQuantityTypeIdentifier, from: Date, unit: HKUnit) async -> Double? {
        guard let type = quantityType(id) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: [])
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stat, _ in
                let val = stat?.sumQuantity()?.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak store] in
                store?.execute(q)
            }
        }
    }

    /// 正念分钟数（HKCategoryType 需要单独处理，不能用 recentSum）
    private nonisolated func recentMindfulMinutes(from: Date) async -> Double? {
        guard let type = categoryType(.mindfulSession) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: [])
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let totalMinutes = (samples as? [HKCategorySample])?.reduce(0.0) { sum, sample in
                    sum + sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                } ?? 0
                cont.resume(returning: totalMinutes)
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak store] in
                store?.execute(q)
            }
        }
    }

    /// 今日睡眠总时长（从 Health App 手动记录的睡眠数据）
    /// 注意：只统计 Asleep 样本（value=2,3,5,6），排除 Awake（value=4）和 InBed（value=0,1）
    func todaySleepHours() async -> Double? {
        guard let sleepType = categoryType(.sleepAnalysis) else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: [])
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let totalSeconds = (samples as? [HKCategorySample])?.reduce(0.0) { sum, sample in
                    // HKCategorySample.value 对于 sleepAnalysis: 0,1=InBed, 2,3,5,6=Asleep, 4=Awake
                    // 只统计 Asleep 状态，排除 Awake 和 InBed
                    switch sample.value {
                    case 2, 3, 5, 6:  // Asleep variants
                        return sum + sample.endDate.timeIntervalSince(sample.startDate)
                    default:
                        return sum  // InBed (0,1) 或 Awake (4) 不计入睡眠时长
                    }
                } ?? 0
                cont.resume(returning: totalSeconds / 3600.0)
            }
            store?.execute(q)
        }
    }

    // MARK: - 推断身体状态 (来自加速度 + 心率)

    /// 当前身体状态 (多信号融合推断)
    var currentState: String {
        let rhr = HealthStore.shared.all
            .compactMap { $0.restingHeartRate }.last
        let result = StateInference.infer(snapshots: HealthStore.shared.today, restingHR: rhr)
        return result.state.rawValue
    }

    /// 当前状态 + 置信度 + 解释 (供 UI 副标展示)
    var currentInference: StateInference.Result {
        let rhr = HealthStore.shared.all
            .compactMap { $0.restingHeartRate }.last
        return StateInference.infer(snapshots: HealthStore.shared.today, restingHR: rhr)
    }

    // MARK: - 时刻表实时刷新（步数变化 + 10 分钟兜底）

    /// 监听步数变化的 HKObserverQuery（步数变化立即触发 `computeDaySchedule()`）
    private var scheduleObserverQuery: HKObserverQuery?
    /// 10 分钟兜底定时器（observer 漏报时仍能刷新）
    private var scheduleFallbackTimer: Timer?
    /// 兜底间隔
    private let scheduleFallbackInterval: TimeInterval = 10 * 60

    /// 启动 schedule 实时刷新：HKObserverQuery 步数变化立即触发 + 10 分钟兜底定时器
    /// 替代 `computeDaySchedule()` 内的 5 分钟节流；节流放宽到 30s 防 race（参见 scheduleRecomputeInterval）。
    /// 必须在 startAutoCapture 内调用（依赖已授权的 `store`）。
    func startScheduleRealtimeRefresh() {
        stopScheduleRealtimeRefresh()  // 防止重复启动

        guard let store else {
            print("[HealthKitService] startScheduleRealtimeRefresh: store 为 nil，跳过")
            return
        }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            print("[HealthKitService] startScheduleRealtimeRefresh: stepCount type 为 nil，跳过")
            return
        }

        // (1) HKObserverQuery 监听步数变化
        let observer = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, _ in
            // observer 回调在后台线程，hop 回 main actor 后再触发 computeDaySchedule
            Task { @MainActor in
                await self?.computeDaySchedule()
                // completion 必须调，否则系统会 throttle observer 后续触发
                completion()
            }
        }
        store.execute(observer)
        scheduleObserverQuery = observer

        // (2) 10 分钟兜底定时器
        scheduleFallbackTimer = Timer.scheduledTimer(withTimeInterval: scheduleFallbackInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.computeDaySchedule()
            }
        }

        print("[HealthKitService] ✅ schedule 实时刷新已启动（observer + \(Int(scheduleFallbackInterval / 60))min 兜底）")

        // (3) 请求后台通知：observer 在后台需要 delivery 才能触发（iOS 13+）
        //    失败也无所谓（前台场景不需要）
        Task {
            do {
                try await store.enableBackgroundDelivery(for: stepType, frequency: .immediate)
            } catch {
                print("[HealthKitService] enableBackgroundDelivery 失败（可忽略）: \(error.localizedDescription)")
            }
        }
    }

    /// 停止 schedule 实时刷新（observer + 兜底定时器）
    func stopScheduleRealtimeRefresh() {
        if let q = scheduleObserverQuery {
            store?.stop(q)
            scheduleObserverQuery = nil
        }
        scheduleFallbackTimer?.invalidate()
        scheduleFallbackTimer = nil
    }

    // MARK: - 定时抓取 (1 分钟一次)

    /// DEBUG 模式：追踪是否已自动注入过 mock 数据（避免每次启动重复注入）
    private static var hasInjectedMockDataInThisCycle = false

    func startAutoCapture(interval: TimeInterval = 60) {
        // 用户未授权时跳过 auto capture — HK 查询返回空集会让 UI 显示全 0 数据
        // （requestAuthorization() 拒绝后会设 isAuthorized = false）
        guard isAuthorized else {
            print("[HealthKitService] 未授权，跳过 auto capture")
            return
        }

        stopAutoCapture()
        autoCaptureInterval = interval

        // 启动 schedule 实时刷新（HKObserverQuery 步数变化 + 10 分钟兜底定时器）
        // startScheduleRealtimeRefresh 内部在 main actor 上下文里启动 observer + Timer
        startScheduleRealtimeRefresh()

        // 模拟器无有效步数时，生成 mock 快照（模拟用户45分钟前走路，现在坐着）。
        // 不能只判断 today.isEmpty：上次启动可能已持久化 0 步快照，导致 mock 永远不再注入。
        #if targetEnvironment(simulator)
        let hasRecentSignificantMovement = HealthStore.shared.today.contains {
            $0.timestamp >= Date().addingTimeInterval(-4 * 3600) && $0.incrementalStepCount > 10
        }
        if !hasRecentSignificantMovement {
            let mockWalkTime = Date().addingTimeInterval(-45 * 60)
            let mockSnapshot = HealthSnapshot(
                timestamp: mockWalkTime,
                heartRate: 72,
                cumulativeStepCount: 1000,
                incrementalStepCount: 50,
                activeEnergy: 50,
                bodyState: "walk",
                heartRateVariability: 30,
                restingHeartRate: 65,
                standHours: nil,
                exerciseMinutes: 5,
                mindfulMinutes: nil,
                respiratoryRate: 16,
                distance: 800,
                flightsClimbed: 2,
                sourceName: "Mock Simulator"
            )
            HealthStore.shared.append(mockSnapshot)
            lastSnapshot = mockSnapshot
        }

        // DEBUG 模拟器：首次启动时自动注入 7 天历史数据到 HealthKit（让"导出最近7天"能看到多天数据）。
        // 通过静态标记避免每次启动重复注入；重启 app 或重装后标记重置，会重新注入。
        #if DEBUG
        if !Self.hasInjectedMockDataInThisCycle {
            Self.hasInjectedMockDataInThisCycle = true
            Task {
                let count = await injectMockDataIntoHealthKit(days: 7)
                print("[HealthKitService] 🧪 DEBUG 模拟器自动注入 7 天 mock 数据: \(count) 条")
            }
        }
        #endif
        #endif

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                let snap = await self.captureSnapshot()
                await MainActor.run { HealthStore.shared.append(snap) }
            }
        }
        // 立即抓一次
        Task {
            let snap = await captureSnapshot()
            await MainActor.run { HealthStore.shared.append(snap) }
        }

        // 监听 app 前后台：切到 background 时暂停 timer（RunLoop 即便降频也仍在 fire，浪费电），
        // 回 foreground 时按原 interval 恢复。多次 start 会被 stopAutoCapture 先清掉 observer，不会重复注册。
        registerLifecycleObserversIfNeeded()
    }

    func stopAutoCapture() {
        // 停止 schedule 实时刷新（observer + 10 分钟兜底定时器）
        stopScheduleRealtimeRefresh()

        timer?.invalidate()
        timer = nil

        // 清理 lifecycle observer（避免内存泄漏 + 下次 start 重复注册）
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
    }

    // MARK: - 后台暂停（节电）

    /// 注册一次性的 background / foreground observer。幂等：多次调用不会重复注册。
    private func registerLifecycleObserversIfNeeded() {
        guard lifecycleObservers.isEmpty else { return }

        let bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseAutoCapture()
            }
        }
        let fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeAutoCapture()
            }
        }
        lifecycleObservers = [bgObserver, fgObserver]
    }

    /// 暂停 auto capture timer（保留 isAuthorized + store + interval；foreground 时 resume 复用）
    func pauseAutoCapture() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        // schedule 实时刷新也一并暂停（10 分钟兜底 timer 在后台 fire 同样浪费电）
        scheduleFallbackTimer?.invalidate()
        scheduleFallbackTimer = nil
        print("[HealthKitService] ⏸️ auto capture 已暂停（app 进入后台）")
    }

    /// 恢复 auto capture timer（仅在已启动过 + 未授权未失效时有效）
    func resumeAutoCapture() {
        guard isAuthorized, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: autoCaptureInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                let snap = await self.captureSnapshot()
                await MainActor.run { HealthStore.shared.append(snap) }
            }
        }
        // schedule 实时刷新也需要重新挂回 observer + 兜底 timer（pause 时一起 stop 了）
        startScheduleRealtimeRefresh()
        print("[HealthKitService] ▶️ auto capture 已恢复（interval=\(Int(autoCaptureInterval))s）")
    }

    // MARK: - Today Convenience Methods

    func todaySteps() async -> Int? {
        let dayStart = Calendar.current.startOfDay(for: Date())
        guard let val: Double = await recentSum(.stepCount, from: dayStart, unit: .count()) else { return nil }
        return Int(val)
    }

    func todayEnergy() async -> Double? {
        await recentSum(.activeEnergyBurned, from: Calendar.current.startOfDay(for: Date()), unit: .kilocalorie())
    }

    func todayFlights() async -> Int? {
        guard let val: Double = await recentSum(.flightsClimbed, from: Calendar.current.startOfDay(for: Date()), unit: .count()) else { return nil }
        return Int(val)
    }

    func todayDistance() async -> Double? {
        await recentSum(.distanceWalkingRunning, from: Calendar.current.startOfDay(for: Date()), unit: .meter())
    }

    func todayHeartRate() async -> Int? {
        guard let type = quantityType(.heartRate) else { return nil }
        return await withCheckedContinuation { cont in
            let from = Calendar.current.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                let val = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                cont.resume(returning: Int(val))
            }
            store?.execute(q)
        }
    }

    // MARK: - Mobility Today Convenience Methods

    /// 步速 (m/s)
    func todayWalkingSpeed() async -> Double? {
        await recentAverage(.walkingSpeed, from: Calendar.current.startOfDay(for: Date()), unit: HKUnit.meter().unitDivided(by: .second()))
    }

    /// 双脚支撑时间比例 (%)
    func todayWalkingDoubleSupport() async -> Double? {
        guard let val: Double = await recentAverage(.walkingDoubleSupportPercentage, from: Calendar.current.startOfDay(for: Date()), unit: .percent()) else { return nil }
        return val * 100
    }

    /// 耳机音量暴露 (dB)
    func todayHeadphoneExposure() async -> Double? {
        await recentAverage(.headphoneAudioExposure, from: Calendar.current.startOfDay(for: Date()), unit: HKUnit.decibelAWeightedSoundPressureLevel())
    }

    // MARK: - Sedentary Minutes

    /// 从 HealthKit 直接读取今日久坐分钟数
    /// **改进版**：排除 0-6 点睡眠时段 + 排除 >4h 无数据长间隔
    /// - 0-6 AM：默认是睡眠时间，不算久坐
    /// - 连续 >4h 没有任何步数：可能睡眠/没带手机，整段跳过不算久坐
    /// 推测今早真正起床时间
    /// 逻辑：从 04:00 开始扫描步数，过滤凌晨翻身误报后第一条 >阈值步数的时间 = 真正起床
    /// - 04:00-06:00：>100 步才算（避免凌晨翻身的 25 步被误判为起床）
    /// - 06:00 之后：>50 步即起床
    /// - 夜间起夜（<50步）不算起床
    func queryWakeUpTime() async -> Date? {
        guard let stepType = quantityType(.stepCount) else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let searchStart = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: startOfDay) else { return nil }
        let now = Date()
        guard now > searchStart else { return nil }

        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: now, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: stepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    cont.resume(returning: nil)
                    return
                }
                // 凌晨误报保护：04:00-06:00 之间的低步数样本视为翻身/起夜，跳过
                for sample in samples {
                    let hour = calendar.component(.hour, from: sample.startDate)
                    let steps = Int(sample.quantity.doubleValue(for: .count()))
                    if hour < 6 {
                        // 凌晨时段：需要 >100 步才算"真实起床"
                        if steps > 100 {
                            cont.resume(returning: sample.startDate)
                            return
                        }
                    } else {
                        // 6 点之后：>50 步即起床
                        if steps > 50 {
                            cont.resume(returning: sample.startDate)
                            return
                        }
                    }
                }
                cont.resume(returning: nil)
            }
            store?.execute(q)
        }
    }

    /// 在 12:00-14:00 午休窗口内，通过步数聚类推断午休时间
    /// 如果两个步行活动之间有 ≥30min 的连续无步数间隔 → 那段间隔是午休，不计久坐
    private func detectLunchNap() async -> ClosedRange<Date>? {
        guard let stepType = quantityType(.stepCount) else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: startOfDay),
              let windowEnd = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: startOfDay) else { return nil }
        let now = Date()
        let effectiveEnd = min(windowEnd, now)
        guard effectiveEnd > windowStart else { return nil }

        return await withCheckedContinuation { cont in
            var interval = DateComponents()
            interval.minute = 1

            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, _ in
                guard let results else { cont.resume(returning: nil); return }

                // 1) 收集窗口内每分钟步数
                var buckets: [(Date, Double)] = []
                results.enumerateStatistics(from: windowStart, to: effectiveEnd) { stat, _ in
                    let s = stat.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    buckets.append((stat.startDate, s))
                }
                buckets.sort { $0.0 < $1.0 }

                // 2) 聚类步行时段：连续有步数的分钟归为一组，间隔 >10min 算不同组
                var clusters: [(Date, Date)] = [] // (start, end) of each walking cluster
                var cStart: Date? = nil
                var cLast: Date? = nil
                for (ts, steps) in buckets {
                    if steps > 0 {
                        if cStart == nil { cStart = ts }
                        cLast = ts
                    } else {
                        // 连续无步数 >10min → 当前步行组结束
                        if let last = cLast, ts.timeIntervalSince(last) > 10 * 60 {
                            if let start = cStart { clusters.append((start, last)) }
                            cStart = nil; cLast = nil
                        }
                    }
                }
                if let start = cStart, let last = cLast { clusters.append((start, last)) }

                // 3) 如果 ≥2 组步行活动，找它们之间的间隙
                guard clusters.count >= 2 else { cont.resume(returning: nil); return }
                let sorted = clusters.sorted { $0.0 < $1.0 }
                for i in 1..<sorted.count {
                    let gapStart = sorted[i-1].1  // 上一组步行的结束
                    let gapEnd = sorted[i].0      // 下一组步行的开始
                    let gapMin = gapEnd.timeIntervalSince(gapStart) / 60
                    if gapMin >= 30 && gapMin <= 120 {
                        cont.resume(returning: gapStart...gapEnd)
                        return
                    }
                }
                cont.resume(returning: nil)
            }
            store?.execute(query)
        }
    }

    /// 通过耳机音量暴露检测夜间清醒时段（WASO — Wake After Sleep Onset）
    /// 在 22:00-06:00 窗口内扫描耳机音频记录：
    /// 有记录 = 实际清醒（戴耳机听东西），即便步数为零也不算睡眠。
    /// 返回分钟级闭合区间数组，每段代表一段清醒期。
    func detectNightWakePeriods() async -> [ClosedRange<Int>] {
        guard let audioType = quantityType(.headphoneAudioExposure) else { return [] }
        let calendar = Calendar.current
        let now = Date()

        // 搜索窗口：昨晚 22:00 → 今早 06:00（或现在，如果现在 < 06:00）
        let todayStart = calendar.startOfDay(for: now)
        let windowEnd: Date
        let h = calendar.component(.hour, from: now)
        if h < 6 {
            windowEnd = now
        } else {
            guard let w = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: todayStart) else { return [] }
            windowEnd = w
        }
        guard let nightStart = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: todayStart.addingTimeInterval(-86400)) else { return [] }
        guard windowEnd > nightStart else { return [] }

        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: nightStart, end: windowEnd, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: audioType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples, !samples.isEmpty else {
                    cont.resume(returning: [])
                    return
                }
                // 聚类：间隔 >10min 算不同清醒段
                // ⚠️ 连续性判断必须用 Date.timeIntervalSince 算真实秒数差，
                //    不能用 minutesOfDay 差：跨午夜的样本（如 23:55 → 00:01）会出现
                //    minutesOfDay 差 = -1434 被误判为 ≤10 连续，闭合时
                //    cStart=1435 > cLast=1 触发 'Range requires lowerBound <= upperBound'
                //    断言崩溃。
                var ranges: [ClosedRange<Int>] = []
                var cStart: Int? = nil
                var cLast: Int? = nil
                var lastDate: Date? = nil
                for s in samples {
                    let m = StickState.minutesOfDay(s.startDate)
                    if cStart == nil {
                        cStart = m; cLast = m
                        lastDate = s.startDate
                    } else if let last = lastDate,
                              s.startDate.timeIntervalSince(last) / 60.0 <= 10 {
                        cLast = m
                        lastDate = s.startDate
                    } else {
                        if let s = cStart, let l = cLast {
                            // 跨午夜 cluster（如 23:55 醒来 → 00:01 又睡）：
                            // minutesOfDay 会让 s=1435, l=1，s>l 不能直接构 Range。
                            // 拆成两段以保持语义完整。
                            if s <= l {
                                ranges.append(s...l)
                            } else {
                                ranges.append(s...1439)
                                ranges.append(0...l)
                            }
                        }
                        cStart = m; cLast = m
                        lastDate = s.startDate
                    }
                }
                if let s = cStart, let l = cLast {
                    if s <= l {
                        ranges.append(s...l)
                    } else {
                        ranges.append(s...1439)
                        ranges.append(0...l)
                    }
                }
                cont.resume(returning: ranges)
            }
            store?.execute(q)
        }
    }

    // MARK: - 步态质量摘要

    /// 步态质量数据（用于活动状态分析）
    struct WalkingQuality {
        let avgSpeed: Double?        // m/s
        let maxSpeed: Double?        // m/s
        let minSpeed: Double?        // m/s
        let avgDoubleSupport: Double? // %
        let avgHeadphoneExposure: Double? // dB
        let nightWakeCount: Int      // 夜间清醒段数
        let nightWakeTotalMin: Int   // 夜间清醒总分钟数

        /// 步态健康评分（0-100）
        var gaitScore: Int {
            var score = 80  // 基准分
            if let sp = avgSpeed {
                if sp >= 1.0 && sp <= 1.4 { score += 10 }  // 健康区间
                else if sp >= 0.8 && sp <= 1.6 { score += 5 }
                else { score -= 10 }
            }
            if let ds = avgDoubleSupport {
                if ds >= 25 && ds <= 33 { score += 10 }  // 健康区间
                else if ds >= 22 && ds <= 36 { score += 5 }
                else { score -= 5 }
            }
            if nightWakeCount > 0 { score -= nightWakeCount * 3 }  // 每段夜间清醒扣分
            return max(0, min(100, score))
        }

        /// 睡眠质量评估（基于夜间清醒）
        var sleepQualityLabel: String {
            if nightWakeCount == 0 { return "连续" }
            if nightWakeCount == 1 { return "轻度中断" }
            if nightWakeCount == 2 { return "中断" }
            return "碎片化"
        }
    }

    /// 综合步态质量分析（今天）
    func todayWalkingQuality() async -> WalkingQuality {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())

        // 并行查询步速、双脚支撑、耳机暴露、夜间清醒
        async let speeds = fetchSamples(.walkingSpeed, from: dayStart, unit: HKUnit.meter().unitDivided(by: .second()))
        async let doubleSupport = recentAverage(.walkingDoubleSupportPercentage, from: dayStart, unit: .percent())
        async let headphone = recentAverage(.headphoneAudioExposure, from: dayStart, unit: HKUnit.decibelAWeightedSoundPressureLevel())
        async let wakePeriods = detectNightWakePeriods()

        let speedVals = (await speeds).compactMap { $0 }
        let nightWakeCount = (await wakePeriods).count
        let nightWakeTotalMin = (await wakePeriods).reduce(0) { $0 + ($1.upperBound - $1.lowerBound + 1) }

        return WalkingQuality(
            avgSpeed: speedVals.isEmpty ? nil : speedVals.reduce(0, +) / Double(speedVals.count),
            maxSpeed: speedVals.max(),
            minSpeed: speedVals.min(),
            avgDoubleSupport: (await doubleSupport).map { $0 * 100 },
            avgHeadphoneExposure: await headphone,
            nightWakeCount: nightWakeCount,
            nightWakeTotalMin: nightWakeTotalMin
        )
    }

    /// 辅助：查询某类型近 N 个样本的值列表
    private func fetchSamples(_ id: HKQuantityTypeIdentifier, from: Date, limit: Int = 100, unit: HKUnit) async -> [Double] {
        guard let type = quantityType(id) else { return [] }
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                let vals = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: unit) } ?? []
                cont.resume(returning: vals)
            }
            store?.execute(q)
        }
    }

    func todaySedentaryMinutes() async -> Int {
        guard let stepType = quantityType(.stepCount) else { return 0 }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let now = Date()

        // 快速检查：今天是否有任何步数样本（模拟器无 HealthKit 数据时避免全算久坐）
        let hasStepData = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: stepType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples?.isEmpty == false)
            }
            store?.execute(q)
        }
        guard hasStepData else { return 0 }

        // 推测起床时间：起床前全部算睡眠，不计久坐
        let wakeUpTime = await queryWakeUpTime()
        // 检测午休：12:00-14:00 内步行之间的长间隙不计久坐
        let lunchNap = await detectLunchNap()
        // 夜间清醒：耳机音量暴露 → 不算久坐
        let nightWake = await detectNightWakePeriods()

        return await withCheckedContinuation { cont in
            var interval = DateComponents()
            interval.minute = 1

            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, _ in
                guard let results = results else {
                    cont.resume(returning: 0)
                    return
                }
                var sedentaryCount = 0
                var lastActiveTime: Date? = nil
                let maxGapSeconds: TimeInterval = 4 * 3600

                // Pass 1: 收集所有分钟 bucket
                var buckets: [(Date, Double)] = []
                results.enumerateStatistics(from: startOfDay, to: now) { stat, _ in
                    let s = stat.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    buckets.append((stat.startDate, s))
                }
                buckets.sort { $0.0 < $1.0 }

                // Pass 2: 根据步数反推步行时间，往前标记活动分钟
                // 每条步数样本代表之前 ~步数/100 分钟的步行
                var activeMinutes = Set<Date>()
                for (ts, steps) in buckets {
                    guard steps > 0 else { continue }
                    let walkMinutes = max(1, min(30, Int(steps / 80.0) + 1))
                    for i in 0..<walkMinutes {
                        let t = ts.addingTimeInterval(-Double(i) * 60)
                        if t >= startOfDay && t <= now { activeMinutes.insert(t) }
                    }
                }

                // Pass 3: 统计久坐（非步行、非睡眠、非午休、非夜间清醒的分钟）
                for (ts, _) in buckets {
                    let m = StickState.minutesOfDay(ts)
                    // 夜间清醒：耳机暴露代表真实清醒，不算久坐
                    if nightWake.contains(where: { $0.contains(m) }) { continue }
                    if let wakeUp = wakeUpTime, ts < wakeUp { continue }
                    if let nap = lunchNap, ts >= nap.lowerBound && ts < nap.upperBound { continue }
                    if activeMinutes.contains(ts) {
                        lastActiveTime = ts
                        continue
                    }
                    if let last = lastActiveTime, ts.timeIntervalSince(last) > maxGapSeconds { continue }
                    sedentaryCount += 1
                }
                cont.resume(returning: sedentaryCount)
            }
            store?.execute(query)
        }
    }

    // MARK: - 真实时刻表

    /// 基于今天真实 HealthKit 步数数据生成的 24h 时刻表
    /// 算法与 `todaySedentaryMinutes()` 一致：/80 divisor 反推步行时间 + 4h 无活动长间隔判睡眠。
    /// 唯一差异：本方法对全部 1440 分钟分类，而非只统计久坐分钟数。
    /// 节流：30s 防 race。调度由 `startScheduleRealtimeRefresh` 接管：HKObserverQuery 步数变化
    /// 立即触发 + 10 分钟兜底定时器；这里只防 observer 在 1 秒内多次触发导致 HK 查询风暴。
    private var lastScheduleComputeAt: Date = .distantPast
    private let scheduleRecomputeInterval: TimeInterval = 30

    func computeDaySchedule() async {
        // 节流：30s 内已有结果则跳过（首次或跨日会重算）
        let now = Date()
        if realDaySchedule != nil,
           now.timeIntervalSince(lastScheduleComputeAt) < scheduleRecomputeInterval {
            return
        }
        lastScheduleComputeAt = now

        guard let stepType = quantityType(.stepCount) else { return }
        let startOfDay = Calendar.current.startOfDay(for: now)

        // 快速检查：今天是否有任何步数样本（模拟器无 HealthKit 数据时避免全算久坐）
        let hasStepData = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: stepType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples?.isEmpty == false)
            }
            store?.execute(q)
        }
        guard hasStepData else { return }

        // 推测起床时间 + 午休窗口 + 夜间清醒期
        let wakeUp = await queryWakeUpTime()
        let nap = await detectLunchNap()
        let nightWakePeriods = await detectNightWakePeriods()

        let wakeUpMinute = wakeUp.map { StickState.minutesOfDay($0) }
        let napStart = nap.map { StickState.minutesOfDay($0.lowerBound) }
        let napEnd = nap.map { StickState.minutesOfDay($0.upperBound) }
        let nowMinute = StickState.minutesOfDay(now)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var interval = DateComponents()
            interval.minute = 1

            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, _ in
                guard let results = results else {
                    cont.resume(returning: ())
                    return
                }

                // Pass 1: 收集所有分钟 bucket
                var buckets: [(Date, Double)] = []
                results.enumerateStatistics(from: startOfDay, to: now) { stat, _ in
                    let s = stat.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    buckets.append((stat.startDate, s))
                }
                buckets.sort { $0.0 < $1.0 }

                // Pass 2: 根据步数反推步行时间（/80 divisor，与 todaySedentaryMinutes 算法一致）
                var activeMinutes = Set<Int>()
                for (ts, steps) in buckets {
                    guard steps > 0 else { continue }
                    let walkMinutes = max(1, min(30, Int(steps / 80.0) + 1))
                    for i in 0..<walkMinutes {
                        let t = ts.addingTimeInterval(-Double(i) * 60)
                        if t >= startOfDay && t <= now {
                            activeMinutes.insert(StickState.minutesOfDay(t))
                        }
                    }
                }

                // Pass 3: 分类全部 1440 分钟
                var states = [StickState](repeating: .sit, count: 1440)
                var lastActiveMinute: Int? = nil
                let maxGapMinutes = 4 * 60

                // 辅助：检查某分钟是否属于夜间清醒期
                func isNightWake(_ m: Int) -> Bool {
                    nightWakePeriods.contains { $0.contains(m) }
                }

                for minute in 0..<1440 {
                    // 0) 夜间清醒（耳机音量暴露）→ 实际清醒，不算睡眠/久坐
                    if isNightWake(minute) {
                        states[minute] = .sleep   // 视觉上保持睡眠分段，避免时间线碎片化
                        continue                    // 不更新 lastActiveMinute，不被 >4h 规则覆盖
                    }

                    // 1) 起床前 → 睡眠
                    if let wu = wakeUpMinute, minute < wu {
                        states[minute] = .sleep
                        continue
                    }

                    // 2) 午休范围 → 睡眠
                    if let ns = napStart, let ne = napEnd, minute >= ns && minute < ne {
                        states[minute] = .sleep
                        continue
                    }

                    // 3) 步行活动分钟
                    if activeMinutes.contains(minute) {
                        states[minute] = .walk
                        lastActiveMinute = minute
                        continue
                    }

                    // 4) 未来分钟：按时间段启发式分类（22:00-07:00 睡眠，其余坐）
                    if minute > nowMinute {
                        let h = minute / 60
                        states[minute] = (h >= 22 || h < 7) ? .sleep : .sit
                        continue
                    }

                    // 5) 夜间（22:00-07:00）→ 睡眠（独立于 gap 检测，覆盖午夜跨点的错误计算）
                    let h = minute / 60
                    if h >= 22 || h < 7 {
                        states[minute] = .sleep
                        continue
                    }

                    // 6) 距上次活动 > 4h → 睡眠/离开（夜间清醒已被 step 0 提前排除，不会误判）
                    if let last = lastActiveMinute, minute - last > maxGapMinutes {
                        states[minute] = .sleep
                        continue
                    }

                    // 7) 默认久坐
                    states[minute] = .sit
                }

                // Pass 4: 按分钟索引建立步数查找表（便于按时间段汇总）
                var stepLookup: [Int: Double] = [:]
                for (ts, steps) in buckets {
                    let m = StickState.minutesOfDay(ts)
                    stepLookup[m] = steps
                }

                // Pass 5: 合并连续相同状态为 DaySegment 数组，walk 段计算总步数
                var segments: [StickState.DaySegment] = []
                var i = 0
                while i < 1440 {
                    let s = states[i]
                    var j = i + 1
                    while j < 1440 && states[j] == s { j += 1 }

                    // 步行段统计该时段总步数
                    var segmentSteps: Int? = nil
                    if s == .walk {
                        let total = (i..<j).reduce(0) { $0 + (stepLookup[$1] ?? 0) }
                        segmentSteps = Int(total)
                    }

                    segments.append(StickState.DaySegment(
                        state: s,
                        startMinute: i,
                        endMinute: j,
                        stepCount: segmentSteps
                    ))
                    i = j
                }

                // 切回主线程写入：@Observable 追踪变更后驱动视图更新（只在内容真变化时才写，避免触发不必要的视图重渲染）
                Task { @MainActor in
                    guard self.realDaySchedule != segments else { return }
                    self.realDaySchedule = segments
                }
                cont.resume(returning: ())
            }
            store?.execute(query)
        }
    }

    // MARK: - 当前久坐时长（最近一次步数时间到现在）

    /// 找到最近一次有效步数 (>10步) 的时间戳
    /// **改进版**：排除 0-6 AM 睡眠时段 + 排除 >4h 无数据长间隔
    /// - 夜间（0-6点）心率偏低+步数极少 → 睡眠，跳过
    /// - 心率高于静息 20bpm → 活动，跳过
    /// - **距上次活动 >4h → 整段跳过**（可能睡眠/没带手机，不算久坐）
    func lastSignificantMovementTime(hours: Double = 4) -> Date? {
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        let snapshots = HealthStore.shared.today.filter { $0.timestamp >= cutoff }
        guard !snapshots.isEmpty else { return nil }

        let sorted = snapshots.sorted { $0.timestamp > $1.timestamp }   // 时间倒序
        let calendar = Calendar.current
        let restingHR = sorted.compactMap { $0.restingHeartRate }.last
        let recentHRValues = Array(sorted.prefix(10)).compactMap { $0.heartRate }
        let recentHRAvg: Double? = recentHRValues.isEmpty
            ? nil : Double(recentHRValues.reduce(0, +)) / Double(max(1, recentHRValues.count))

        let walkThreshold = 10
        let activeHRDelta: Double = 20
        let maxGapSeconds: TimeInterval = 4 * 3600
        var lastActiveTime: Date? = nil   // 上一条"考察过"的快照时间

        for snap in sorted {
            let steps = snap.incrementalStepCount
            let hr = snap.heartRate
            let snapHour = calendar.component(.hour, from: snap.timestamp)

            // 夜间睡眠跳过
            let isNight = snapHour >= 0 && snapHour < 6
            let isLowHR = hr.map { r in
                if let resting = restingHR {
                    return Double(r) < resting - 5
                } else if let avg = recentHRAvg {
                    return Double(r) < avg - 10
                }
                return false
            } ?? false
            if isNight && isLowHR && steps < 5 {
                lastActiveTime = snap.timestamp
                continue
            }

            // 心率活动
            let isActiveHR = hr.map { r in
                if let resting = restingHR {
                    return Double(r) > resting + activeHRDelta
                } else if let avg = recentHRAvg {
                    return Double(r) > avg + 15
                }
                return false
            } ?? false

            // 有效步数或心率活动
            if steps > walkThreshold || isActiveHR {
                // 距上一条活动/睡眠标记 >4h → 可能睡眠/没带手机，跳过
                if let last = lastActiveTime, last.timeIntervalSince(snap.timestamp) > maxGapSeconds {
                    lastActiveTime = snap.timestamp
                    continue
                }
                return snap.timestamp
            }
            lastActiveTime = snap.timestamp
        }
        return nil
    }

    /// 从 HealthKit 直接查询最近一次有效步数（>10步）的时间
    /// 解决 app 快照覆盖不到历史时间段的问题
    private func queryLatestStepTime(hours: Double = 4) async -> Date? {
        guard let stepType = quantityType(.stepCount) else { return nil }
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: nil, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: stepType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                let steps = sample.quantity.doubleValue(for: .count())
                guard steps > 10 else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: sample.endDate)
            }
            store?.execute(q)
        }
    }

    /// 当前连续久坐分钟数 = now - 最近一次有效步数时间
    /// **数据来源融合**：
    /// 1. 先扫描 app 本地快照（`HealthStore.shared.today`），找最近有明显步数的时间
    /// 2. 再从 HealthKit 直接查最近一次 >10 步的原始样本
    /// 3. 取两个来源中**更晚**的那个（更精确地反映"最后一次活动"）
    /// 4. 若最后活动时间在起床前 → 从起床时间开始算久坐
    /// 5. 若最后活动在午休前 → 从午休结束开始算久坐
    func currentSedentarySessionMinutes(hours: Double = 4) async -> Int {
        let wakeUp = await queryWakeUpTime()
        let lunchNap = await detectLunchNap()
        let lastFromSnapshots = lastSignificantMovementTime(hours: hours)
        let lastFromHK = await queryLatestStepTime(hours: hours)
        // 取两个来源中更晚的（更接近真实"最后活动时间"）
        let lastMove: Date?
        switch (lastFromSnapshots, lastFromHK) {
        case let (a?, b?): lastMove = a > b ? a : b
        case let (a?, nil): lastMove = a
        case let (nil, b?): lastMove = b
        case (nil, nil):    lastMove = nil
        }
        // 最后活动在起床前 → 从起床时间开始算（夜间起夜不算活动）
        if let lastMove, let wakeUp, lastMove < wakeUp {
            return max(0, Int(Date().timeIntervalSince(wakeUp) / 60))
        }
        // 最后活动在午休结束前 → 从午休结束开始算（午睡不算久坐）
        if let lastMove, let nap = lunchNap, lastMove < nap.upperBound {
            return max(0, Int(Date().timeIntervalSince(nap.upperBound) / 60))
        }
        guard let lastMove else { return 0 }
        return max(0, Int(Date().timeIntervalSince(lastMove) / 60))
    }

    /// single-flight 入口：5 个写入源（Timer 1s / Timer 30s / scenePhase 恢复 / .task 启动 /
    /// lastMovementTime 重置）全部走这里。已有 Task 在跑就复用，不 fork 新 HealthKit 查询。
    /// **锁放在 service（actor-isolated）**：旧实现把 Task 引用塞进 HomeState struct 字段，
    /// view 重组时新 struct 实例看不到旧 Task，defer 里写回的 nil 不反映到新 state → 永远认为
    /// 有 Task 在跑 → 后续 single-flight 全部死锁。
    /// - Parameter onUpdate: 拿到 `newMinutes` 和 `startTime` 后写回 UI state（nil = 归零）
    /// - Parameter onWidgetWrite: 写 SharedStateStore 给 widget（仅在 sit + 有 session 时）
    /// 返回 true 表示本次新建并派发了任务，false 表示已有任务在跑、复用。
    @discardableResult
    func scheduleSitMetricsUpdate(
        onUpdate: @MainActor @Sendable @escaping (_ newMinutes: Int, _ startTime: Date?) -> Void,
        onWidgetWrite: @MainActor @Sendable @escaping (_ newMinutes: Int, _ startTime: Date) -> Void
    ) -> Bool {
        if let existing = sitMetricsTask, !existing.isCancelled {
            return false  // 已有 Task 在跑，复用，不 fork 新的
        }
        sitMetricsTask = Task { @MainActor in
            defer { sitMetricsTask = nil }
            if Task.isCancelled { return }
            // 抓 HealthKit 当前 session 久坐（小时窗覆盖午餐后等长坐场景）
            let newMinutes = await currentSedentarySessionMinutes(hours: 4)
            if Task.isCancelled { return }
            // 同步 startTime：newMinutes=0 归零，否则从当前时刻往前推
            let startTime: Date? = newMinutes == 0
                ? nil
                : Date().addingTimeInterval(-Double(newMinutes) * 60)
            onUpdate(newMinutes, startTime)
            if Task.isCancelled { return }
            // 同步到 Widget（仅在 sit + 有 session 时写，避免 sleep/stand 反复写）
            if let startTime {
                onWidgetWrite(newMinutes, startTime)
            }
        }
        return true
    }

    /// 取消 in-flight 的 sit metrics Task（lastMovementTime 重置路径用）。
    /// 避免已 sleep 完的 stale Task 在 cancel 后覆盖刚 reset 的秒表。
    func cancelSitMetricsTask() {
        sitMetricsTask?.cancel()
        sitMetricsTask = nil
    }

    // MARK: - 起床时间推测

    /// 根据夜间步数活动推测起床时间
    /// 逻辑：
    /// - 扫描昨天 22:00 到今天 10:00 的快照
    /// - 夜间短时步数（<5分钟）是上厕所，不算起床
    /// - 早上第一段持续 >5分钟 的步数活动 = 真正起床
    /// - 返回 HH:mm 格式字符串
    func guessWakeUpTime() -> String? {
        let calendar = Calendar.current
        let now = Date()

        // 昨天 22:00
        let yesterday = calendar.startOfDay(for: now)
        guard let yesterdayPrev = calendar.date(byAdding: .day, value: -1, to: yesterday),
              let nightStart = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: yesterdayPrev) else {
            return nil
        }

        // 今天 10:00
        let today = calendar.startOfDay(for: now)
        guard let morningEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today) else {
            return nil
        }

        let snapshots = HealthStore.shared.today.filter {
            $0.timestamp >= nightStart && $0.timestamp <= morningEnd
        }.sorted { $0.timestamp < $1.timestamp }

        guard !snapshots.isEmpty else { return nil }

        // 找第一段持续 >5分钟 且 单分钟 >10步 的活动
        var i = 0
        while i < snapshots.count {
            let snap = snapshots[i]
            if snap.incrementalStepCount > 10 {
                // 找到一段步数活动的起点，往后看持续了多久
                var duration = snap.incrementalStepCount > 0 ? 1 : 0
                var j = i + 1
                while j < snapshots.count {
                    let next = snapshots[j]
                    // 同一小时内算持续（宽松判断：只要不是完全没步数）
                    if next.incrementalStepCount > 5 {
                        duration += 1
                        j += 1
                    } else {
                        break
                    }
                }
                // 持续超过 5 分钟，且在 05:00-10:00 之间 → 起床时间
                if duration >= 5 {
                    let hour = calendar.component(.hour, from: snap.timestamp)
                    if hour >= 5 && hour <= 10 {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
                        return formatter.string(from: snap.timestamp)
                    }
                }
                i = j
            } else {
                i += 1
            }
        }
        return nil
    }

    // MARK: - 数据导出

    /// 导出最近 N 天的 HealthKit 数据（JSON 格式，北京时间）。`days = 1` 等同于今日。
    func exportRecentData(days: Int) async -> URL? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        // N 天前 0 点（days=1 → 今日 0 点）
        let fromDate = Calendar.current.date(byAdding: .day, value: -(days - 1), to: dayStart) ?? dayStart
        return await exportHealthRange(from: fromDate, to: now, fileSuffix: days == 1 ? nil : "\(days)d")
    }

    /// 导出今日 HealthKit 数据（JSON 格式，北京时间）
    func exportTodayData() async -> URL? {
        return await exportRecentData(days: 1)
    }

    /// 导出最近 7 天 HealthKit 数据（JSON 格式，北京时间）
    /// - Returns: 临时目录里的 JSON 文件 URL；失败返回 nil
    func exportLast7Days() async -> URL? {
        return await exportRecentData(days: 7)
    }

    /// 把指定日期范围的全部 HealthKit 数据导出成 JSON 写到临时目录
    /// - Parameters:
    ///   - from: 起始时间（含）
    ///   - to: 结束时间（含）
    ///   - fileSuffix: 文件名后缀（如 "7d"），nil 则用默认 `health_export_<timestamp>_<device>.json`
    /// - Returns: 临时文件 URL；失败返回 nil
    private func exportHealthRange(from: Date, to: Date, fileSuffix: String?) async -> URL? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        // 北京时间格式化器（不带时区偏移后缀）
        let bjTz = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = bjTz
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var exportData: [String: Any] = [
            "导出时间": dateFormatter.string(from: to),
            "数据开始": dateFormatter.string(from: from),
            "数据类型": []
        ]

        let types: [(String, HKQuantityTypeIdentifier, HKUnit)] = [
            ("步数", .stepCount, .count()),
            ("活动能量", .activeEnergyBurned, .kilocalorie()),
            ("心率", .heartRate, HKUnit.count().unitDivided(by: .minute())),
            ("静息心率", .restingHeartRate, HKUnit.count().unitDivided(by: .minute())),
            ("心率变异性", .heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli)),
            ("呼吸频率", .respiratoryRate, HKUnit.count().unitDivided(by: .minute())),
            ("距离", .distanceWalkingRunning, .meter()),
            ("爬楼", .flightsClimbed, .count()),
            ("站立时间", .appleStandTime, .hour()),
            ("锻炼时间", .appleExerciseTime, .minute()),
            ("步速", .walkingSpeed, HKUnit.meter().unitDivided(by: .second())),
            ("双脚支撑比例", .walkingDoubleSupportPercentage, .percent()),
            ("耳机音量暴露", .headphoneAudioExposure, HKUnit.decibelAWeightedSoundPressureLevel()),
        ]

        var results: [[String: Any]] = []
        var totalSamples = 0

        for (name, id, unit) in types {
            guard let type = quantityType(id) else {
                print("[Export] ⚠️ \(name) (\(id.rawValue)) → type 为 nil，跳过")
                continue
            }
            let samples = await fetchSamples(type: type, unit: unit, from: from, to: to)
            totalSamples += samples.count
            print("[Export] \(name): \(samples.count) 样本 (from \(from) to \(to))")
            results.append([
                "类型": name,
                "identifier": id.rawValue,
                "样本数": samples.count,
                "数据": samples.map { ["时间": dateFormatter.string(from: $0.0), "值": $0.1] }
            ])
        }

        // 睡眠
        if let sleepType = categoryType(.sleepAnalysis) {
            let sleepSamples = await fetchCategorySamples(type: sleepType, from: from, to: to)
            totalSamples += sleepSamples.count
            print("[Export] 睡眠分析: \(sleepSamples.count) 样本")
            results.append([
                "类型": "睡眠分析",
                "identifier": HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
                "样本数": sleepSamples.count,
                "数据": sleepSamples.map { sample -> [String: Any] in
                    [
                        "时间": dateFormatter.string(from: sample.0),
                        "值": sample.1,
                        "来源": sample.2
                    ]
                }
            ])
        }

        exportData["数据类型"] = results

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            let nameFormatter = DateFormatter()
            nameFormatter.dateFormat = "yyyyMMdd_HHmm"
            nameFormatter.timeZone = bjTz
            let timeStr = nameFormatter.string(from: to)
            let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")
            let suffix = fileSuffix.map { "_\($0)" } ?? ""
            let fileName = "health_export_\(timeStr)_\(deviceName)\(suffix).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try jsonData.write(to: tempURL)
            print("[Export] ✅ 写文件: \(fileName) — \(totalSamples) 总样本 / \(results.count) 类型")
            return tempURL
        } catch {
            print("[HealthKitService] export failed: \(error)")
            return nil
        }
    }

    // MARK: - Mock 注入（写入 HealthKit）

    /// 申请写入权限（首次注入前调用一次）
    func requestWriteAuthorization() async -> Bool {
        guard let store, HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            print("[HealthKitService] write auth failed: \(error)")
            return false
        }
    }

    /// 注入过去 N 天的 mock 数据到 HealthKit（用于验证 7 天导出按钮）。
    /// - Parameters:
    ///   - days: 注入天数（含今天）。days=7 → 注入过去 7 天 + 今天。
    ///   - stepsPerDay: 每天合成的步数（默认 8000，随机 ±2000）
    /// - Returns: 写入的样本总数；失败返回 0
    @discardableResult
    func injectMockDataIntoHealthKit(days: Int = 7, stepsPerDay: Int = 8000) async -> Int {
        guard let store, HKHealthStore.isHealthDataAvailable() else { return 0 }

        // 先申请写入权限（如果之前申请过 read 但没申请过 share，这里会再弹一次）
        _ = await requestWriteAuthorization()

        var samples: [HKSample] = []
        let cal = Calendar.current
        let now = Date()

        for dayOffset in (0..<days).reversed() {
            // 当天 = dayOffset 0；其它 = dayOffset 天前
            guard let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: now)) else { continue }
            samples.append(contentsOf: makeMockSamplesForDay(day: dayStart, now: now, stepsPerDay: stepsPerDay))
        }

        guard !samples.isEmpty else { return 0 }

        do {
            try await store.save(samples)
            print("[HealthKitService] ✅ 注入 \(samples.count) 条样本到 HealthKit（\(days) 天）")
            return samples.count
        } catch {
            print("[HealthKitService] ❌ 注入失败: \(error)")
            return 0
        }
    }

    /// 一天内的 mock 样本：步数（每小时 1 条）+ 心率（每 10 分钟 1 条）+ 距离 + 活动能量 + 睡眠（当晚一段）
    private func makeMockSamplesForDay(day: Date, now: Date, stepsPerDay: Int) -> [HKSample] {
        var out: [HKSample] = []
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)

        // 1. 步数 / 距离 / 活动能量 — 每小时一条（活动时段 8:00-22:00）
        let dayEnd: Date = {
            if isToday {
                return now   // 今天到当前时间，避免注入未来数据
            } else {
                return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) ?? day
            }
        }()

        var cumulativeSteps = 0
        for hour in 0..<24 {
            guard let hourStart = cal.date(byAdding: .hour, value: hour, to: cal.startOfDay(for: day)),
                  hourStart < dayEnd else { continue }
            let hourEnd = min(cal.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart, dayEnd)

            // 8:00-22:00 是活动时段，均匀分布步数；其它时段少量
            let isActiveHour = hour >= 8 && hour < 22
            let weight = isActiveHour ? 1.0 : 0.05
            let hourSteps = Int(Double(stepsPerDay) * weight / 14.0)  // 14 小时活动 / 1 小时其它
            cumulativeSteps += hourSteps

            if let stepType = quantityType(.stepCount) {
                let sample = HKQuantitySample(
                    type: stepType,
                    quantity: HKQuantity(unit: .count(), doubleValue: Double(hourSteps)),
                    start: hourStart, end: hourEnd
                )
                out.append(sample)
            }
            if let distType = quantityType(.distanceWalkingRunning) {
                // 平均步幅 0.75m
                let meters = Double(hourSteps) * 0.75
                let sample = HKQuantitySample(
                    type: distType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                    start: hourStart, end: hourEnd
                )
                out.append(sample)
            }
            if let energyType = quantityType(.activeEnergyBurned) {
                // 每千步约 40 kcal
                let kcal = Double(hourSteps) * 0.04
                let sample = HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: hourStart, end: hourEnd
                )
                out.append(sample)
            }
        }

        // 2. 心率 — 每 10 分钟一条，活动时段稍高
        guard let hrType = quantityType(.heartRate) else { return out }
        var t = cal.startOfDay(for: day)
        while t < dayEnd {
            let hour = cal.component(.hour, from: t)
            let bpm: Double
            if hour >= 0 && hour < 7 {
                bpm = Double.random(in: 52...60)   // 睡眠
            } else if hour >= 8 && hour < 22 {
                bpm = Double.random(in: 70...95)   // 白天
            } else {
                bpm = Double.random(in: 60...72)   // 晚间
            }
            let hrSample = HKQuantitySample(
                type: hrType,
                quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: bpm),
                start: t, end: t.addingTimeInterval(10 * 60)
            )
            out.append(hrSample)
            t = t.addingTimeInterval(10 * 60)
        }

        // 3. 睡眠 — 当晚 23:30 到次日 06:30（HKCategorySample，value=2 表示 Asleep）
        //   跳过今天（避免注入未来时间）
        if !isToday, let sleepType = categoryType(.sleepAnalysis) {
            // "当晚"= day 当天 23:30 → 次日 06:30
            // 对于 day=N（N>0），就寝发生在 day=N 当晚 23:30，醒来在 day=N+1 早晨 06:30
            // 所以 sleep start = day 23:30, end = day+1 06:30
            guard let sleepStart = cal.date(bySettingHour: 23, minute: 30, second: 0, of: day),
                  let sleepEnd = cal.date(byAdding: .day, value: 1, to: cal.date(bySettingHour: 6, minute: 30, second: 0, of: day) ?? day) else { return out }
            let sleepSample = HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                start: sleepStart, end: sleepEnd
            )
            out.append(sleepSample)
        }

        return out
    }

    /// 删除过去 N 天注入的 mock 数据（清理用 — 仅删 sourceName == "Stick Mock" 的样本）
    func clearMockDataFromHealthKit(days: Int = 7) async -> Int {
        guard let store, HKHealthStore.isHealthDataAvailable() else { return 0 }
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now, options: .strictStartDate)

        var deleted = 0
        for type in writeTypes {
            let samples: [HKSample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                    cont.resume(returning: results ?? [])
                }
                store.execute(q)
            }
            // 仅删 metadata.sourceName == "Stick Mock" 的样本
            let toDelete = samples.filter { $0.metadata?["source"] as? String == "Stick Mock" || $0.sourceRevision.source.name.contains("Mock") }
            guard !toDelete.isEmpty else { continue }
            do {
                try await store.delete(toDelete)
                deleted += toDelete.count
            } catch {
                print("[HealthKitService] ❌ 删除失败: \(error)")
            }
        }
        // 给样本加上 source metadata 后再标记
        return deleted
    }

    private func fetchSamples(type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async -> [(Date, Double)] {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let result = (samples as? [HKQuantitySample])?.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) } ?? []
                cont.resume(returning: result)
            }
            store?.execute(q)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType, from: Date, to: Date) async -> [(Date, String, String)] {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let result = (samples as? [HKCategorySample])?.map { sample -> (Date, String, String) in
                    let value: String
                    if type.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
                        switch sample.value {
                        case 1: value = "在床上"
                        case 2: value = "入睡"
                        case 4: value = "清醒"
                        default: value = "未知(\(sample.value))"
                        }
                    } else {
                        value = String(sample.value)
                    }
                    return (sample.startDate, value, sample.sourceRevision.productType ?? "未知")
                } ?? []
                cont.resume(returning: result)
            }
            store?.execute(q)
        }
    }
}

// MARK: - 昨日数据查询（用于 Morning Report）

extension HealthKitService {
    /// 24h 窗口内是否有步数数据（用于判断是否启用晨间报告）
    /// 改查 HealthKit 真实样本：之前用 HealthStore.shared.today（app 自
    /// 己 60s 抓一次的本地聚合快照），App 刚启动时本地为空会误判为
    /// 「无步数」导致晨报不生成。改用 HKSampleQuery 直接查 24h 窗口。
    func hasStepData() async -> Bool {
        guard let stepType = quantityType(.stepCount) else { return false }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let windowStart = startOfDay.addingTimeInterval(-86400) // 包含昨日 + 今日
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let predicate = HKQuery.predicateForSamples(
                withStart: windowStart, end: nil, options: .strictStartDate
            )
            let q = HKSampleQuery(
                sampleType: stepType, predicate: predicate, limit: 1, sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: (samples?.isEmpty == false))
            }
            store?.execute(q)
        }
    }

    /// 查询昨日（00:00 ~ 23:59）的快照数据
    func queryYesterdaySnapshots() async -> [HealthSnapshot] {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())),
              let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday) else {
            return []
        }
        return HealthStore.shared.all.filter { $0.timestamp >= yesterday && $0.timestamp < endOfYesterday }
    }

    /// 查询昨日睡眠总分钟数
    /// 优先用 HealthKit sleepAnalysis 累加 asleep 段；无数据时回退到 body state 计数
    func queryYesterdaySleepMinutes() async -> Int {
        let result = await analyzeSleep(forYesterday: Date())
        if result.totalAsleepMinutes > 0 {
            return result.totalAsleepMinutes
        }
        // fallback: body state 计数
        let snapshots = await queryYesterdaySnapshots()
        return snapshots.filter { $0.bodyState == "sleep" }.count
    }

    /// 查询昨日步行总分钟数
    func queryYesterdayWalkMinutes() async -> Int {
        let snapshots = await queryYesterdaySnapshots()
        return snapshots.filter { $0.bodyState == "walk" }.count
    }

    /// 查询昨日久坐总分钟数
    func queryYesterdaySedentaryMinutes() async -> Int {
        let snapshots = await queryYesterdaySnapshots()
        return snapshots.filter { $0.bodyState == "sit" }.count
    }

    /// 查询昨日总步数
    func queryYesterdaySteps() async -> Int {
        let snapshots = await queryYesterdaySnapshots()
        return snapshots.last?.cumulativeStepCount ?? 0
    }

    /// 查询昨日起床时间（分钟，0-1439）
    /// 优先用 HealthKit sleepAnalysis 的 awake 段；无数据时回退到 body state 首条 walk
    func queryYesterdayWakeUpMinute() async -> Int {
        if let wakeMin = await todayWakeUpMinuteFromHealthKit() {
            return wakeMin
        }
        // fallback: body state
        let snapshots = await queryYesterdaySnapshots()
        guard let first = snapshots.first(where: { $0.bodyState == "walk" }) else { return 0 }
        return StickState.minutesOfDay(first.timestamp)
    }
}

// MARK: - 心率区间分析

struct HeartRateZoneAnalysis {
    let zone1Percent: Double   // 50-60% max HR (very light)
    let zone2Percent: Double   // 60-70% max HR (light)
    let zone3Percent: Double   // 70-80% max HR (moderate)
    let zone4Percent: Double   // 80-90% max HR (hard)
    let zone5Percent: Double   // 90-100% max HR (max)
    let avgHR: Double
    let maxHR: Double
    let minHR: Double
    let predominantZone: Int   // 1-5
    let timeInHighIntensity: Double  // % time in zone 4-5
}

extension HealthKitService {
    /// 昨日心率区间分析（基于220-age公式）
    /// - Parameter age: 年龄，默认35岁
    /// - Returns: 心率区间分布和统计数据
    func analyzeYesterdayHeartRateZones(age: Int = 35) async -> HeartRateZoneAnalysis? {
        guard let heartRateType = quantityType(.heartRate) else { return nil }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday) else {
            return nil
        }

        let samples = await withCheckedContinuation { (cont: CheckedContinuation<[Double], Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: endOfYesterday, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let hrValues = (samples as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                } ?? []
                cont.resume(returning: hrValues)
            }
            store?.execute(q)
        }

        guard !samples.isEmpty else { return nil }

        let maxHR = Double(220 - age)
        var zoneCounts = [0, 0, 0, 0, 0]
        var totalHR: Double = 0
        let maxVal = samples.max() ?? 0
        let minVal = samples.min() ?? 0

        for hr in samples {
            totalHR += hr
            let ratio = hr / maxHR
            let zone: Int
            if ratio < 0.6 { zone = 0 }      // Zone 1: 50-60%
            else if ratio < 0.7 { zone = 1 } // Zone 2: 60-70%
            else if ratio < 0.8 { zone = 2 } // Zone 3: 70-80%
            else if ratio < 0.9 { zone = 3 } // Zone 4: 80-90%
            else { zone = 4 }                 // Zone 5: 90-100%
            zoneCounts[zone] += 1
        }

        let total = Double(samples.count)
        let zonePercents = zoneCounts.map { Double($0) / total * 100 }
        let avgHR = totalHR / total

        // Find predominant zone
        var predominantZone = 1
        var maxCount = 0
        for (i, count) in zoneCounts.enumerated() {
            if count > maxCount {
                maxCount = count
                predominantZone = i + 1
            }
        }

        // High intensity = zones 4-5
        let highIntensityPercent = (zoneCounts[3] + zoneCounts[4]) > 0
            ? Double(zoneCounts[3] + zoneCounts[4]) / total * 100 : 0

        return HeartRateZoneAnalysis(
            zone1Percent: zonePercents[0],
            zone2Percent: zonePercents[1],
            zone3Percent: zonePercents[2],
            zone4Percent: zonePercents[3],
            zone5Percent: zonePercents[4],
            avgHR: avgHR,
            maxHR: maxVal,
            minHR: minVal,
            predominantZone: predominantZone,
            timeInHighIntensity: highIntensityPercent
        )
    }

    /// 获取昨日平均心率
    func yesterdayAverageHeartRate() async -> Double? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else {
            return nil
        }
        return await recentAverage(.heartRate, from: yesterday, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    /// 获取昨日最高心率
    func yesterdayMaxHeartRate() async -> Double? {
        guard let heartRateType = quantityType(.heartRate) else { return nil }
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())),
              let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday) else {
            return nil
        }

        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: endOfYesterday, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let maxHR = (samples as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                }.max()
                cont.resume(returning: maxHR)
            }
            store?.execute(q)
        }
    }

    /// 昨日 HRV 平均值 (SDNN in ms)
    func yesterdayHRV() async -> Double? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else {
            return nil
        }
        return await recentAverage(.heartRateVariabilitySDNN, from: yesterday, unit: HKUnit.secondUnit(with: .milli))
    }

    /// 昨日静息心率
    func yesterdayRestingHeartRate() async -> Double? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else {
            return nil
        }
        return await recentAverage(.restingHeartRate, from: yesterday, unit: HKUnit.count().unitDivided(by: .minute()))
    }
}

// MARK: - 睡眠分析 (HealthKit sleepAnalysis 原始数据)

/// 单段睡眠样本
struct SleepStageRecord: Codable, Hashable {
    enum Stage: String, Codable {
        case inBed   // 在床上 (尚未入睡)
        case asleep  // 入睡 (兼容 asleepUnspecified / Core / Deep / REM)
        case awake   // 床内清醒
    }
    let stage: Stage
    let startDate: Date
    let endDate: Date
}

/// 睡眠分析结果
struct SleepAnalysisResult {
    /// 入睡时刻 (昨日首次 inBed/asleep 起点)
    let bedtime: Date?
    /// 醒来的最近 awake 起点 (无 awake 时用最后一段 inBed/asleep 的 endDate)
    let wakeTime: Date?
    /// 昨日累计入睡分钟数 (排除 inBed / awake)
    let totalAsleepMinutes: Int
    /// 入睡前最后一次 walk 时刻 (来自 body state snapshots)
    let lastWalkTime: Date?
    /// 夜间清醒段数
    let awakeCount: Int
    /// 睡眠质量分级
    let quality: String
}

extension HealthKitService {
    /// 把 HKCategoryValueSleepAnalysis 数值映射到我们的 Stage
    /// - value 0: .inBed (iOS 16+)
    /// - value 1: .inBed
    /// - value 2: .asleep (asleepUnspecified)
    /// - value 3: .asleep (asleepCore) - iOS 16+
    /// - value 4: .awake
    /// - value 5: .asleep (asleepDeep) - iOS 16+
    /// - value 6: .asleep (asleepREM) - iOS 16+
    private nonisolated func mapSleepStage(_ rawValue: Int) -> SleepStageRecord.Stage? {
        switch rawValue {
        case 0, 1:
            return .inBed
        case 2, 3, 5, 6:
            return .asleep
        case 4:
            return .awake
        default:
            return nil
        }
    }

    /// 查询最近 N 天内所有 sleepAnalysis 样本
    /// - Parameter daysBack: 从今天起回溯多少天 (含今天)
    /// - Returns: 按 startDate 升序排列的样本
    func querySleepAnalysis(daysBack: Int) async -> [SleepStageRecord] {
        guard let sleepType = categoryType(.sleepAnalysis) else { return [] }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -max(daysBack, 1), to: startOfToday) else { return [] }
        let end = Date()

        return await withCheckedContinuation { (cont: CheckedContinuation<[SleepStageRecord], Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let records: [SleepStageRecord] = (samples as? [HKCategorySample])?.compactMap { sample in
                    guard let stage = self.mapSleepStage(sample.value) else { return nil }
                    return SleepStageRecord(stage: stage, startDate: sample.startDate, endDate: sample.endDate)
                } ?? []
                cont.resume(returning: records)
            }
            store?.execute(q)
        }
    }

    /// 分析昨日 (date 减一天) 的睡眠 + 今日早起数据
    /// - Parameter date: 报告日期 (生成器传入 "今天" 的 date，函数内部取前一天作为 "昨日")
    func analyzeSleep(forYesterday date: Date) async -> SleepAnalysisResult {
        let calendar = Calendar.current
        // 报告 date 视为 "今天"，昨日 = date - 1 天
        let reportDayStart = calendar.startOfDay(for: date)
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: reportDayStart) else {
            return SleepAnalysisResult(
                bedtime: nil, wakeTime: nil, totalAsleepMinutes: 0,
                lastWalkTime: nil, awakeCount: 0, quality: "连续"
            )
        }
        // 睡眠窗口: 昨日 18:00 ~ 今日 12:00 (覆盖从晚 6 点到次日中午的所有可能睡眠段)
        guard let windowStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterdayStart),
              let windowEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reportDayStart)
        else {
            return SleepAnalysisResult(
                bedtime: nil, wakeTime: nil, totalAsleepMinutes: 0,
                lastWalkTime: nil, awakeCount: 0, quality: "连续"
            )
        }

        // 1) 拉取最近 2 天样本，过滤到睡眠窗口
        let allRecords = await querySleepAnalysis(daysBack: 2)
        let windowRecords = allRecords.filter { rec in
            rec.startDate >= windowStart && rec.startDate < windowEnd
        }

        // 2) bedtime = 窗口内最早的 inBed / asleep 起点
        let bedCandidates = windowRecords.filter { $0.stage == .inBed || $0.stage == .asleep }
        let bedtime = bedCandidates.min(by: { $0.startDate < $1.startDate })?.startDate

        // 3) wakeTime: 优先取最后一段 awake 的 startDate；无 awake 时取最后一段 inBed/asleep 的 endDate
        let awakeRecords = windowRecords.filter { $0.stage == .awake }
        let wakeTime: Date? = {
            if let lastAwake = awakeRecords.max(by: { $0.startDate < $1.startDate }) {
                return lastAwake.startDate
            }
            if let lastBed = bedCandidates.max(by: { $0.endDate < $1.endDate }) {
                return lastBed.endDate
            }
            return nil
        }()

        // 4) totalAsleepMinutes = 窗口内 asleep 段累计秒数 / 60
        let totalSeconds = windowRecords
            .filter { $0.stage == .asleep }
            .reduce(0.0) { sum, rec in
                sum + rec.endDate.timeIntervalSince(rec.startDate)
            }
        let totalAsleepMinutes = Int(totalSeconds / 60.0)

        // 5) awakeCount = 窗口内 awake 段数
        let awakeCount = awakeRecords.count

        // 6) quality 按 awakeCount 分级
        let quality: String
        switch awakeCount {
        case 0: quality = "连续"
        case 1: quality = "轻度中断"
        case 2: quality = "中断"
        default: quality = "碎片化"
        }

        // 7) lastWalkTime: 来自 body state snapshots，取 bedtime 之前最后一次 walk
        var lastWalkTime: Date? = nil
        if let bedtime {
            // 找 bedtime 之前的 walk snapshots
            let all = HealthStore.shared.all
            let walksBeforeBed = all.filter { $0.bodyState == "walk" && $0.timestamp < bedtime }
            lastWalkTime = walksBeforeBed.max(by: { $0.timestamp < $1.timestamp })?.timestamp
        }

        return SleepAnalysisResult(
            bedtime: bedtime,
            wakeTime: wakeTime,
            totalAsleepMinutes: totalAsleepMinutes,
            lastWalkTime: lastWalkTime,
            awakeCount: awakeCount,
            quality: quality
        )
    }

    /// 今日最早醒来的分钟 (0-1439)。优先用 HealthKit sleep awake stage，回退到 nil
    func todayWakeUpMinuteFromHealthKit() async -> Int? {
        let records = await querySleepAnalysis(daysBack: 2)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        // 找今天范围内的 awake 段，取最早的 startDate
        let todayAwake = records.filter { $0.stage == .awake && $0.startDate >= todayStart }
        guard let firstAwake = todayAwake.min(by: { $0.startDate < $1.startDate }) else { return nil }
        return StickState.minutesOfDay(firstAwake.startDate)
    }
}
