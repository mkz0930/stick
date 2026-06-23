import SwiftUI

/// 火柴人 4 状态（走 / 站 / 坐 / 睡）。整个 app 围绕这个枚举。
enum StickState: String, CaseIterable, Identifiable, Hashable {
    case walk  = "走"
    case stand = "站"
    case sit   = "坐"
    case sleep = "睡"

    var id: String { rawValue }

    var englishName: String {
        switch self {
        case .walk:  return "WALKING"
        case .stand: return "STANDING"
        case .sit:   return "SITTING"
        case .sleep: return "SLEEPING"
        }
    }

    // MARK: - 主舞台文字（v6 风格）

    /// eyebrow 场景前缀：— OUTDOOR · COMMUTE · WALK —
    var eyebrow: String {
        switch self {
        case .walk:  return "OUTDOOR · COMMUTE · WALK"
        case .stand: return "HOME · IDLE · STANDING"
        case .sit:   return "OFFICE · DEEP WORK · SITTING"
        case .sleep: return "BEDROOM · DEEP SLEEP · LIVE"
        }
    }

    /// 标题强调短语（"你正在 ___ 中"）
    var actionPhrase: String {
        switch self {
        case .walk:  return "能量输出"
        case .stand: return "静态待机"
        case .sit:   return "深度专注"
        case .sleep: return "深度修复"
        }
    }

    /// 标题前导词
    var titlePrefix: String { "你正在" }
    /// 标题结尾词
    var titleSuffix: String { "中" }

    /// 副标题 / sub line
    var subLine: String {
        switch self {
        case .walk:  return "步态稳定 · 步频 118 spm · 心率 92 bpm"
        case .stand: return "无活动 · 心率平稳 · 待命中"
        case .sit:   return "久坐 47 分 · 颈椎前倾 +18° · 心率 78 bpm"
        case .sleep: return "已入睡 2 小时 47 分 · 深睡 1h32m · 侧卧 92%"
        }
    }

    /// 短标题（兼容旧版 UI）
    var caption: String {
        switch self {
        case .walk:  return "正在户外行走"
        case .stand: return "正在站立待机"
        case .sit:   return "正在专注工作"
        case .sleep: return "已入睡"
        }
    }

    /// 一句话概览（兼容旧版 UI）
    var summary: String {
        switch self {
        case .walk:  return "步态稳定 · 心率 92 bpm"
        case .stand: return "无运动 · 心率平稳"
        case .sit:   return "久坐 47 分 · 颈椎前倾 +18°"
        case .sleep: return "侧卧 · 呼吸 13/分"
        }
    }

    // MARK: - 指标（每张数据卡）

    /// 关键指标（卡片 1）
    var primaryMetric: Metric {
        switch self {
        case .walk:  return Metric(label: "HEART RATE", value: "92 bpm", status: "ACTIVE",  statusKind: .ok,   desc: "心率 · 正常",   hint: "有氧区间",      metricID: .heartRate)
        case .stand: return Metric(label: "HEART RATE", value: "--",      status: "IDLE",    statusKind: .info, desc: "心率 · 待机",   hint: "暂无活动数据",   metricID: .heartRate)
        case .sit:   return Metric(label: "SEDENTARY",  value: "47:23", status: "WARN",    statusKind: .warn, desc: "持续久坐",       hint: "建议起身活动",  metricID: nil)
        case .sleep: return Metric(label: "SLEEP",      value: "82",    status: "GOOD",    statusKind: .ok,   desc: "睡眠质量评分",   hint: "较 7 日均值 +4", metricID: .sleepStage)
        }
    }

    /// 次要指标（卡片 2）
    var secondaryMetric: Metric {
        switch self {
        case .walk:  return Metric(label: "MOOD",       value: "良好",   status: "GOOD",    statusKind: .ok,   desc: "心情 · 愉悦",   hint: "压力偏低",     metricID: nil)
        case .stand: return Metric(label: "POSTURE",    value: "OK",      status: "GOOD",    statusKind: .ok,   desc: "姿态 · 正常",   hint: "无颈椎前倾",   metricID: .posture)
        case .sit:   return Metric(label: "POSTURE",    value: "POOR",    status: "WARN",    statusKind: .warn, desc: "姿态 · 前倾",   hint: "颈角异常 +18°", metricID: .posture)
        case .sleep: return Metric(label: "HEART RATE", value: "56 bpm",  status: "DEEP",    statusKind: .info, desc: "心率 · 深睡区", hint: "HRV 68 ms",    metricID: .heartRate)
        }
    }

    /// 第三指标（卡片 3）
    var tertiaryMetric: Metric {
        switch self {
        case .walk:  return Metric(label: "DURATION",   value: "18 min", status: "STABLE",  statusKind: .info, desc: "行走 · 累计",   hint: "接近目标",     metricID: .exerciseMinutes)
        case .stand: return Metric(label: "STATUS",     value: "STANDBY", status: "IDLE",   statusKind: .info, desc: "活动状态",     hint: "等下一步动作",  metricID: nil)
        case .sit:   return Metric(label: "HEART RATE", value: "78 bpm", status: "STABLE",  statusKind: .info, desc: "心率 · 静息",   hint: "专注态偏低",   metricID: .heartRate)
        // 翻身指标已删除（无真实数据源）
        case .sleep: return Metric(label: "STATUS",     value: "RESTING", status: "DEEP",   statusKind: .ok,   desc: "睡眠 · 状态",   hint: "无数据时占位",  metricID: nil)
        }
    }

