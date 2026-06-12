//
//  AlertAggregator.swift
//  统一异常面板 — 把 AI 实时风险、HealthAnalyzer 历史洞察、参考睡眠异常等
//  所有来源的"非正常状态"聚合成一个统一列表，供主页一次性展示。
//

import Foundation
import SwiftUI

/// 统一异常条目
struct UnifiedAlert: Identifiable, Equatable {
    enum Source: String {
        case heartRate, posture, activity, sleep, mood, respiratory, generic
    }
    enum Severity {
        case info, warn, alert

        var color: Color {
            switch self {
            case .info:  return Color(red: 0.30, green: 0.55, blue: 0.85)
            case .warn:  return Color(red: 0.92, green: 0.55, blue: 0.20)
            case .alert: return Color(red: 0.90, green: 0.25, blue: 0.25)
            }
        }
        var label: String {
            switch self {
            case .info:  return "提示"
            case .warn:  return "警告"
            case .alert: return "异常"
            }
        }
    }

    let id = UUID()
    let source: Source
    let severity: Severity
    let title: String
    let detail: String
    let timestampRange: String?
    let numericValue: String?
    let icon: String
    /// 关联的 AI 实时报告（晚间心率风险场景下会有）
    let aiReport: AIAnalysisReport?
    /// 用于点击跳转的标志 (AI 报告 / 通用)
    let kind: Kind

    enum Kind: Equatable {
        case aiLive
        case generic
    }

    static func == (lhs: UnifiedAlert, rhs: UnifiedAlert) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
enum AlertAggregator {

    /// 聚合所有异常：AI 实时 + HealthAnalyzer 历史 + 隐含推断
    /// 只保留 severity >= warn 的项
    static func aggregate(
        snapshots: [HealthSnapshot],
        aiReport: AIAnalysisReport?
    ) -> [UnifiedAlert] {
        var alerts: [UnifiedAlert] = []

        // 1) AI 实时风险报告（最优先，最显眼）
        if let r = aiReport {
            let severity: UnifiedAlert.Severity = {
                switch r.risk {
                case .high:     return .alert
                case .moderate: return .warn
                case .low:      return .info
                }
            }()
            alerts.append(UnifiedAlert(
                source: .heartRate,
                severity: severity,
                title: "实时心率 \(r.heartRate) bpm · \(r.risk.label)度风险",
                detail: r.headline,
                timestampRange: StickState.formatMinute(StickState.minutesOfDay(r.timestamp)),
                numericValue: "\(r.heartRate) bpm",
                icon: "waveform.path.ecg.rectangle.fill",
                aiReport: r,
                kind: .aiLive
            ))
        }

        // 2) HealthAnalyzer 历史洞察（含睡眠异常）
        let insights = HealthAnalyzer.shared.analyze(snapshots: snapshots)
        for i in insights where i.severity != .info {
            alerts.append(UnifiedAlert(
                source: sourceOf(i.kind),
                severity: severityOf(i.severity),
                title: i.title,
                detail: i.detail,
                timestampRange: i.timestampRange,
                numericValue: i.numericValue,
                icon: iconOf(i.kind),
                aiReport: nil,
                kind: .generic
            ))
        }

        // 3) 按 severity (alert > warn > info) + 时间排序
        return alerts.sorted { lhs, rhs in
            sevRank(lhs.severity) > sevRank(rhs.severity)
        }
    }

    // MARK: - 映射

    private static func sourceOf(_ k: HealthInsight.Kind) -> UnifiedAlert.Source {
        switch k {
        case .sedentary, .active, .lowSteps: return .activity
        case .lowHeartRate, .highHeartRate:  return .heartRate
        case .sleepWindow:                   return .sleep
        case .hydration, .generic:           return .generic
        }
    }

    private static func severityOf(_ s: HealthInsight.Severity) -> UnifiedAlert.Severity {
        switch s {
        case .info:  return .info
        case .warn:  return .warn
        case .alert: return .alert
        }
    }

    private static func iconOf(_ k: HealthInsight.Kind) -> String {
        switch k {
        case .sedentary:     return "figure.seated.side"
        case .active:        return "figure.walk"
        case .lowHeartRate:  return "heart.slash"
        case .highHeartRate: return "heart.fill"
        case .sleepWindow:   return "bed.double.fill"
        case .lowSteps:      return "figure.walk.motion"
        case .hydration:     return "drop.fill"
        case .generic:       return "exclamationmark.triangle.fill"
        }
    }

    private static func sevRank(_ s: UnifiedAlert.Severity) -> Int {
        switch s {
        case .alert: return 3
        case .warn:  return 2
        case .info:  return 1
        }
    }
}
