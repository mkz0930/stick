//
//  DeviceCapabilities.swift
//  设备能力矩阵 — 决定哪些数据可以呈现 / 哪些置灰
//
//  设计目标：UI 各处不需要知道 HealthKit / 蓝牙协议细节，
//  只需要问 "我这个 metric 在当前设备下能呈现吗？"
//

import SwiftUI
import HealthKit

// MARK: - 设备枚举

enum DeviceID: String, CaseIterable, Hashable, Identifiable {
    case iPhone       = "iPhone"
    case appleWatch   = "Apple Watch"
    case smartBelt    = "智能护腰"
    case smartShoe    = "智能运动鞋"
    case airpods      = "AirPods"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .iPhone:      return "iphone"
        case .appleWatch:  return "applewatch"
        case .smartBelt:   return "figure.mind.and.body"
        case .smartShoe:   return "shoeprints.fill"
        case .airpods:     return "earbuds"
        }
    }

    var color: Color {
        switch self {
        case .iPhone:      return Color(red: 0.40, green: 0.45, blue: 0.55)
        case .appleWatch:  return Color(red: 0.95, green: 0.40, blue: 0.45)
        case .smartBelt:   return Color(red: 0.55, green: 0.50, blue: 0.85)
        case .smartShoe:   return Color(red: 0.30, green: 0.70, blue: 0.85)
        case .airpods:     return Color(red: 0.30, green: 0.55, blue: 0.85)
        }
    }

    /// 哪些 metric 在缺这个设备时会被锁住 (用于"推荐解锁"提示)
    var enables: Set<MetricID> {
        MetricID.allCases.filter { $0.required.contains(self) }.reduce(into: Set<MetricID>()) { $0.insert($1) }
    }

    /// 这个设备能提供的 metric 列表 (用于设备行下方小字)
    var capabilities: [MetricID] {
        MetricID.allCases.filter { $0.required.contains(self) }
    }
}

// MARK: - 指标枚举

enum MetricID: String, CaseIterable, Hashable, Identifiable {
    // 心血管 / 呼吸 (基本只有 Watch 才有)
    case heartRate         = "心率"
    case restingHeartRate  = "静息心率"
    case hrv               = "HRV"
    case bloodOxygen       = "血氧"
    case respiratoryRate   = "呼吸频率"

    // 活动 (iPhone 都有)
    case steps             = "步数"
    case distance          = "距离"
    case flightsClimbed    = "爬楼层"
    case activeEnergy      = "活动能量"
    case standHours        = "站立小时"
    case exerciseMinutes   = "锻炼分钟"
    case mindfulMinutes    = "正念分钟"

    // 睡眠 (手动 iPhone ✅, 分期 + 呼吸暂停 Watch)
    case sleepStage        = "睡眠分期"
    case sleepApnea        = "睡眠呼吸暂停"

    // 姿态 (需要护腰/鞋/AirPods 加速计)
    case posture           = "坐姿前倾角"
    case stride            = "步频步态"
    case neckAngle         = "颈椎角度"

    var id: String { rawValue }

    var englishName: String {
        switch self {
        case .heartRate:        return "HEART RATE"
        case .restingHeartRate: return "RHR"
        case .hrv:              return "HRV"
        case .bloodOxygen:      return "SpO₂"
        case .respiratoryRate:  return "RESP"
        case .steps:            return "STEPS"
        case .distance:         return "DIST"
        case .flightsClimbed:   return "FLIGHTS"
        case .activeEnergy:     return "KCAL"
        case .standHours:       return "STAND H"
        case .exerciseMinutes:  return "EX MIN"
        case .mindfulMinutes:   return "MIND MIN"
        case .sleepStage:       return "SLEEP STAGE"
        case .sleepApnea:       return "SLEEP APNEA"
        case .posture:          return "POSTURE"
        case .stride:           return "STRIDE"
        case .neckAngle:        return "NECK ANGLE"
        }
    }

    var icon: String {
        switch self {
        case .heartRate, .restingHeartRate, .hrv:
            return "heart.fill"
        case .bloodOxygen:
            return "drop.fill"
        case .respiratoryRate:
            return "lungs.fill"
        case .steps, .distance, .flightsClimbed:
            return "figure.walk"
        case .activeEnergy:
            return "flame.fill"
        case .standHours:
            return "figure.stand"
        case .exerciseMinutes:
            return "figure.run"
        case .mindfulMinutes:
            return "brain.head.profile"
        case .sleepStage:
            return "bed.double.fill"
        case .sleepApnea:
            return "moon.zzz.fill"
        case .posture:
            return "figure.mind.and.body"
        case .stride:
            return "shoeprints.fill"
        case .neckAngle:
            return "head.side"
        }
    }

