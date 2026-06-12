//
//  HealthAnalyzer.swift
//  时间维度分析 — 把 1 分钟快照按小时聚合成洞察
//

import Foundation

struct HealthInsight: Identifiable {
    enum Kind { case sedentary, active, lowHeartRate, highHeartRate, sleepWindow, lowSteps, hydration, generic }
    enum Severity { case info, warn, alert }

    let id = UUID()
    let kind: Kind
    let severity: Severity
    let title: String
    let detail: String
    let timestampRange: String     // "14:00–16:00"
    let numericValue: String?      // "≈ 2.3h"
}

@MainActor
final class HealthAnalyzer {
    static let shared = HealthAnalyzer()

    /// 把一天的快照聚合成洞察
    func analyze(snapshots: [HealthSnapshot]) -> [HealthInsight] {
        guard !snapshots.isEmpty else { return [] }

        var insights: [HealthInsight] = []

        // 1) 久坐检测 — 连续 30 分钟 bodyState == sit 且步数 == 0
        insights.append(contentsOf: detectSedentary(snapshots))

        // 2) 活跃时段 — 连续 walk 5+ 分钟
        insights.append(contentsOf: detectActive(snapshots))

        // 3) 心率异常
        insights.append(contentsOf: detectHeartRate(snapshots))

        // 4) HRV (心率变异性) 偏低 — 压力/恢复力指标
        insights.append(contentsOf: detectHRV(snapshots))

        // 5) 步数不足
        insights.append(contentsOf: detectStepGoal(snapshots))

        // 6) 站立小时不足 (苹果手表指标)
        insights.append(contentsOf: detectStandHours(snapshots))

        // 7) 锻炼时间不足
        insights.append(contentsOf: detectExerciseTime(snapshots))

        // 8) 睡眠窗口
        insights.append(contentsOf: detectSleep(snapshots))

        // 8b) 睡眠异常 (vs. 参考 7-9h)
        insights.append(contentsOf: detectSleepAbnormality(snapshots))

        // 9) 距离 / 楼层
        insights.append(contentsOf: detectDistance(snapshots))

        // 10) 呼吸频率
        insights.append(contentsOf: detectRespiratory(snapshots))

        // 按时间排序
        return insights.sorted { $0.timestampRange < $1.timestampRange }
    }

    // MARK: - 久坐

    private func detectSedentary(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        var out: [HealthInsight] = []
        var runStart: Date?
        var runMinutes: Int = 0
        var lastTimestamp: Date?

        for s in snaps {
            let moving = (s.stepCount ?? 0) > 0
            let isSit = (s.bodyState == "sit") && !moving
            if isSit {
                if runStart == nil { runStart = s.timestamp }
                runMinutes += 1
                lastTimestamp = s.timestamp
            } else {
                if let s_ = runStart, runMinutes >= 30 {
                    out.append(HealthInsight(
                        kind: .sedentary,
                        severity: runMinutes >= 60 ? .alert : .warn,
                        title: runMinutes >= 60 ? "久坐超过 1 小时" : "久坐 30 分钟以上",
                        detail: "建议起身活动 5 分钟, 拉伸颈肩",
                        timestampRange: "\(hhmm(s_))–\(hhmm(lastTimestamp ?? s_))",
                        numericValue: "\(runMinutes) 分钟"
                    ))
                }
                runStart = nil; runMinutes = 0
            }
        }
        return out
    }

    // MARK: - 活跃

    private func detectActive(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        var out: [HealthInsight] = []
        var runStart: Date?
        var runMinutes: Int = 0
        var lastTimestamp: Date?

        for s in snaps {
            let active = (s.bodyState == "walk") || ((s.stepCount ?? 0) > 0)
            if active {
                if runStart == nil { runStart = s.timestamp }
                runMinutes += 1
                lastTimestamp = s.timestamp
            } else {
                if let s_ = runStart, runMinutes >= 5 {
                    out.append(HealthInsight(
                        kind: .active,
                        severity: .info,
                        title: "活跃时段",
                        detail: "持续活动, 状态良好",
                        timestampRange: "\(hhmm(s_))–\(hhmm(lastTimestamp ?? s_))",
                        numericValue: "\(runMinutes) 分钟"
                    ))
                }
                runStart = nil; runMinutes = 0
            }
        }
        return out
    }

    // MARK: - 心率

    private func detectHeartRate(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        var out: [HealthInsight] = []
        let hrs = snaps.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return out }
        let avg = hrs.reduce(0, +) / Double(hrs.count)
        let maxV = hrs.max() ?? 0
        let minV = hrs.min() ?? 0

