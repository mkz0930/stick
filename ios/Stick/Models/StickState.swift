import SwiftUI

/// 火柴人 3 状态（走 / 坐 / 睡）。整个 app 围绕这个枚举。
enum StickState: String, CaseIterable, Identifiable, Hashable {
    case walk  = "走"
    case sit   = "坐"
    case sleep = "睡"

    var id: String { rawValue }

    var englishName: String {
        switch self {
        case .walk:  return "WALKING"
        case .sit:   return "SITTING"
        case .sleep: return "SLEEPING"
        }
    }

    // MARK: - 主舞台文字（v6 风格）

    /// eyebrow 场景前缀：— OUTDOOR · COMMUTE · WALK —
    var eyebrow: String {
        switch self {
        case .walk:  return "OUTDOOR · COMMUTE · WALK"
        case .sit:   return "OFFICE · DEEP WORK · SITTING"
        case .sleep: return "BEDROOM · DEEP SLEEP · LIVE"
        }
    }

    /// 标题强调短语（"你正在 ___ 中"）
    var actionPhrase: String {
        switch self {
        case .walk:  return "能量输出"
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
        case .sit:   return "久坐 47 分 · 颈椎前倾 +18° · 心率 78 bpm"
        case .sleep: return "已入睡 2 小时 47 分 · 深睡 1h32m · 侧卧 92%"
        }
    }

    /// 短标题（兼容旧版 UI）
    var caption: String {
        switch self {
        case .walk:  return "正在户外行走"
        case .sit:   return "正在专注工作"
        case .sleep: return "已入睡"
        }
    }

    /// 一句话概览（兼容旧版 UI）
    var summary: String {
        switch self {
        case .walk:  return "步态稳定 · 心率 92 bpm"
        case .sit:   return "久坐 47 分 · 颈椎前倾 +18°"
        case .sleep: return "侧卧 · 呼吸 13/分"
        }
    }

    // MARK: - 指标（每张数据卡）

    /// 关键指标（卡片 1）
    var primaryMetric: Metric {
        switch self {
        case .walk:  return Metric(label: "STEPS",      value: "6,242", status: "ACTIVE",  statusKind: .ok,   desc: "今日步数",       hint: "较昨日 +8%")
        case .sit:   return Metric(label: "SEDENTARY",  value: "47:23", status: "WARN",    statusKind: .warn, desc: "持续久坐",       hint: "建议起身活动")
        case .sleep: return Metric(label: "SLEEP",      value: "82",    status: "GOOD",    statusKind: .ok,   desc: "睡眠质量评分",   hint: "较 7 日均值 +4")
        }
    }

    /// 次要指标（卡片 2）
    var secondaryMetric: Metric {
        switch self {
        case .walk:  return Metric(label: "CADENCE",    value: "118 spm", status: "OPTIMAL", statusKind: .ok,   desc: "步频 · 稳定",   hint: "高强度区间")
        case .sit:   return Metric(label: "POSTURE",    value: "POOR",    status: "WARN",    statusKind: .warn, desc: "姿态 · 前倾",   hint: "颈角异常 +18°")
        case .sleep: return Metric(label: "HEART RATE", value: "56 bpm",  status: "DEEP",    statusKind: .info, desc: "心率 · 深睡区", hint: "HRV 68 ms")
        }
    }

    /// 第三指标（卡片 3）
    var tertiaryMetric: Metric {
        switch self {
        case .walk:  return Metric(label: "HEART RATE", value: "92 bpm", status: "ACTIVE",  statusKind: .ok,   desc: "心率 · 正常",   hint: "有氧区间")
        case .sit:   return Metric(label: "HEART RATE", value: "78 bpm", status: "STABLE",  statusKind: .info, desc: "心率 · 静息",   hint: "专注态偏低")
        case .sleep: return Metric(label: "TURNS",      value: "4",     status: "CALM",    statusKind: .ok,   desc: "翻身次数",       hint: "无久压点")
        }
    }

    // MARK: - 主题色（ATLAS v6 调色板）