    // MARK: - 主题色（ATLAS v6 调色板）

    /// 主题色：关节、强调点、电量条、徽章
    var accent: Color {
        switch self {
        case .walk:  return Color(red: 0.02, green: 0.59, blue: 0.41)  // #059669  ATLAS 绿
        case .stand: return Color(red: 0.55, green: 0.71, blue: 0.06)  // 黄绿
        case .sit:   return Color(red: 0.92, green: 0.34, blue: 0.05)  // #EA580C  ATLAS 橙
        case .sleep: return Color(red: 0.70, green: 0.60, blue: 0.98)  // 浅紫
        }
    }

    /// 状态软色（背景柔光 / 卡片左 border）
    var accentSoft: Color {
        switch self {
        case .walk:  return Color(red: 0.85, green: 0.94, blue: 0.90)
        case .stand: return Color(red: 0.93, green: 0.97, blue: 0.85)
        case .sit:   return Color(red: 0.99, green: 0.91, blue: 0.83)
        case .sleep: return Color(red: 0.95, green: 0.93, blue: 1.0)
        }
    }
}

// MARK: - 指标元组

struct Metric {
    enum Kind { case ok, warn, info }

    let label: String
    let value: String
    let status: String
    let statusKind: Kind
    let desc: String
    let hint: String
    /// 关联到真实可呈现的指标；nil = 仅装饰文字 (不参与设备能力检查)
    let metricID: MetricID?

    /// 中文显示标签（与内部英文 `label` 解耦，避免破坏现有 `== "HEART RATE"` 等判断）
    var chineseLabel: String {
        switch label {
        case "HEART RATE": return "心率"
        case "SEDENTARY":  return "久坐"
        case "POSTURE":    return "姿态"
        case "MOOD":       return "心情"
        case "SLEEP":      return "睡眠"
        case "DURATION":   return "时长"
        default:           return label
        }
    }
}
// MARK: - 全局主题色已迁移到 SharedKit/SharedState.swift（主 app + Widget 共享）

// MARK: - 24h 时刻表

extension StickState {
    /// 一天中的一个时段（分钟自午夜起，[start, end)）
    struct DaySegment: Identifiable, Hashable {
        let state: StickState
        let startMinute: Int
        let endMinute: Int
        let stepCount: Int?  // 该时段的总步数（仅 walk segment 有值）
        var id: Int { startMinute }
        var duration: Int { endMinute - startMinute }
        var contains: (Int) -> Bool { { $0 >= startMinute && $0 < endMinute } }
    }

    /// 一个典型上班族的 24h 时刻表。所有分钟都覆盖到。
    /// 包含显式的 .stand 段（站立汇报 / 下班站立），避免长时间步行段混入静态站立场景。
    /// 步行段按通勤 / 午餐 / 晚间休闲拆开（不超过 1.5h），更贴近真实节奏。
    static let daySchedule: [DaySegment] = [
        DaySegment(state: .sleep, startMinute: 0,    endMinute: 420,  stepCount: nil),    // 00:00 – 07:00  夜间 / 睡眠 (7h)
        DaySegment(state: .walk,  startMinute: 420,  endMinute: 480,  stepCount: 1500),   // 07:00 – 08:00  晨起通勤 (1h)
        DaySegment(state: .sit,   startMinute: 480,  endMinute: 540,  stepCount: nil),    // 08:00 – 09:00  早会工位 (1h)
        DaySegment(state: .stand, startMinute: 540,  endMinute: 570,  stepCount: nil),    // 09:00 – 09:30  站立汇报 (30min)
        DaySegment(state: .sit,   startMinute: 570,  endMinute: 720,  stepCount: nil),    // 09:30 – 12:00  上午工作 (2.5h)
        DaySegment(state: .walk,  startMinute: 720,  endMinute: 780,  stepCount: 1200),   // 12:00 – 13:00  午餐散步 (1h)
        DaySegment(state: .sit,   startMinute: 780,  endMinute: 1080, stepCount: nil),    // 13:00 – 18:00  下午工作 (5h)
        DaySegment(state: .stand, startMinute: 1080, endMinute: 1110, stepCount: nil),    // 18:00 – 18:30  下班站立 (30min)
        DaySegment(state: .walk,  startMinute: 1110, endMinute: 1170, stepCount: 1500),   // 18:30 – 19:30  通勤 / 晚餐前 (1h)
        DaySegment(state: .sit,   startMinute: 1170, endMinute: 1230, stepCount: nil),    // 19:30 – 20:30  晚餐 (1h)
        DaySegment(state: .walk,  startMinute: 1230, endMinute: 1320, stepCount: 2000),   // 20:30 – 22:00  晚间休闲 (1.5h)
        DaySegment(state: .sleep, startMinute: 1320, endMinute: 1440, stepCount: nil),    // 22:00 – 24:00  入睡 (2h)
    ]

    /// 给定时间查到当前 state
    static func current(at date: Date = Date()) -> StickState {
        currentSegment(at: date)?.state ?? .walk
    }

    /// 给定时间查到当前 segment（方便 UI 显示时段详情）
    static func currentSegment(at date: Date = Date()) -> DaySegment? {
        let m = minutesOfDay(date)
        return daySchedule.first { $0.contains(m) }
    }

    /// Date → 自午夜起的分钟数
    static func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar.current
        return c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
    }

    /// 格式化分钟数 → "HH:MM"
    static func formatMinute(_ m: Int) -> String {
        let h = (m / 60) % 24
        let mm = m % 60
        return String(format: "%02d:%02d", h, mm)
    }
}
