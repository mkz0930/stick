//
//  RealHealthAnalyzer.swift
//  基于真实 HealthKit 数据做异常分析 — 只有数据真的异常才会触发提醒
//  取代之前基于"tiredness（时间+姿态估算）"的硬编码分析
//

import Foundation
import SwiftUI

/// 异常风险等级
enum RealHealthRisk: Int, Comparable {
    case normal = 0    // 数据都正常
    case low = 1       // 1 项轻度异常
    case medium = 2     // 2 项异常 或 1 项中度
    case high = 3       // 3+ 项异常 或 1 项重度

    static func < (lhs: RealHealthRisk, rhs: RealHealthRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .normal: return "正常"
        case .low:    return "轻度"
        case .medium: return "中度"
        case .high:   return "高风险"
        }
    }

    var color: Color {
        switch self {
        case .normal: return Theme.stateWalk
        case .low:    return Theme.stateStand
        case .medium: return Theme.stateSit
        case .high:   return Theme.riskHigh
        }
    }
}

/// 一条异常发现
struct HealthFinding: Identifiable {
    let id = UUID()
    let metric: String       // "久坐时长"
    let value: String        // "95 分钟"
    let threshold: String    // "> 90 分钟属异常"
    let severity: RealHealthRisk
    let suggestion: String   // 简短建议
}

/// 真实数据分析结果
struct RealHealthReport {
    let risk: RealHealthRisk
    let findings: [HealthFinding]
    let keyMetrics: [(label: String, value: String, isAbnormal: Bool)]
    let analysisText: String
    let recommendations: [String]
    let dataCompleteness: Double  // 0..1 反映数据完整度
}

/// 基于真实 HealthKit 数据的异常分析
@MainActor
final class RealHealthAnalyzer {
    static let shared = RealHealthAnalyzer()

    /// 异常阈值
    struct Thresholds {
        // 久坐
        static let sedentaryCautionMin: Int = 60      // 60 分钟提示
        static let sedentaryWarningMin: Int = 90      // 90 分钟警告
        static let sedentaryCriticalMin: Int = 120    // 120 分钟严重

        // 心率（bpm）
        static let hrRestingHigh: Double = 85        // 静息心率偏高
        static let hrRestingCritical: Double = 95
        static let hrActiveHigh: Double = 110        // 活动时心率偏高
        static let hrActiveCritical: Double = 130

        // HRV (ms) — 越低越差
        static let hrvLowCaution: Double = 40
        static let hrvLowCritical: Double = 25

        // 步数
        static let stepsLow: Int = 3000      // 低于 3000 步属久坐
        static let stepsVeryLow: Int = 1000   // 严重不足

        // 睡眠（小时）
        static let sleepShortCaution: Double = 6.5
        static let sleepShortCritical: Double = 5.0
    }