    var unit: String {
        switch self {
        case .heartRate, .restingHeartRate:     return "bpm"
        case .hrv:                              return "ms"
        case .bloodOxygen:                      return "%"
        case .respiratoryRate:                  return "/min"
        case .steps:                            return "步"
        case .distance:                         return "m"
        case .flightsClimbed:                   return "层"
        case .activeEnergy:                     return "kcal"
        case .standHours:                       return "h"
        case .exerciseMinutes, .mindfulMinutes: return "min"
        case .sleepStage:                       return "stage"
        case .sleepApnea:                       return "次"
        case .posture:                          return "°"
        case .stride:                           return "spm"
        case .neckAngle:                        return "°"
        }
    }

    /// 至少需要这些设备中的**任一**才能呈现
    var required: Set<DeviceID> {
        switch self {
        case .heartRate, .restingHeartRate, .hrv,
             .bloodOxygen, .respiratoryRate,
             .sleepStage, .sleepApnea:
            return [.appleWatch]

        case .steps, .distance, .flightsClimbed, .activeEnergy,
             .standHours, .exerciseMinutes, .mindfulMinutes:
            return [.iPhone]   // iPhone 自带

        case .posture:
            return [.smartBelt]

        case .stride:
            return [.smartShoe]

        case .neckAngle:
            return [.airpods]  // AirPods 加速计检测头部倾斜
        }
    }

    var category: MetricCategory {
        switch self {
        case .heartRate, .restingHeartRate, .hrv, .bloodOxygen, .respiratoryRate:
            return .vitals
        case .steps, .distance, .flightsClimbed, .activeEnergy, .standHours, .exerciseMinutes, .mindfulMinutes, .stride:
            return .activity
        case .sleepStage, .sleepApnea:
            return .sleep
        case .posture, .neckAngle:
            return .posture
        }
    }

    /// 一行短说明（解锁后能看到什么）
    var hint: String {
        switch self {
        case .heartRate:        return "实时心率 · 静息对比"
        case .restingHeartRate: return "每日静息基线"
        case .hrv:              return "恢复态指标"
        case .bloodOxygen:      return "SpO₂ 趋势"
        case .respiratoryRate:  return "呼吸频率"
        case .steps:            return "步数 · 自动同步"
        case .distance:         return "移动距离"
        case .flightsClimbed:   return "爬楼层"
        case .activeEnergy:     return "活动消耗"
        case .standHours:       return "每小时站立"
        case .exerciseMinutes:  return "中高强度"
        case .mindfulMinutes:   return "正念记录"
        case .sleepStage:       return "深 / 浅 / REM / 清醒"
        case .sleepApnea:       return "呼吸暂停事件"
        case .posture:          return "前倾角 · 久坐"
        case .stride:           return "步频 · 步态"
        case .neckAngle:        return "头部倾斜角"
        }
    }

    /// 数据源类型 — 决定点亮/灰的逻辑
    var dataSource: MetricDataSource {
        switch self {
        case .steps, .distance, .flightsClimbed, .activeEnergy,
             .standHours, .exerciseMinutes, .mindfulMinutes:
            return .iPhoneNative
        case .sleepStage:
            return .iPhoneManual
        case .heartRate, .restingHeartRate, .hrv, .bloodOxygen,
             .respiratoryRate, .sleepApnea:
            return .watchRequired
        case .posture, .stride, .neckAngle:
            return .peripheralRequired
        }
    }

    /// 对应的 HealthKit type (用于真实 query 授权状态)
    var hkType: HKObjectType? {
        switch self {
        case .steps:            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case .distance:         return HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        case .flightsClimbed:   return HKObjectType.quantityType(forIdentifier: .flightsClimbed)
        case .activeEnergy:     return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .standHours:       return HKObjectType.quantityType(forIdentifier: .appleStandTime)
        case .exerciseMinutes:  return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .mindfulMinutes:   return HKObjectType.categoryType(forIdentifier: .mindfulSession)
        case .heartRate:        return HKObjectType.quantityType(forIdentifier: .heartRate)
        case .restingHeartRate: return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .hrv:              return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .respiratoryRate:  return HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        case .sleepStage:       return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .bloodOxygen, .sleepApnea, .posture, .stride, .neckAngle:
            return nil   // iPhone 内置 HealthKit 不支持 (posture/stride/neckAngle 走外设)
        }
    }
}

/// 数据源类型
enum MetricDataSource: String, CaseIterable {
    case iPhoneNative        // iPhone 自身传感器直接出数
    case iPhoneManual        // iPhone 上只能手动 (睡眠 / 正念)
    case watchRequired       // 需要 Apple Watch 才有真实数据
    case peripheralRequired  // 需要智能护腰/鞋/...
}

enum MetricCategory: String, CaseIterable, Hashable, Identifiable {
    case vitals   = "生命体征"
    case activity = "活动"
    case sleep    = "睡眠"
    case posture  = "姿态"

    var id: String { rawValue }

    var order: Int {
        switch self {
        case .vitals: return 0
        case .activity: return 1
        case .sleep: return 2
        case .posture: return 3
        }
    }
}

// MARK: - 能力矩阵查询

enum DeviceCapabilities {

    /// 当前设备集合下, 该 metric 能不能呈现
    static func unlocked(_ metric: MetricID, deviceSet: Set<DeviceID>) -> Bool {
        !metric.required.intersection(deviceSet).isEmpty
    }

