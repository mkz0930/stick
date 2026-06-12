//
//  AIRiskAnalyzer.swift
//  实时风险分析 — 检测到「晚间走路 + 心率过高」时输出 AI 风格的健康报告
//
//  触发条件 (合成示例)：
//    - state == .walk
//    - 1080 <= minute < 1320 (晚间 18:00–22:00)
//    - heartRate > 115 (高于走路常态 95–110 区间)
//
//  实际接入 HealthKit 后只需替换 currentHeartRate 来源。
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

    /// 1 句话结论（"你正在以高于基线 60% 的强度行走..."）
    let headline: String
    /// 时间戳 (供 UI 显示 "周四 19:14")
    let timestamp: Date
    /// 当前心率
    let heartRate: Int
    /// 静息基线
    let restingHR: Int
    /// 风险等级
    let risk: Risk
    /// 多条分析原因 (3–5 条)
    let reasons: [String]
    /// 行动建议 (3–4 条，按优先级)
    let recommendations: [String]
    /// 持续高心率分钟数（合成）
    let sustainedMinutes: Int
    /// 较 7 日同时段均值偏离 (%)
    let deviationPct: Int
    /// HRV (ms)
    let hrv: Int
}

enum AIRiskAnalyzer {

    /// 阈值（合成）
    private static let restingHR: Int = 65
    private static let lowThreshold: Int = 115
    private static let highThreshold: Int = 135

    /// 主入口：给定当前 state + 当前时间 + 心率，返回报告；不满足触发条件时返回 nil
    static func analyze(
        state: StickState,
        heartRate: Int,
        at date: Date,
        sustainedMinutes: Int = 6,
        hrv: Int = 28,
        avg7d: Int = 110
    ) -> AIAnalysisReport? {
        let m = StickState.minutesOfDay(date)
        // 触发条件：晚上走路 + 心率超阈值
        guard state == .walk, m >= 1080, m < 1320 else { return nil }
        guard heartRate > lowThreshold else { return nil }

        let risk: AIAnalysisReport.Risk
        if heartRate >= highThreshold { risk = .high }
        else if heartRate >= 125 { risk = .moderate }
        else { risk = .low }

        let delta = heartRate - restingHR
        let pctVsBase = Int((Double(heartRate - restingHR) / Double(restingHR) * 100).rounded())
        let devPct = Int(((Double(heartRate) - Double(avg7d)) / Double(avg7d) * 100).rounded())

        let headline = headline(risk: risk, delta: delta, m: m)
        let reasons = buildReasons(state: state, hr: heartRate, hrv: hrv,
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

    // MARK: - 合成

    private static func headline(risk: AIAnalysisReport.Risk, delta: Int, m: Int) -> String {
        let timeText = StickState.formatMinute(m)
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
        state: StickState, hr: Int, hrv: Int,
        sustained: Int, devPct: Int, m: Int
    ) -> [String] {
        var rs: [String] = []
        rs.append("心率 \(hr) bpm，已持续 ≥ \(sustained) 分钟超出 115 警戒线")
        rs.append("较 7 日同时段均值偏离 \(devPct >= 0 ? "+" : "")\(devPct)%")
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