    /// 从真实快照 + 当天数据生成分析报告
    func analyze() -> RealHealthReport {
        let snapshots = HealthStore.shared.today
        let today = Date()

        var findings: [HealthFinding] = []
        var keyMetrics: [(String, String, Bool)] = []
        var completeness: Double = 0
        var checkCount = 0

        // MARK: 1. 当前连续久坐时长
        checkCount += 1
        let sitMins = computeCurrentSedentaryMinutes()
        if sitMins > 0 {
            let isAbnormal = sitMins >= Thresholds.sedentaryCautionMin
            let valueStr = "\(sitMins) 分钟"
            keyMetrics.append(("当前连续久坐", valueStr, isAbnormal))
            if isAbnormal {
                let severity: RealHealthRisk = sitMins >= Thresholds.sedentaryCriticalMin ? .high
                    : sitMins >= Thresholds.sedentaryWarningMin ? .medium
                    : .low
                let threshold = sitMins >= Thresholds.sedentaryCriticalMin ? "≥ 120 分钟属高风险"
                    : sitMins >= Thresholds.sedentaryWarningMin ? "≥ 90 分钟属中度"
                    : "≥ 60 分钟需起身"
                findings.append(HealthFinding(
                    metric: "连续久坐", value: valueStr, threshold: threshold,
                    severity: severity,
                    suggestion: severity == .high
                        ? "立刻起身 5 分钟，做扩胸+深蹲激活肌肉"
                        : "起来走动 2-3 分钟，让血液恢复"
                ))
            }
            completeness += 1
        } else {
            keyMetrics.append(("当前连续久坐", "0 分钟（不在久坐）", false))
        }

        // MARK: 2. 今日累计久坐
        checkCount += 1
        let todaySitMin = todaySitMinutes(snapshots: snapshots)
        keyMetrics.append(("今日累计久坐", "\(todaySitMin) 分钟", todaySitMin >= 240))
        if todaySitMin >= 240 {
            findings.append(HealthFinding(
                metric: "今日累计久坐", value: "\(todaySitMin) 分钟", threshold: "≥ 4 小时高风险",
                severity: todaySitMin >= 360 ? .high : .medium,
                suggestion: "中间穿插站立/散步 5-10 分钟"
            ))
        }
        completeness += 1

        // MARK: 3. 心率（最近）
        checkCount += 1
        let recentHR = computeRecentHeartRate(snapshots: snapshots)
        if let hr = recentHR {
            let restingHR = computeRestingHeartRate(snapshots: snapshots)
            keyMetrics.append(("当前心率", "\(Int(hr)) bpm", hr > Thresholds.hrActiveHigh))
            // 判断是静息态还是活动态
            if let rHR = restingHR, hr - rHR > 15 {
                // 活动态
                if hr > Thresholds.hrActiveCritical {
                    findings.append(HealthFinding(
                        metric: "心率异常", value: "\(Int(hr)) bpm", threshold: "活动时 > 130 bpm",
                        severity: .high,
                        suggestion: "立即降低运动强度，慢走恢复"
                    ))
                } else if hr > Thresholds.hrActiveHigh {
                    findings.append(HealthFinding(
                        metric: "心率偏高", value: "\(Int(hr)) bpm", threshold: "活动时 > 110 bpm",
                        severity: .medium,
                        suggestion: "放慢节奏，做几次深呼吸"
                    ))
                }
            } else if let rHR = restingHR, rHR > Thresholds.hrRestingCritical {
                findings.append(HealthFinding(
                    metric: "静息心率过高", value: "\(Int(rHR)) bpm", threshold: "> 95 bpm",
                    severity: .high,
                    suggestion: "近期压力大/睡眠不足，建议今晚早睡"
                ))
            } else if let rHR = restingHR, rHR > Thresholds.hrRestingHigh {
                findings.append(HealthFinding(
                    metric: "静息心率偏高", value: "\(Int(rHR)) bpm", threshold: "> 85 bpm",
                    severity: .low,
                    suggestion: "注意放松，今晚保证 7h 睡眠"
                ))
            }
            completeness += 1
        }

        // MARK: 4. HRV
        checkCount += 1
        let hrv = computeRecentHRV(snapshots: snapshots)
        if let hrvVal = hrv {
            keyMetrics.append(("HRV", "\(Int(hrvVal)) ms", hrvVal < Thresholds.hrvLowCaution))
            if hrvVal < Thresholds.hrvLowCritical {
                findings.append(HealthFinding(
                    metric: "HRV 偏低", value: "\(Int(hrvVal)) ms", threshold: "< 25 ms 压力大",
                    severity: .high,
                    suggestion: "副交感神经疲劳，今晚务必早睡 + 远离屏幕"
                ))
            } else if hrvVal < Thresholds.hrvLowCaution {
                findings.append(HealthFinding(
                    metric: "HRV 偏低", value: "\(Int(hrvVal)) ms", threshold: "< 40 ms 需关注",
                    severity: .medium,
                    suggestion: "本周增加散步/拉伸，避免高强度运动"
                ))
            }
            completeness += 1
        }

        // MARK: 5. 今日步数
        checkCount += 1
        let steps = todayTotalSteps(snapshots: snapshots)
        let hour = Calendar.current.component(.hour, from: today)
        if hour >= 14 {  // 下午 2 点后才判断步数
            let isLow = steps < Thresholds.stepsLow
            let isVeryLow = steps < Thresholds.stepsVeryLow
            keyMetrics.append(("今日步数", "\(steps) 步", isLow))
            if isVeryLow {
                findings.append(HealthFinding(
                    metric: "步数严重不足", value: "\(steps) 步", threshold: "< 1000 步极度久坐",
                    severity: .high,
                    suggestion: "出门走 20 分钟，今晚补 5000+ 步"
                ))
            } else if isLow {
                findings.append(HealthFinding(
                    metric: "步数偏低", value: "\(steps) 步", threshold: "< 3000 步活动不足",
                    severity: .low,
                    suggestion: "下楼走两圈，今天补到 5000 步"
                ))
            }
            completeness += 1
        } else {
            keyMetrics.append(("今日步数", "\(steps) 步（早上数据还少）", false))
        }

        // MARK: 计算综合风险
        let risk = computeOverallRisk(findings: findings)
        // checkCount > 0 时必有 completeness >= 0；checkCount == 0 表示所有检查被跳过（如刚装 app 无数据），则 completeness 也为 0，除零保护
        let dataComp = checkCount > 0 ? Double(completeness) / Double(checkCount) : 0

        // MARK: 生成分析文本
        let analysis = generateAnalysis(risk: risk, findings: findings, dataComp: dataComp)
        let recs = generateRecommendations(risk: risk, findings: findings)

        return RealHealthReport(
            risk: risk,
            findings: findings,
            keyMetrics: keyMetrics,
            analysisText: analysis,
            recommendations: recs,
            dataCompleteness: dataComp
        )
    }