        if avg > 100 {
            out.append(HealthInsight(
                kind: .highHeartRate, severity: .warn,
                title: "平均心率偏高", detail: "可能压力较大或咖啡因摄入",
                timestampRange: "今日全天", numericValue: "avg \(Int(avg)) bpm"
            ))
        }
        if maxV > 140 {
            out.append(HealthInsight(
                kind: .highHeartRate, severity: .alert,
                title: "心率峰值异常", detail: "建议关注",
                timestampRange: "今日全天", numericValue: "peak \(Int(maxV)) bpm"
            ))
        }
        return out
    }

    // MARK: - 步数

    private func detectStepGoal(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let total = snaps.compactMap { $0.stepCount }.reduce(0, +)
        if total < 3000 && !snaps.isEmpty {
            return [HealthInsight(
                kind: .lowSteps, severity: .warn,
                title: "今日步数偏少", detail: "目标 6000 步, 建议多走动",
                timestampRange: "今日", numericValue: "\(total) 步"
            )]
        }
        return []
    }

    // MARK: - 睡眠

    private func detectSleep(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let sleeps = snaps.filter { $0.bodyState == "sleep" }
        guard !sleeps.isEmpty else { return [] }
        let start = sleeps.first!.timestamp
        let end = sleeps.last!.timestamp
        let mins = Int(end.timeIntervalSince(start) / 60)
        if mins > 60 {
            return [HealthInsight(
                kind: .sleepWindow, severity: .info,
                title: "睡眠窗口", detail: "记录到的睡眠时长",
                timestampRange: "\(hhmm(start))–\(hhmm(end))",
                numericValue: "\(mins / 60)h \(mins % 60)m"
            )]
        }
        return []
    }

    // MARK: - 睡眠质量 (vs. 参考 7-9h)

    /// 对比「参考睡眠区间 7-9h」评估最近一次睡眠
    private func detectSleepAbnormality(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let sleeps = snaps.filter { $0.bodyState == "sleep" }
        guard !sleeps.isEmpty else { return [] }
        let start = sleeps.first!.timestamp
        let end = sleeps.last!.timestamp
        let mins = max(1, Int(end.timeIntervalSince(start) / 60))
        let hours = Double(mins) / 60.0

        if hours < 6.0 {
            return [HealthInsight(
                kind: .sleepWindow, severity: .alert,
                title: "睡眠严重不足",
                detail: String(format: "参考 7-9h，差 %.1fh，建议提前入睡 + 减少晚间屏幕",
                               7.0 - hours),
                timestampRange: "\(hhmm(start))–\(hhmm(end))",
                numericValue: String(format: "%.1fh", hours)
            )]
        } else if hours < 7.0 {
            return [HealthInsight(
                kind: .sleepWindow, severity: .warn,
                title: "睡眠不足",
                detail: "参考 7-9h，建议今晚提前 30 分钟入睡",
                timestampRange: "\(hhmm(start))–\(hhmm(end))",
                numericValue: String(format: "%.1fh", hours)
            )]
        } else if hours > 9.5 {
            return [HealthInsight(
                kind: .sleepWindow, severity: .info,
                title: "睡眠偏长",
                detail: "参考 7-9h，可能处于恢复期",
                timestampRange: "\(hhmm(start))–\(hhmm(end))",
                numericValue: String(format: "%.1fh", hours)
            )]
        }
        return []
    }

    // MARK: - 工具

    private func hhmm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - HRV (心率变异性 — 压力指标)

    private func detectHRV(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let vals = snaps.compactMap { $0.heartRateVariability }.filter { $0 > 0 }
        guard vals.count >= 10 else { return [] }
        let avg = vals.reduce(0, +) / Double(vals.count)
        if avg < 20 {
            return [HealthInsight(
                kind: .lowHeartRate, severity: .warn,
                title: "HRV 偏低", detail: "压力可能较大, 建议放松或深呼吸",
                timestampRange: "今日全天", numericValue: "avg \(Int(avg)) ms"
            )]
        }
        return []
    }

    // MARK: - 站立小时 (苹果手表指标)

    private func detectStandHours(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let last = snaps.last(where: { $0.standHours != nil })
        guard let stand = last?.standHours else { return [] }
        let now = Date(); let h = Calendar.current.component(.hour, from: now)
        if h >= 12 && stand < 6 {
            return [HealthInsight(
                kind: .sedentary, severity: .warn,
                title: "站立小时不足", detail: "苹果手表建议每小时站立 1 分钟",
                timestampRange: "截至现在", numericValue: "\(stand) / 12 小时"
            )]
        }
        return []
    }

    // MARK: - 锻炼时间

    private func detectExerciseTime(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let last = snaps.last(where: { $0.exerciseMinutes != nil })
        guard let mins = last?.exerciseMinutes else { return [] }
        if mins < 30 {
            return [HealthInsight(
                kind: .lowSteps, severity: .info,
                title: "今日锻炼时间偏少", detail: "WHO 建议成人每日 ≥ 30 分钟中等强度运动",
                timestampRange: "今日", numericValue: String(format: "%.0f 分钟", mins)
            )]
        }
        return []
    }

    // MARK: - 距离 / 楼层

    private func detectDistance(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let total = snaps.compactMap { $0.distance }.reduce(0, +)
        let flights = snaps.compactMap { $0.flightsClimbed }.reduce(0, +)
        guard total > 0 || flights > 0 else { return [] }
        var out: [HealthInsight] = []
        if total > 0 {
            let km = total / 1000.0
            out.append(HealthInsight(
                kind: .active, severity: .info,
                title: "今日步行距离", detail: "包含户外与室内",
                timestampRange: "今日", numericValue: String(format: "%.2f km", km)
            ))
        }
        if flights > 0 {
            out.append(HealthInsight(
                kind: .active, severity: .info,
                title: "今日爬楼层", detail: "爬楼梯是一种高强度有氧",
                timestampRange: "今日", numericValue: "\(flights) 层"
            ))
        }
        return out
    }

    // MARK: - 呼吸频率

    private func detectRespiratory(_ snaps: [HealthSnapshot]) -> [HealthInsight] {
        let vals = snaps.compactMap { $0.respiratoryRate }.filter { $0 > 0 }
        guard vals.count >= 5 else { return [] }
        let avg = vals.reduce(0, +) / Double(vals.count)
        if avg < 12 || avg > 25 {
            return [HealthInsight(
                kind: .generic, severity: .info,
                title: "呼吸频率异常", detail: "正常成人 12-20 次/分",
                timestampRange: "今日", numericValue: String(format: "%.0f 次/分", avg)
            )]
        }
        return []
    }
}