    /// 锁定 (不可呈现) 的 metric 列表
    static func lockedMetrics(_ deviceSet: Set<DeviceID>) -> [MetricID] {
        MetricID.allCases.filter { !unlocked($0, deviceSet: deviceSet) }
    }

    /// 解锁中的 metric
    static func availableMetrics(_ deviceSet: Set<DeviceID>) -> [MetricID] {
        MetricID.allCases.filter { unlocked($0, deviceSet: deviceSet) }
    }

    /// 把 unlocked 数量按 category 分组
    static func summary(deviceSet: Set<DeviceID>) -> [(category: MetricCategory, total: Int, unlocked: Int)] {
        MetricCategory.allCases
            .sorted { $0.order < $1.order }
            .map { cat in
                let all = MetricID.allCases.filter { $0.category == cat }
                let on  = all.filter { unlocked($0, deviceSet: deviceSet) }
                return (cat, all.count, on.count)
            }
    }

    /// 缺少哪些设备 — 用于"提示用户连接 XX 解锁"
    /// 返回一个按设备分组的 [DeviceID: [MetricID]] 映射, 只包含未连的设备 + 它们能解锁的指标
    static func unlockSuggestions(_ deviceSet: Set<DeviceID>) -> [DeviceID: [MetricID]] {
        let locked = lockedMetrics(deviceSet)
        var out: [DeviceID: [MetricID]] = [:]
        for dev in DeviceID.allCases where !deviceSet.contains(dev) {
            let enables = locked.filter { $0.required.contains(dev) }
            if !enables.isEmpty {
                out[dev] = enables
            }
        }
        // 按解锁数量降序排
        return out.sorted { $0.value.count > $1.value.count }
            .reduce(into: [:]) { $0[$1.key] = $1.value }
    }

    /// 人类友好的设备 → 名称
    static func deviceShortName(_ d: DeviceID) -> String {
        switch d {
        case .appleWatch: return "Apple Watch"
        case .smartBelt:  return "智能护腰"
        case .smartShoe:  return "智能运动鞋"
        case .airpods:    return "AirPods"
        case .iPhone:     return "iPhone"
        }
    }
}

// MARK: - 数据真实状态 (HealthKit query 结果)

/// 一次 query 的结果
enum MetricDataStatus: Equatable {
    /// iPhone 没硬件 (永远拿不到 — e.g. 心率/HRV/SpO₂)
    case notSupported
    /// 用户拒绝授权 HealthKit 读权限
    case notAuthorized
    /// 已授权 + 过去 7d 有数据
    case hasData
    /// 已授权 + 过去 7d 没数据
    case noData
    /// 还没查完
    case unknown
}

/// 该 metric 在当前 UI 中如何呈现
struct MetricAvailability: Equatable {
    enum Kind: Equatable { case available, availableEmpty, locked }
    let kind: Kind
    /// 灰显时显示的副标 (短)
    let hint: String
    /// 解锁建议 (点开后弹)
    let unlockHint: String?

    static let available = MetricAvailability(kind: .available, hint: "", unlockHint: nil)
    static let availableEmpty = MetricAvailability(kind: .availableEmpty, hint: "", unlockHint: nil)

    static func == (lhs: MetricAvailability, rhs: MetricAvailability) -> Bool {
        lhs.kind == rhs.kind && lhs.hint == rhs.hint && lhs.unlockHint == rhs.unlockHint
    }
}

extension DeviceCapabilities {

    /// 把"数据真实状态 + 当前模拟连接"组合 → UI 呈现
    static func effective(
        _ metric: MetricID,
        status: MetricDataStatus,
        deviceSet: Set<DeviceID>
    ) -> MetricAvailability {
        switch metric.dataSource {
        case .iPhoneNative, .iPhoneManual:
            // iPhone 能拿 — 看真实 query 结果
            switch status {
            case .notAuthorized:
                return MetricAvailability(
                    kind: .locked,
                    hint: "未授权",
                    unlockHint: "去 设置 → 健康 → 数据访问与设备 → Stick 授权"
                )
            case .notSupported:
                return MetricAvailability(
                    kind: .locked,
                    hint: "硬件不支持",
                    unlockHint: nil
                )
            case .hasData:
                return .available
            case .noData, .unknown:
                return .availableEmpty
            }

        case .watchRequired:
            // 真实硬件不支持，但 deviceSet 模拟可解锁
            if deviceSet.contains(.appleWatch) {
                return .available
            }
            return MetricAvailability(
                kind: .locked,
                hint: "需 Apple Watch",
                unlockHint: "连接 Apple Watch 后可呈现心率 / 静息 / HRV / 血氧 / 呼吸"
            )

        case .peripheralRequired:
            if let dev = metric.required.first, deviceSet.contains(dev) {
                return .available
            }
            let devName = metric.required.first?.displayName ?? "外设"
            return MetricAvailability(
                kind: .locked,
                hint: "需 \(devName)",
                unlockHint: "连接 \(devName) 后可呈现"
            )
        }
    }
}
