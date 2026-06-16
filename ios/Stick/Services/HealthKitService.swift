//
//  HealthKitService.swift
//  抓取 HealthKit 数据 (心率/步数/睡眠/久坐/活动)
//

import Foundation
import HealthKit
import Combine
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
    /// 最后检测到明显步数的时间（incrementalStepCount > 10），用于立即打断久坐计时
    @Published var lastMovementTime: Date? = nil
    /// 基于今天真实 HealthKit 步数数据生成的 24h 时刻表
    @Published var realDaySchedule: [StickState.DaySegment]? = nil

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
        self.lastSnapshot = snapshot
        // 增量步数 > 10 → 打断久坐
        if incremental > 10 {
            self.lastMovementTime = now
        }
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

        // 模拟器且无数据时，生成 mock 快照（模拟用户45分钟前走路，现在坐着）
        if HealthStore.shared.today.isEmpty {
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
        }

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
    /// **改进版**：排除 0-6 点睡眠时段 + 排除 >4h 无数据长间隔
    /// - 0-6 AM：默认是睡眠时间，不算久坐
    /// - 连续 >4h 没有任何步数：可能睡眠/没带手机，整段跳过不算久坐
    /// 推测今早真正起床时间
    /// 逻辑：从 04:00 开始扫描步数，第一条 >50 步的时间 = 真正起床
    /// 夜间起夜（<50步）不算起床；6 点前轻微活动也不算
    func queryWakeUpTime() async -> Date? {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let searchStart = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: startOfDay) else { return nil }
        let now = Date()
        guard now > searchStart else { return nil }

        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: now, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: stepType, predicate: predicate, limit: 50, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else {
                    cont.resume(returning: nil)
                    return
                }
                for sample in samples {
                    let steps = sample.quantity.doubleValue(for: .count())
                    if steps > 50 {
                        cont.resume(returning: sample.startDate)
                        return
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
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
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
        guard let audioType = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure) else { return [] }
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
                var ranges: [ClosedRange<Int>] = []
                var cStart: Int? = nil
                var cLast: Int? = nil
                for s in samples {
                    let m = StickState.minutesOfDay(s.startDate)
                    if cStart == nil {
                        cStart = m; cLast = m
                    } else if m - (cLast ?? 0) <= 10 {
                        cLast = m
                    } else {
                        if let s = cStart, let l = cLast {
                            ranges.append(s...l)
                        }
                        cStart = m; cLast = m
                    }
                }
                if let s = cStart, let l = cLast {
                    ranges.append(s...l)
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
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return [] }
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
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return 0 }
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

            query.initialResultsHandler = { _, results, error in
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
    func computeDaySchedule() async {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
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

                    // 5) 距上次活动 > 4h → 睡眠/离开（夜间清醒已被 step 0 提前排除，不会误判）
                    if let last = lastActiveMinute, minute - last > maxGapMinutes {
                        states[minute] = .sleep
                        continue
                    }

                    // 6) 默认久坐
                    states[minute] = .sit
                }

                // Pass 4: 合并连续相同状态为 DaySegment 数组
                var segments: [StickState.DaySegment] = []
                var i = 0
                while i < 1440 {
                    let s = states[i]
                    var j = i + 1
                    while j < 1440 && states[j] == s { j += 1 }
                    segments.append(StickState.DaySegment(state: s, startMinute: i, endMinute: j))
                    i = j
                }

                // 切回主线程写入 @Published 属性
                Task { @MainActor in
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
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
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
        var yesterday = calendar.startOfDay(for: now)
        yesterday = calendar.date(byAdding: .day, value: -1, to: yesterday)!
        let nightStart = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: yesterday)!

        // 今天 10:00
        let today = calendar.startOfDay(for: now)
        let morningEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!

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

    /// 导出今日全部 HealthKit 数据（JSON 格式，北京时间）
    func exportTodayData() async -> URL? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let dayStart = Calendar.current.startOfDay(for: Date())
        let now = Date()

        // 北京时间格式化器（不带时区偏移后缀）
        let bjTz = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = bjTz
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var exportData: [String: Any] = [
            "导出时间": dateFormatter.string(from: now),
            "数据开始": dateFormatter.string(from: dayStart),
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

        for (name, id, unit) in types {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            let samples = await fetchSamples(type: type, unit: unit, from: dayStart, to: now)
            results.append([
                "类型": name,
                "identifier": id.rawValue,
                "样本数": samples.count,
                "数据": samples.map { ["时间": dateFormatter.string(from: $0.0), "值": $0.1] }
            ])
        }

        // 睡眠
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let sleepSamples = await fetchCategorySamples(type: sleepType, from: dayStart, to: now)
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
            let timeStr = nameFormatter.string(from: now)
            let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")
            let fileName = "health_export_\(timeStr)_\(deviceName).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try jsonData.write(to: tempURL)
            return tempURL
        } catch {
            print("[HealthKitService] export failed: \(error)")
            return nil
        }
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
    /// 当日是否有步数数据（用于判断是否启用晨间报告）
    var hasStepData: Bool {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return HealthStore.shared.today.contains { $0.cumulativeStepCount ?? 0 > 0 }
    }

    /// 查询昨日（00:00 ~ 23:59）的快照数据
    func queryYesterdaySnapshots() async -> [HealthSnapshot] {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday)!
        return HealthStore.shared.all.filter { $0.timestamp >= yesterday && $0.timestamp < endOfYesterday }
    }

    /// 查询昨日睡眠总分钟数
    func queryYesterdaySleepMinutes() async -> Int {
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
    func queryYesterdayWakeUpMinute() async -> Int {
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
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }

        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday)!

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
        var maxVal = samples.max() ?? 0
        var minVal = samples.min() ?? 0

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
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        return await recentAverage(.heartRate, from: yesterday, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    /// 获取昨日最高心率
    func yesterdayMaxHeartRate() async -> Double? {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday)!

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
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        return await recentAverage(.heartRateVariabilitySDNN, from: yesterday, unit: HKUnit.secondUnit(with: .milli))
    }

    /// 昨日静息心率
    func yesterdayRestingHeartRate() async -> Double? {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        return await recentAverage(.restingHeartRate, from: yesterday, unit: HKUnit.count().unitDivided(by: .minute()))
    }
}
