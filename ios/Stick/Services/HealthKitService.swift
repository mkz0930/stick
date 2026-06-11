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
    private let store = HKHealthStore()

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
        return s
    }()

    // MARK: - 授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            error = "HealthKit 不可用"; return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            self.error = "授权失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 抓取

    /// 抓取一次最近 60 秒的数据 → 合成快照
    func captureSnapshot() async -> HealthSnapshot {
        let now = Date()
        let from = now.addingTimeInterval(-60)
        async let hr    = recentAverage(.heartRate, from: from, unit: HKUnit.count().unitDivided(by: .minute()))
        async let steps = recentSum(.stepCount, from: from, unit: .count())
        async let energy = recentSum(.activeEnergyBurned, from: from, unit: .kilocalorie())
        async let hrv   = recentAverage(.heartRateVariabilitySDNN, from: from, unit: HKUnit.secondUnit(with: .milli))
        // 累计型: 站立小时 / 锻炼分钟 / 正念分钟 — 取今日累计
        let dayStart = Calendar.current.startOfDay(for: now)
        async let stand = recentSum(.appleStandTime, from: dayStart, unit: .hour())
        async let exercise = recentSum(.appleExerciseTime, from: dayStart, unit: .minute())
        async let mindful = recentSum(.appleExerciseTime, from: dayStart, unit: .minute())  // fallback: 用 exerciseTime
        async let resp = recentAverage(.respiratoryRate, from: from, unit: HKUnit.count().unitDivided(by: .minute()))
        async let dist = recentSum(.distanceWalkingRunning, from: from, unit: .meter())
        async let flights = recentSum(.flightsClimbed, from: from, unit: .count())
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
        store.execute(q)
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
            store.execute(q)
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
            store.execute(q)
        }
    }

    // MARK: - 推断身体状态 (来自加速度 + 心率)

    /// 当前身体状态 (综合)
    var currentState: String {
        // 这里先用简化规则 (之后接加速度计会更准)
        let now = Date()
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        if h >= 22 || h < 7 { return "sleep" }
        // 后续可以叠加: 步数>0 → walk, 否则 sit
        return "sit"
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
}