    // MARK: - 私有计算

    private func computeCurrentSedentaryMinutes() -> Int {
        let now = Date()
        let cutoff = now.addingTimeInterval(-4 * 3600)
        let snapshots = HealthStore.shared.today.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
        guard !snapshots.isEmpty else { return 0 }

        let restingHR = snapshots.compactMap { $0.restingHeartRate }.last

        var minutes = 0
        for snap in snapshots {
            // 睡眠时段不算久坐
            if snap.bodyState == "sleep" { break }
            // 起身走动（增量步数 > 5）中断 session
            if snap.incrementalStepCount > 5 { break }
            // 心率高于基线 15+ 说明在活动
            if let rHR = restingHR, let hr = snap.heartRate, hr - rHR > 15 { break }
            minutes += 1
        }
        return minutes
    }

    private func todaySitMinutes(snapshots: [HealthSnapshot]) -> Int {
        snapshots.filter { $0.bodyState == "sit" }.count
    }

    private func computeRecentHeartRate(snapshots: [HealthSnapshot]) -> Double? {
        let recent = Array(snapshots.suffix(5))
        let hrs = recent.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / Double(hrs.count)
    }

    private func computeRestingHeartRate(snapshots: [HealthSnapshot]) -> Double? {
        // 取最旧的 30 条快照里最小的 HR（早上起床时最接近静息）
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        let earlySnapshots = Array(sorted.prefix(30))
        let hrs = earlySnapshots.compactMap { $0.heartRate }
        // 优先用 Apple Watch 测的静息心率字段
        let rhr = snapshots.compactMap { $0.restingHeartRate }.last
        return rhr ?? (hrs.min())
    }

    private func computeRecentHRV(snapshots: [HealthSnapshot]) -> Double? {
        let recent = Array(snapshots.suffix(10))
        let vals = recent.compactMap { $0.heartRateVariability }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func todayTotalSteps(snapshots: [HealthSnapshot]) -> Int {
        // 用最大的累计步数（cumulativeStepCount 最大值）
        return snapshots.compactMap { $0.cumulativeStepCount }.max() ?? 0
    }

    private func computeOverallRisk(findings: [HealthFinding]) -> RealHealthRisk {
        if findings.isEmpty { return .normal }
        if findings.contains(where: { $0.severity == .high }) { return .high }
        let highCount = findings.filter { $0.severity == .medium }.count
        if highCount >= 2 { return .high }
        if highCount >= 1 { return .medium }
        return .low
    }

    private func generateAnalysis(risk: RealHealthRisk, findings: [HealthFinding], dataComp: Double) -> String {
        if findings.isEmpty {
            return "📊 当前真实数据未发现异常。\n\n心率稳定，久坐时长在健康范围，HRV 和步数都正常。继续保持当前作息即可。"
        }
        if dataComp < 0.4 {
            return "⚠️ 数据不足：当前可分析的 HealthKit 指标较少，结论仅供参考。建议佩戴 Apple Watch 或打开 iPhone 健康 App 持续记录。\n\n\(findings.map { "• \($0.metric)：\($0.value) — \($0.threshold)" }.joined(separator: "\n"))"
        }
        let parts = findings.prefix(3).map { "• \($0.metric) \($0.value) — \($0.threshold)" }
        switch risk {
        case .high:
            return "🚨 多项指标异常，建议优先处理：\n\n" + parts.joined(separator: "\n")
        case .medium:
            return "⚠️ 检测到以下异常：\n\n" + parts.joined(separator: "\n")
        case .low:
            return "📍 轻度异常：\n\n" + parts.joined(separator: "\n")
        case .normal:
            return "数据正常"
        }
    }

    private func generateRecommendations(risk: RealHealthRisk, findings: [HealthFinding]) -> [String] {
        if findings.isEmpty {
            return [
                "保持当前活动节律，每小时起身一次",
                "继续监测，异常会自动提醒",
            ]
        }
        // 优先按 severity 排序，取前 4 条
        let sorted = findings.sorted { $0.severity.rawValue > $1.severity.rawValue }
        return Array(sorted.prefix(4).map { $0.suggestion })
    }
}