    /// 主题色：关节、强调点、电量条、徽章
    var accent: Color {
        switch self {
        case .walk:  return Color(red: 0.02, green: 0.59, blue: 0.41)  // #059669  ATLAS 绿
        case .sit:   return Color(red: 0.92, green: 0.34, blue: 0.05)  // #EA580C  ATLAS 橙
        case .sleep: return Color(red: 0.39, green: 0.40, blue: 0.95)  // #6366F1  ATLAS 靛
        }
    }

    /// 状态软色（背景柔光 / 卡片左 border）
    var accentSoft: Color {
        switch self {
        case .walk:  return Color(red: 0.85, green: 0.94, blue: 0.90)
        case .sit:   return Color(red: 0.99, green: 0.91, blue: 0.83)
        case .sleep: return Color(red: 0.87, green: 0.88, blue: 0.99)
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
}

// MARK: - 全局主题色（v6 调色板）

enum Theme {
    /// 页面渐变背景
    static let bgTop    = Color(red: 0.96, green: 0.94, blue: 0.91)  // #F5F0E8
    static let bgBottom = Color(red: 0.93, green: 0.91, blue: 0.86)  // #EDE7DC

    /// 卡片
    static let card       = Color.white
    static let cardBorder = Color.black.opacity(0.10)

    /// 文字
    static let navy  = Color(red: 0.10, green: 0.14, blue: 0.20)  // #1A2332
    static let slate = Color(red: 0.36, green: 0.41, blue: 0.47)  // #5C6878
    static let mist  = Color(red: 0.58, green: 0.64, blue: 0.72)  // #94A3B8

    /// 网格 / 分割
    static let grid       = Color.black.opacity(0.04)
    static let gridStrong = Color.black.opacity(0.06)
    static let border     = Color.black.opacity(0.10)
    static let borderSoft = Color.black.opacity(0.06)
    static let divider    = Color.black.opacity(0.10)

    /// 深色面板（actions / 底部）
    static let darkPanel = Color(red: 0.10, green: 0.14, blue: 0.20)  // #1A2332
    static let darkText  = Color(red: 0.97, green: 0.96, blue: 0.93)  // #F7F4ED
    static let darkMuted = Color(red: 0.58, green: 0.64, blue: 0.72)  // #94A3B8

    /// 火柴人描边默认色
    static let figureStroke = navy
    /// 火柴人内部填充（头/手/脚）默认色：米白
    static let figureFill   = Color(red: 0.97, green: 0.96, blue: 0.93)  // #F7F4ED
}

// MARK: - 24h 时刻表

extension StickState {
    /// 一天中的一个时段（分钟自午夜起，[start, end)）
    struct DaySegment: Identifiable, Hashable {
        let state: StickState
        let startMinute: Int
        let endMinute: Int
        var id: Int { startMinute }
        var duration: Int { endMinute - startMinute }
        var contains: (Int) -> Bool { { $0 >= startMinute && $0 < endMinute } }
    }

    /// 一个典型上班族的 24h 时刻表。所有分钟都覆盖到。
    /// 22:00–07:00 标记为 .sleep（凌晨/夜间休息）
    /// 19:00–22:00 原本是 .stand，删除 .stand 后并入 .walk（晚间散步/休闲）
    static let daySchedule: [DaySegment] = [
        DaySegment(state: .sleep, startMinute: 0,    endMinute: 420),    // 00:00 – 07:00  夜间 / 睡眠
        DaySegment(state: .walk,  startMinute: 420,  endMinute: 510),    // 07:00 – 08:30  晨间通勤
        DaySegment(state: .sit,   startMinute: 510,  endMinute: 720),    // 08:30 – 12:00  上午工作
        DaySegment(state: .walk,  startMinute: 720,  endMinute: 810),    // 12:00 – 13:30  午餐 + 散步
        DaySegment(state: .sit,   startMinute: 810,  endMinute: 1080),   // 13:30 – 18:00  下午工作
        DaySegment(state: .walk,  startMinute: 1080, endMinute: 1320),   // 18:00 – 22:00  晚间通勤 + 休闲（合并）
        DaySegment(state: .sleep, startMinute: 1320, endMinute: 1440),   // 22:00 – 24:00  夜间休息
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
