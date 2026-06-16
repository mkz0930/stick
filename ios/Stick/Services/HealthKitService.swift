//
//  HealthKitService.swift
//  抓取 HealthKit 数据 (心率/步数/睡眠/久坐/活动)
//

import Foundation
import HealthKit
import Combine

/// HealthKit 数据快照 (1 分钟一条)
struct HealthSnapshot: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let heartRate: Double?           // bpm
    let stepCount: Int?              // 当前分钟内步数增量
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
         stepCount: Int? = nil,
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
        self.stepCount = stepCount
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
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    /// Xcode Canvas Preview 用的 no-op 实例：不构造 HKHealthStore（避免 framework import 卡 preview）
    static let noop = HealthKitService(isPreview: true)

    /// 真实例用 .shared；preview 用 .noop（避开 HKHealthStore() 初始化）
    private let isPreview: Bool
    private let store: HKHealthStore?

    private init(isPreview: Bool = false) {
        self.isPreview = isPreview
        self.store = isPreview ? nil : HKHealthStore()
    }

    @Published var lastSnapshot: HealthSnapshot?
    @Published var isAuthorized: Bool = false
    @Published var error: String?

    private var timer: Timer?

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
        async let mindful = recentSum(.appleExerciseTime, from: dayStart, unit: .minute())  // fallback: exerciseTime
        async let resp = recentAverage(.respiratoryRate, from: from, unit: HKUnit.count().unitDivided(by: .minute()))
        // 距离和爬楼也应是全天累计
        async let dist = recentSum(.distanceWalkingRunning, from: dayStart, unit: .meter())
        async let flights = recentSum(.flightsClimbed, from: dayStart, unit: .count())
        // 静息心率: 当日平均
        async let rhr = recentAverage(.restingHeartRate, from: dayStart, unit: HKUnit.count().unitDivided(by: .minute()))

        let bodyState = currentState
        let source = sourceName()
        let snapshot = HealthSnapshot(
            timestamp: now,
            heartRate: await hr,
            stepCount: (await steps).map { Int($0) },
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
        self.lastSnapshot = snapshot
        return snapshot
    }

    /// 数据来源设备 (iPhone / Apple Watch / 等)
    private func sourceName() -> String? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
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

    private func recentAverage(_ id: HKQuantityTypeIdentifier, from: Date, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: [])
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stat, _ in
                let val = stat?.averageQuantity()?.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            store?.execute(q)
        }
    }

    private func recentSum(_ id: HKQuantityTypeIdentifier, from: Date, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil, options: [])
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stat, _ in
                let val = stat?.sumQuantity()?.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            store?.execute(q)
        }
    }

    /// 今日睡眠总时长（从 Health App 手动记录的睡眠数据）
    func todaySleepHours() async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: [])
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let totalSeconds = (samples as? [HKCategorySample])?.reduce(0.0) { sum, sample in
                    // HKCategorySample.value 对于 sleepAnalysis: 1=InBed, 2=Asleep, 4=Awake
                    let seconds = sample.endDate.timeIntervalSince(sample.startDate)
                    return sum + seconds
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

    // MARK: - 定时抓取 (1 分钟一次)

    func startAutoCapture(interval: TimeInterval = 60) {
        stopAutoCapture()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                let snap = await self.captureSnapshot()
                HealthStore.shared.append(snap)
            }
        }
        // 立即抓一次
        Task {
            let snap = await captureSnapshot()
            HealthStore.shared.append(snap)
        }
    }

    func stopAutoCapture() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Today Convenience Methods

    func todaySteps() async -> Int? {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
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
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
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
    /// 每分钟采样一次，统计步数为 0 的采样点数即为久坐分钟数
    func todaySedentaryMinutes() async -> Int {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let now = Date()

        return await withCheckedContinuation { cont in
            let calendar = Calendar.current
            var interval = DateComponents()
            interval.minute = 1

            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                guard let results = results else {
                    cont.resume(returning: 0)
                    return
                }
                var sedentaryCount = 0
                results.enumerateStatistics(from: startOfDay, to: now) { statistics, _ in
                    let steps = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    if steps == 0 {
                        sedentaryCount += 1
                    }
                }
                cont.resume(returning: sedentaryCount)
            }
            store?.execute(query)
        }
    }
}
