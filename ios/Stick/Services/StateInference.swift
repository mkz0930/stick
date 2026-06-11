//
//  StateInference.swift
//  多信号融合推断身体状态 — 替代单一时段粗判
//
//  信号来源:
//   - 步数 (最近 5 分钟)
//   - 心率 (当前 / 静息基线)
//   - HRV (可选)
//   - 时段 (睡眠窗口 22:00-07:00)
//
//  输出: walk / sit / sleep + 置信度
//

import Foundation

struct StateInference {

    enum State: String { case walk, sit, sleep }

    struct Result {
        let state: State
        let confidence: Double       // 0–1
        let reasons: [String]        // 解释 (调试 / UI 副标)
    }

    /// 推断 (主入口)
    static func infer(snapshots: [HealthSnapshot], restingHR: Double? = nil) -> Result {
        // 取最近 5 条 (≈ 5 分钟)
        let recent = Array(snapshots.suffix(5))
        guard !recent.isEmpty else {
            return Result(state: .sit, confidence: 0.3, reasons: ["无数据"])
        }

        // 1) 步数 (最近 5 分钟总和)
        let recentSteps = recent.compactMap { $0.stepCount }.reduce(0, +)
        // 2) 当前心率
        let currentHR = recent.last?.heartRate
        // 3) HRV
        let hrv = recent.compactMap { $0.heartRateVariability }.filter { $0 > 0 }.last
        // 4) 呼吸
        let resp = recent.compactMap { $0.respiratoryRate }.filter { $0 > 0 }.last

        let now = Date()
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)

        var score: [State: Double] = [.walk: 0, .sit: 0, .sleep: 0]
        var reasons: [String] = []

        // === A. 时段基线 (睡眠窗口) ===
        if h >= 22 || h < 7 {
            score[.sleep]! += 1.5
            reasons.append("睡眠时段 \(h):00")
        } else if (11 <= h && h <= 13) || h == 18 {
            score[.walk]! += 0.3   // 午饭/晚饭散步
            reasons.append("用餐时段")
        }

        // === B. 步数信号 (强信号) ===
        if recentSteps > 30 {
            score[.walk]! += 3.0
            reasons.append("5min 步数 \(recentSteps) (强)")
        } else if recentSteps > 5 {
            score[.walk]! += 1.5
            reasons.append("5min 步数 \(recentSteps) (弱)")
        } else if recentSteps == 0 {
            score[.sit]! += 1.0
            score[.sleep]! += 0.5   // 0 步 + 睡眠时段 = 强 sleep
        }

        // === C. 心率信号 ===
        if let hr = currentHR {
            let rhr = restingHR ?? 65.0
            let delta = hr - rhr
            if hr < 55 {
                // 深度休息/睡眠
                score[.sleep]! += 2.0
                reasons.append("HR \(Int(hr)) < 55")
            } else if delta > 20 {
                // 明显高于基线 → 活动
                score[.walk]! += 2.0
                reasons.append("HR \(Int(hr)) > RHR+\(Int(delta))")
            } else if delta > 10 {
                // 略高于基线 → 轻度活动
                score[.walk]! += 0.8
            } else if abs(delta) <= 10 {
                // 接近基线 → 静息
                score[.sit]! += 1.5
                reasons.append("HR 接近基线")
            }
        }

        // === D. HRV 信号 ===
        if let h = hrv, h > 0 {
            if h > 60 {
                score[.sleep]! += 0.5   // 高 HRV = 恢复态
            } else if h < 20 {
                score[.sit]! += 0.5   // 低 HRV = 压力
            }
        }

        // === E. 呼吸 ===
        if let r = resp, r > 0 {
            if r < 14 {
                score[.sleep]! += 0.5
            } else if r > 20 {
                score[.walk]! += 0.3
            }
        }

        // === F. 决策 ===
        let best = score.max(by: { $0.value < $1.value })!
        let totalScore = score.values.reduce(0, +)
        let confidence = totalScore > 0 ? min(1.0, best.value / max(totalScore, 5)) : 0.3

        return Result(
            state: best.key,
            confidence: confidence,
            reasons: reasons
        )
    }

    // MARK: - 单条快照推断 (无历史)

    static func inferSingle(_ snap: HealthSnapshot, restingHR: Double? = nil) -> Result {
        infer(snapshots: [snap], restingHR: restingHR)
    }
}
