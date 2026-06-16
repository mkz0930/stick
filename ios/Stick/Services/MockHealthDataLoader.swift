//
//  MockHealthDataLoader.swift
//  模拟器调试用：把导出的 HealthKit JSON 转成 HealthSnapshot 写进 HealthStore
//  真机不需要，HealthKit 实时采集即可
//

import Foundation
import SwiftUI

/// 把导出的 HealthKit JSON 转成 HealthSnapshot 列表，写进 HealthStore 模拟真实数据
@MainActor
final class MockHealthDataLoader {
    static let shared = MockHealthDataLoader()

    /// 从指定 URL 加载 JSON 并写入 HealthStore
    /// - Parameter url: JSON 文件的 URL（用 UIDocumentPicker 或传 file:// URL）
    @discardableResult
    func load(from url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else {
            print("[MockHealthDataLoader] ❌ 读不到文件: \(url.path)")
            return 0
        }
        guard let export = try? JSONDecoder().decode(HealthExport.self, from: data) else {
            print("[MockHealthDataLoader] ❌ JSON 解析失败")
            return 0
        }
        return ingest(export)
    }

    /// 从内嵌的导出 JSON（Bundle 资源或 Documents）载入
    @discardableResult
    func loadBundledIfExists() -> Int {
        // 优先查 Documents/MockHealth.json
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidate = docs.appendingPathComponent("MockHealth.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return load(from: candidate)
        }
        // 再查 Bundle
        if let url = Bundle.main.url(forResource: "MockHealth", withExtension: "json") {
            return load(from: url)
        }
        return 0
    }

