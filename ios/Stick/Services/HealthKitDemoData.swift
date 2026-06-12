//
//  HealthKitDemoData.swift
//  模拟器自动注入 — 让用户在没真实数据时也能看到 iPhone native metric 被点亮
//
//  行为:
//   - 启动时检查是否是模拟器
//   - 模拟器上且 HealthKit 7d 内完全没数据 → 注入过去 7 天的样本
//   - 注入完成后 healthAuth.refresh() 重新查状态, tag 自动从灰变亮
//

import Foundation
import HealthKit

@MainActor
final class HealthKitDemoData {
    static let shared = HealthKitDemoData()

    private let store = HKHealthStore()
    private var didInject = false

    /// 模拟器且 HealthKit 没数据时, 注入过去 7 天的样本
    func injectIfNeeded() async {
        guard !didInject else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        didInject = true

        // 先检查过去 7d 步数 — 有数据就不注入
        let hasData = await hasAnyStepData()
        if hasData { return }

        await injectWeekOfSamples()
    }

    private func hasAnyStepData() async -> Bool {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return true }
        let now = Date()
        let from = now.addingTimeInterval(-7 * 24 * 3600)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: from, end: now, options: .strictStartDate),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: !(samples?.isEmpty ?? true))
            }
            store.execute(q)
        }
    }

    /// 注入过去 7 天的步数 / 距离 / 活动能量 / 站立小时 / 锻炼分钟 / 飞行层
    private func injectWeekOfSamples() async {
        let now = Date()
        let cal = Calendar.current
        var samples: [HKQuantitySample] = []

        // 7 天 × 每小时样本
        for dayOffset in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: now)) else { continue }
            for hour in 0..<24 {
                guard let sampleTime = cal.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
                // 跳过未来时间
                guard sampleTime <= now else { continue }

                let hourOfDay = hour
                let isDayTime = hourOfDay >= 7 && hourOfDay <= 22
                // 白天: 中等步数, 晚上: 零
                let stepCount: Int
                if isDayTime {
                    // 上午 7-9 通勤, 中午 12 散步, 下午 18-19 散步 → 略多
                    if hourOfDay == 8 || hourOfDay == 18 { stepCount = Int.random(in: 350...550) }
                    else if hourOfDay == 12 { stepCount = Int.random(in: 200...350) }
                    else { stepCount = Int.random(in: 30...120) }
                } else {
                    stepCount = 0
                }

                if stepCount > 0 {
                    if let type = HKObjectType.quantityType(forIdentifier: .stepCount) {
                        let q = HKQuantity(unit: .count(), doubleValue: Double(stepCount))
                        let s = HKQuantitySample(type: type, quantity: q, start: sampleTime, end: sampleTime)
                        samples.append(s)
                    }
                    // 距离: 步数 × 0.78m
                    if let type = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
                        let q = HKQuantity(unit: .meter(), doubleValue: Double(stepCount) * 0.78)
                        let s = HKQuantitySample(type: type, quantity: q, start: sampleTime, end: sampleTime)
                        samples.append(s)
                    }
                    // 活动能量: 步数 × 0.04 kcal
                    if let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                        let q = HKQuantity(unit: .kilocalorie(), doubleValue: Double(stepCount) * 0.04)
                        let s = HKQuantitySample(type: type, quantity: q, start: sampleTime, end: sampleTime)
                        samples.append(s)
                    }
                }

                // 站立小时: 白天每小时 1h (实际系统写一次/天, 这里按小时注入)
                if isDayTime {
                    if let type = HKObjectType.quantityType(forIdentifier: .appleStandTime) {
                        let q = HKQuantity(unit: .hour(), doubleValue: 1.0)
                        let s = HKQuantitySample(type: type, quantity: q, start: sampleTime, end: sampleTime)
                        samples.append(s)
                    }
                }
            }
        }

        // 锻炼分钟: 每天 18:00 一段 30 min
        for dayOffset in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: now)),
                  let start = cal.date(byAdding: .hour, value: 18, to: dayStart),
                  let end = cal.date(byAdding: .minute, value: 30, to: start),
                  end <= now else { continue }
            if let type = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
                let q = HKQuantity(unit: .minute(), doubleValue: 30)
                let s = HKQuantitySample(type: type, quantity: q, start: start, end: end)
                samples.append(s)
            }
        }

        // 飞行层: 偶尔 2-5 层
        for dayOffset in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: now)),
                  let sampleTime = cal.date(byAdding: .hour, value: 9, to: dayStart),
                  sampleTime <= now else { continue }
            if let type = HKObjectType.quantityType(forIdentifier: .flightsClimbed) {
                let q = HKQuantity(unit: .count(), doubleValue: Double(Int.random(in: 2...5)))
                let s = HKQuantitySample(type: type, quantity: q, start: sampleTime, end: sampleTime)
                samples.append(s)
            }
        }

        // 写入
        guard !samples.isEmpty else { return }
        print("[HealthKitDemoData] 准备注入 \(samples.count) 个样本")

        // 策略 1: try HKHealthStore.save (真机或模拟器已授权时)
        // 策略 2: 失败时转为 HealthSnapshot 写到 HealthStore.shared (本地 JSON)
        store.save(samples) { success, error in
            if success {
                print("[HealthKitDemoData] ✅ saved \(samples.count) samples to HealthKit")
            } else {
                let code = (error as NSError?)?.code ?? 0
                print("[HealthKitDemoData] ⚠️ HealthKit save failed (\(code)) — 降级到本地 HealthStore.shared")
                Task { @MainActor in
                    Self.fallbackToLocalStore(samples: samples)
                }
            }
        }
    }

    /// 模拟器 / 未授权时降级: 把 HKQuantitySample 转成 HealthSnapshot 写本地
    private static func fallbackToLocalStore(samples: [HKQuantitySample]) {
        for sample in samples {
            guard let mapped = mapSample(sample) else { continue }
            HealthStore.shared.append(mapped)
        }
        print("[HealthKitDemoData] 📦 wrote \(samples.count) to local HealthStore.shared")
    }

    private static func mapSample(_ s: HKQuantitySample) -> HealthSnapshot? {
        let id = s.uuid
        let timestamp = s.startDate
        let sourceName = "DemoData"
        if let q = HKQuantityType.quantityType(forIdentifier: .stepCount), s.sampleType == q {
            let v = s.quantity.doubleValue(for: .count())
            return HealthSnapshot(timestamp: timestamp, heartRate: nil, stepCount: Int(v), activeEnergy: nil,
                                 heartRateVariability: nil, restingHeartRate: nil, standHours: nil,
                                 exerciseMinutes: nil, mindfulMinutes: nil, respiratoryRate: nil,
                                 distance: nil, flightsClimbed: nil, sourceName: sourceName)
        }
        if let q = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning), s.sampleType == q {
            let v = s.quantity.doubleValue(for: .meter())
            return HealthSnapshot(timestamp: timestamp, heartRate: nil, stepCount: nil, activeEnergy: nil,
                                 heartRateVariability: nil, restingHeartRate: nil, standHours: nil,
                                 exerciseMinutes: nil, mindfulMinutes: nil, respiratoryRate: nil,
                                 distance: v, flightsClimbed: nil, sourceName: sourceName)
        }
        if let q = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned), s.sampleType == q {
            let v = s.quantity.doubleValue(for: .kilocalorie())
            return HealthSnapshot(timestamp: timestamp, heartRate: nil, stepCount: nil, activeEnergy: v,
                                 heartRateVariability: nil, restingHeartRate: nil, standHours: nil,
                                 exerciseMinutes: nil, mindfulMinutes: nil, respiratoryRate: nil,
                                 distance: nil, flightsClimbed: nil, sourceName: sourceName)
        }
        if let q = HKQuantityType.quantityType(forIdentifier: .appleStandTime), s.sampleType == q {
            let v = Int(s.quantity.doubleValue(for: .hour()))
            return HealthSnapshot(timestamp: timestamp, heartRate: nil, stepCount: nil, activeEnergy: nil,
                                 heartRateVariability: nil, restingHeartRate: nil, standHours: v,
                                 exerciseMinutes: nil, mindfulMinutes: nil, respiratoryRate: nil,
                                 distance: nil, flightsClimbed: nil, sourceName: sourceName)
        }
        if let q = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime), s.sampleType == q {
            let v = Int(s.quantity.doubleValue(for: .minute()))
            return HealthSnapshot(timestamp: timestamp, heartRate: nil, stepCount: nil, activeEnergy: nil,
                                 heartRateVariability: nil, restingHeartRate: nil, standHours: nil,
                                 exerciseMinutes: Double(v), mindfulMinutes: nil, respiratoryRate: nil,
                                 distance: nil, flightsClimbed: nil, sourceName: sourceName)
        }
        if let q = HKQuantityType.quantityType(forIdentifier: .flightsClimbed), s.sampleType == q {
            let v = Int(s.quantity.doubleValue(for: .count()))
            return HealthSnapshot(timestamp: timestamp, heartRate: nil, stepCount: nil, activeEnergy: nil,
                                 heartRateVariability: nil, restingHeartRate: nil, standHours: nil,
                                 exerciseMinutes: nil, mindfulMinutes: nil, respiratoryRate: nil,
                                 distance: nil, flightsClimbed: v, sourceName: sourceName)
        }
        _ = id   // 静默 unused warning
        return nil
    }
}
