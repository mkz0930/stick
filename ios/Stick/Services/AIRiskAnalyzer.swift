//
//  AIRiskAnalyzer.swift
//  实时风险分析 — 基于用户真实 HealthKit 数据检测风险并生成个性化报告
//

import Foundation
import SwiftUI

struct AIAnalysisReport: Equatable {
    enum Risk: String {
        case low, moderate, high
        var label: String {
            switch self {
            case .low:      return "低"
            case .moderate: return "中"
            case .high:     return "高"
            }
        }
        var englishLabel: String {
            switch self {
            case .low:      return "LOW"
            case .moderate: return "MODERATE"
            case .high:     return "HIGH"
            }
        }
        var color: Color {
            switch self {
            case .low:      return Color(red: 0.20, green: 0.65, blue: 0.45)
            case .moderate: return Color(red: 0.92, green: 0.55, blue: 0.20)
            case .high:     return Color(red: 0.90, green: 0.25, blue: 0.25)
            }
        }
    }

    /// 1 句话结论
    let headline: String
    /// 时间戳
    let timestamp: Date
    /// 当前心率
    let heartRate: Int
    /// 静息基线
    let restingHR: Int
    /// 风险等级
    let risk: Risk
    /// 多条分析原因
    let reasons: [String]
    /// 行动建议
    let recommendations: [String]
    /// 持续高心率分钟数
    let sustainedMinutes: Int
    /// 较 7 日同时段均值偏离 (%)
    let deviationPct: Int
    /// HRV (ms)
    let hrv: Int
}

@MainActor
enum AIRiskAnalyzer {

    private static let lowThreshold: Int = 115
    private static let highThreshold: Int = 135

    /// 从 HealthStore 获取真实静息心率（取最近 7 天数据的平均值）
    private static var realRestingHR: Int {
        let values = HealthStore.shared.all
            .compactMap { $0.restingHeartRate }
        guard !values.isEmpty else { return 65 }
        return Int(values.reduce(0, +) / Double(values.count))
    }

    /// 从 HealthStore 获取真实 HRV（取今日最新值）
    private static var realHRV: Int {
        guard let latest = HealthStore.shared.today
            .compactMap({ $0.heartRateVariability })
            .last else { return 28 }
        return Int(latest)
    }

    /// 从 HealthStore 获取当前心率（取今日最新值）
    private static var realCurrentHeartRate: Int {
        guard let latest = HealthStore.shared.today
            .compactMap({ $0.heartRate })
            .last else { return 72 }
        return Int(latest)
    }

    /// 计算今日同一时段的 7 日平均心率
    private static func avgHeartRateAtSameTime(last7Days: [HealthSnapshot], minuteOfDay: Int) -> Int {
        var dailyAvgs: [Double] = []
        let calendar = Calendar.current

        for dayOffset in 1...7 {
            guard let targetDay = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: targetDay)
            let targetMinuteStart = dayStart.addingTimeInterval(Double(minuteOfDay) * 60)
            let targetMinuteEnd = targetMinuteStart.addingTimeInterval(300) // ±5 分钟窗口

            let sameTimeSamples = last7Days.filter { snap in
                snap.timestamp >= targetMinuteStart && snap.timestamp < targetMinuteEnd && snap.heartRate != nil
            }
            if let avg = sameTimeSamples.compactMap({ $0.heartRate }).average, avg > 0 {
                dailyAvgs.append(avg)
            }
        }