    /// 把解析后的 JSON 转成 HealthSnapshot，写进 HealthStore
    @discardableResult
    private func ingest(_ export: HealthExport) -> Int {
        // 1) 按时间聚合步数 / 距离 / 活动能量 / 速度
        struct Bucket {
            var steps: Double = 0
            var distance: Double = 0
            var energy: Double = 0
            var speed: Double = 0
            var haveSpeed = false
        }
        var buckets: [Date: Bucket] = [:]
        let now = Date()

        for t in export.数据类型 {
            switch t.identifier {
            case "HKQuantityTypeIdentifierStepCount":
                for d in t.数据 {
                    let ts = Self.parseDate(d.时间) ?? now
                    let key = ts.timeTruncatedToMinute()
                    buckets[key, default: Bucket()].steps += d.值
                }
            case "HKQuantityTypeIdentifierDistanceWalkingRunning":
                for d in t.数据 {
                    let ts = Self.parseDate(d.时间) ?? now
                    let key = ts.timeTruncatedToMinute()
                    buckets[key, default: Bucket()].distance += d.值
                }
            case "HKQuantityTypeIdentifierActiveEnergyBurned":
                for d in t.数据 {
                    let ts = Self.parseDate(d.时间) ?? now
                    let key = ts.timeTruncatedToMinute()
                    buckets[key, default: Bucket()].energy += d.值
                }
            case "HKQuantityTypeIdentifierWalkingSpeed":
                for d in t.数据 {
                    let ts = Self.parseDate(d.时间) ?? now
                    let key = ts.timeTruncatedToMinute()
                    var b = buckets[key] ?? Bucket()
                    b.speed = d.值
                    b.haveSpeed = true
                    buckets[key] = b
                }
            default:
                continue
            }
        }

        // 2) 按时间排序，转 HealthSnapshot
        let sortedKeys = buckets.keys.sorted()
        var cumulativeSteps = 0
        var prevSteps = 0
        var snapshots: [HealthSnapshot] = []
        for key in sortedKeys {
            let b = buckets[key]!
            cumulativeSteps = max(cumulativeSteps, Int(b.steps.rounded()))
            let incremental = max(0, cumulativeSteps - prevSteps)
            prevSteps = cumulativeSteps

            // 推断 bodyState
            let comps = Calendar.current.dateComponents([.hour, .minute], from: key)
            let body = inferBodyState(steps: b.steps, energy: b.energy, speed: b.speed, hasSpeed: b.haveSpeed, hour: comps.hour ?? 0, minute: comps.minute ?? 0)

            // 估算心率（按状态）
            let hr = estimateHeartRate(body: body)

            let snap = HealthSnapshot(
                timestamp: key,
                heartRate: hr,
                cumulativeStepCount: cumulativeSteps,
                incrementalStepCount: incremental,
                activeEnergy: b.energy > 0 ? b.energy : nil,
                bodyState: body,
                heartRateVariability: nil,
                restingHeartRate: nil,
                standHours: nil,
                exerciseMinutes: nil,
                mindfulMinutes: nil,
                respiratoryRate: nil,
                distance: b.distance > 0 ? b.distance : nil,
                flightsClimbed: nil,
                sourceName: "Mock"
            )
            snapshots.append(snap)
        }

        // 3) 补齐间隙：两个 bucket 之间的每一分钟都生成快照（sit/sleep）
        var filled: [HealthSnapshot] = []
        var lastCumulative = 0
        let calendar = Calendar.current
        for (idx, snap) in snapshots.enumerated() {
            if idx == 0 {
                filled.append(snap)
                lastCumulative = snap.cumulativeStepCount ?? 0
                continue
            }
            let prev = snapshots[idx - 1]
            let gapMinutes = Int(snap.timestamp.timeIntervalSince(prev.timestamp) / 60)
            if gapMinutes > 1 {
                // 逐分钟填补
                for offset in 1..<gapMinutes {
                    let fillTime = prev.timestamp.addingTimeInterval(Double(offset) * 60)
                    let comps = calendar.dateComponents([.hour, .minute], from: fillTime)
                    let hour = comps.hour ?? 0
                    let minute = comps.minute ?? 0
                    let bodyState: String
                    if hour >= 0 && hour < 6 {
                        bodyState = "sleep"
                    } else if hour == 13 && minute < 30 {
                        bodyState = "sleep"  // 午休
                    } else {
                        bodyState = "sit"
                    }
                    let hr = estimateHeartRate(body: bodyState)
                    let fillSnap = HealthSnapshot(
                        timestamp: fillTime,
                        heartRate: hr,
                        cumulativeStepCount: lastCumulative,
                        incrementalStepCount: 0,
                        activeEnergy: nil,
                        bodyState: bodyState,
                        heartRateVariability: nil,
                        restingHeartRate: nil,
                        standHours: nil,
                        exerciseMinutes: nil,
                        mindfulMinutes: nil,
                        respiratoryRate: nil,
                        distance: nil,
                        flightsClimbed: nil,
                        sourceName: "Mock"
                    )
                    filled.append(fillSnap)
                }
            }
            filled.append(snap)
            lastCumulative = snap.cumulativeStepCount ?? lastCumulative
        }
        snapshots = filled

        // 4) 末尾补齐到当前时间（最新快照之后的所有分钟填 sit）
        if let last = snapshots.last {
            let now = Date()
            let lastTime = last.timestamp
            let gapsFromNow = Int(now.timeIntervalSince(lastTime) / 60)
            if gapsFromNow > 1 {
                for offset in 1..<gapsFromNow {
                    let fillTime = lastTime.addingTimeInterval(Double(offset) * 60)
                    let comps = calendar.dateComponents([.hour, .minute], from: fillTime)
                    let hour = comps.hour ?? 0
                    let minute = comps.minute ?? 0
                    let bodyState: String
                    if hour >= 0 && hour < 6 {
                        bodyState = "sleep"
                    } else if hour == 13 && minute < 30 {
                        bodyState = "sleep"  // 午休
                    } else {
                        bodyState = "sit"
                    }
                    let hr = estimateHeartRate(body: bodyState)
                    let fillSnap = HealthSnapshot(
                        timestamp: fillTime,
                        heartRate: hr,
                        cumulativeStepCount: lastCumulative,
                        incrementalStepCount: 0,
                        activeEnergy: nil,
                        bodyState: bodyState,
                        heartRateVariability: nil,
                        restingHeartRate: nil,
                        standHours: nil,
                        exerciseMinutes: nil,
                        mindfulMinutes: nil,
                        respiratoryRate: nil,
                        distance: nil,
                        flightsClimbed: nil,
                        sourceName: "Mock"
                    )
                    snapshots.append(fillSnap)
                }
            }
        }

        // 4) 写进 HealthStore（替换现有数据 — 通过 setAll 公开方法）
        HealthStore.shared.setAllForMock(snapshots)
        // 5) 同步生成 24h 时刻表 — 让时间线轴也用真实状态上色
        let schedule = Self.buildDaySchedule(from: snapshots)
        Task { @MainActor in
            guard HealthKitService.shared.realDaySchedule != schedule else { return }
            HealthKitService.shared.realDaySchedule = schedule
        }
        print("[MockHealthDataLoader] ✅ 注入 \(snapshots.count) 条快照 + \(schedule.count) 个时刻段")
        return snapshots.count
    }

    /// 把快照数组转成 24h 时刻表（每分钟聚合 + 连续段合并）
    private static func buildDaySchedule(from snapshots: [HealthSnapshot]) -> [StickState.DaySegment] {
        // 1) 每分钟状态 + 步数查找表
        var minuteStates: [Int: StickState] = [:]
        var minuteSteps: [Int: Int] = [:]
        for snap in snapshots {
            let m = StickState.minutesOfDay(snap.timestamp)
            if let state = mapToState(snap.bodyState) {
                minuteStates[m] = state
            }
            minuteSteps[m] = (minuteSteps[m] ?? 0) + snap.incrementalStepCount
        }
        // 2) 连续相同 state → 合并为段，walk 段统计步数
        var segments: [StickState.DaySegment] = []
        var current: StickState? = nil
        var start = 0
        for m in 0..<1440 {
            let state = minuteStates[m] ?? .sit
            if state != current {
                if let cur = current {
                    // 统计当前段的总步数
                    let segmentSteps = cur == .walk ? (start..<m).reduce(0) { $0 + (minuteSteps[$1] ?? 0) } : nil
                    segments.append(StickState.DaySegment(
                        state: cur,
                        startMinute: start,
                        endMinute: m,
                        stepCount: segmentSteps
                    ))
                }
                current = state
                start = m
            }
        }
        if let cur = current {
            let segmentSteps = cur == .walk ? (start..<1440).reduce(0) { $0 + (minuteSteps[$1] ?? 0) } : nil
            segments.append(StickState.DaySegment(
                state: cur,
                startMinute: start,
                endMinute: 1440,
                stepCount: segmentSteps
            ))
        }
        return segments
    }

    private static func mapToState(_ raw: String) -> StickState? {
        switch raw {
        case "walk":  return .walk
        case "sit":   return .sit
        case "stand": return .stand
        case "sleep": return .sleep
        default:      return nil
        }
    }

    /// 根据步数 / 能量 / 速度推断姿态
    private func inferBodyState(steps: Double, energy: Double, speed: Double, hasSpeed: Bool, hour: Int, minute: Int = 0) -> String {
        // 夜间 0-6 → 睡眠
        if hour >= 0 && hour < 6 { return "sleep" }
        // 有步速且 > 0.5 → walk
        if hasSpeed && speed > 0.5 { return "walk" }
        // 步数 > 10 → 运动
        if steps > 10 { return "walk" }
        // 能量 > 1 → 活动
        if energy > 1.0 { return "walk" }
        // 13:00-13:30 午休（非运动时默认睡眠）
        if hour == 13 && minute >= 0 && minute < 30 { return "sleep" }
        // 步数 1-10 → 轻度活动
        if steps > 0 { return "sit" }
        // 0 步 → 静坐 / 待命
        return "sit"
    }

    /// 按状态估算心率
    private func estimateHeartRate(body: String) -> Double? {
        switch body {
        case "walk":  return Double.random(in: 95...125)
        case "sit":   return Double.random(in: 70...82)
        case "sleep": return Double.random(in: 52...62)
        case "stand": return Double.random(in: 68...76)
        default:      return 72
        }
    }

    /// 解析日期（支持 ISO8601 + 毫秒；fallback 到无时区本地时间）
    /// 顺序：ISO8601 + 时区 + 毫秒 → ISO8601 + 时区 → 本地无时区 + 毫秒 → 本地无时区
    /// 导出的 HealthKit JSON 时间戳是设备本地时间（无 Z / 无 +08:00），必须按本地时区解释
    private static func parseDate(_ s: String) -> Date? {
        // 1) ISO8601 + 时区 + 毫秒
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        // 2) ISO8601 + 时区（无毫秒）
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // 3) 本地无时区 + 毫秒
        let localWithMs = DateFormatter()
        localWithMs.locale = Locale(identifier: "en_US_POSIX")
        localWithMs.timeZone = TimeZone.current
        localWithMs.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let d = localWithMs.date(from: s) { return d }
        // 4) 本地无时区（无毫秒）
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone.current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: s)
    }
}

private extension Date {
    /// 截到分钟精度（key 用）
    func timeTruncatedToMinute() -> Date {
        let c = Calendar.current
        let comps = c.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return c.date(from: comps) ?? self
    }
}

// MARK: - JSON 解析模型

struct HealthExport: Codable {
    let 导出时间: String
    let 数据开始: String
    let 数据类型: [HealthTypeBlock]

    enum CodingKeys: String, CodingKey {
        case 导出时间, 数据开始, 数据类型
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        导出时间 = (try? c.decode(String.self, forKey: DynamicKey(stringValue: "导出时间")!)) ?? ""
        数据开始 = (try? c.decode(String.self, forKey: DynamicKey(stringValue: "数据开始")!)) ?? ""
        数据类型 = (try? c.decode([HealthTypeBlock].self, forKey: DynamicKey(stringValue: "数据类型")!)) ?? []
    }

    func encode(to encoder: Encoder) throws { fatalError() }
}

struct HealthTypeBlock: Codable {
    let identifier: String
    let 数据: [HealthDataPoint]
    let 样本数: Int?
    let 类型: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        identifier = (try? c.decode(String.self, forKey: DynamicKey(stringValue: "identifier")!)) ?? ""
        数据 = (try? c.decode([HealthDataPoint].self, forKey: DynamicKey(stringValue: "数据")!)) ?? []
        样本数 = try? c.decode(Int.self, forKey: DynamicKey(stringValue: "样本数")!)
        类型 = try? c.decode(String.self, forKey: DynamicKey(stringValue: "类型")!)
    }

    func encode(to encoder: Encoder) throws { fatalError() }
}

struct HealthDataPoint: Codable {
    let 值: Double
    let 时间: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        值 = (try? c.decode(Double.self, forKey: DynamicKey(stringValue: "值")!)) ?? 0
        时间 = (try? c.decode(String.self, forKey: DynamicKey(stringValue: "时间")!)) ?? ""
    }

    func encode(to encoder: Encoder) throws { fatalError() }
}

/// 动态 key（支持中文 key）
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