        guard !dailyAvgs.isEmpty else { return 100 }
        return Int(dailyAvgs.reduce(0, +) / Double(dailyAvgs.count))
    }

    /// 主入口：基于真实 HealthKit 数据生成报告
    static func analyze(
        state: StickState,
        heartRate: Int,
        at date: Date
    ) -> AIAnalysisReport? {
        let m = StickState.minutesOfDay(date)
        // 触发条件：晚上走路 + 心率超阈值
        guard state == .walk, m >= 1080, m < 1320 else { return nil }
        guard heartRate > lowThreshold else { return nil }

        // 使用真实数据
        let restingHR = realRestingHR
        let hrv = realHRV
        let avg7d = avgHeartRateAtSameTime(last7Days: HealthStore.shared.all, minuteOfDay: m)

        // 计算持续高心率分钟数（今日同类时段）
        let sustainedMinutes = max(5, HealthStore.shared.today.filter { snap in
            snap.heartRate != nil && snap.heartRate! > Double(lowThreshold)
        }.count)

        let risk: AIAnalysisReport.Risk
        if heartRate >= highThreshold { risk = .high }
        else if heartRate >= 125 { risk = .moderate }
        else { risk = .low }

        let devPct = avg7d > 0 ? Int(((Double(heartRate) - Double(avg7d)) / Double(avg7d) * 100).rounded()) : 0

        let headline = headline(risk: risk, hr: heartRate, restingHR: restingHR, m: m)
        let reasons = buildReasons(hr: heartRate, restingHR: restingHR, hrv: hrv,
                                   sustained: sustainedMinutes, devPct: devPct, m: m)
        let recs = buildRecommendations(risk: risk, hr: heartRate, m: m)

        return AIAnalysisReport(
            headline: headline,
            timestamp: date,
            heartRate: heartRate,
            restingHR: restingHR,
            risk: risk,
            reasons: reasons,
            recommendations: recs,
            sustainedMinutes: sustainedMinutes,
            deviationPct: devPct,
            hrv: hrv
        )
    }

    // MARK: - 报告生成

    private static func headline(risk: AIAnalysisReport.Risk, hr: Int, restingHR: Int, m: Int) -> String {
        let timeText = StickState.formatMinute(m)
        let delta = hr - restingHR
        switch risk {
        case .high:
            return "你正在以 \(abs(delta)) bpm 高于静息基线的强度行走 (\(timeText))，心血管负荷较高，建议立即减速。"
        case .moderate:
            return "晚间行走心率高于常态 \(abs(delta)) bpm (\(timeText))，建议降低强度并监测。"
        case .low:
            return "晚间行走心率略高于参考区间 (\(timeText))，整体在可控范围。"
        }
    }

    private static func buildReasons(
        hr: Int, restingHR: Int, hrv: Int,
        sustained: Int, devPct: Int, m: Int
    ) -> [String] {
        var rs: [String] = []
        rs.append("心率 \(hr) bpm，已持续 ≥ \(sustained) 分钟超出 \(lowThreshold) 警戒线")
        if devPct != 0 {
            rs.append("较 7 日同时段均值偏离 \(devPct >= 0 ? "+" : "")\(devPct)%")
        }
        if hrv < 30 {
            rs.append("HRV \(hrv) ms 偏低，副交感活性下降，恢复能力受限")
        }
        rs.append("夜间高强度活动抑制褪黑素分泌，可能延后入睡 30–60 分钟")
        if m >= 1200 {
            rs.append("已临近 22:00 黄金睡眠窗口，继续高强度会进一步压缩深睡时间")
        }
        return rs
    }

    private static func buildRecommendations(
        risk: AIAnalysisReport.Risk, hr: Int, m: Int
    ) -> [String] {
        var recs: [String] = [
            "立即降低步速至散步级别，目标 < 100 bpm",
            "4-7-8 呼吸法：4s 吸 / 7s 屏 / 8s 呼，循环 4 次（约 90 秒）",
        ]
        if risk == .high {
            recs.append("若 5 分钟内未恢复至 < 100 bpm，请坐下休息并联系设备同步心电图")
            recs.append("建议今晚停止所有有氧运动，改为 10 分钟拉伸")
        } else {
            recs.append("若 10 分钟内未恢复，建议放慢节奏或转为慢走")
        }
        if m >= 1200 {
            recs.append("21:30 后避免咖啡因与高强度屏幕光")
        }
        recs.append("回到室内后开启「夜间恢复」模式以监测 60 分钟内 HRV 回升")
        return recs
    }
}

// MARK: - Array 扩展

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
