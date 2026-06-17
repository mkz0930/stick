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

        // 1) 步数 (最近 5 分钟总和 = 5 个 incrementalStepCount 之和)
        // 旧版 bug: 把 5 个 cumulativeStepCount 求和 → 5x 膨胀（每条都是今日累计）
        let recentSteps = recent.reduce(0) { $0 + $1.incrementalStepCount }
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

        // === A. 时段基线 (睡眠窗口: 22-08 夜间 + 12-14 午睡) ===
        if h >= 22 || h < 8 {
            score[.sleep]! += 1.5
            reasons.append("睡眠时段 \(h):00 (夜间)")
        } else if h >= 12 && h < 14 {
            score[.sleep]! += 0.8
            reasons.append("午睡时段 \(h):00")
        } else if (11 <= h && h <= 13) || h == 18 {
            score[.walk]! += 0.3   // 午饭/晚饭散步
            reasons.append("用餐时段")
        }

        // === A2. 持续静止信号 (门控: 仅在睡眠窗口内才识别为 sleep) ===
        // 睡眠窗口: 22:00-08:00 (夜间) 或 12:00-14:00 (午睡)
        // 避免白天开会/看书/通勤中断被误识别为 sleep
        let inSleepWindow = (h >= 22 || h < 8) || (h >= 12 && h < 14)
        if inSleepWindow {
            let longWindow = Array(snapshots.suffix(30))
            if longWindow.count >= 20 {
                let zeroCount = longWindow.filter { $0.incrementalStepCount == 0 }.count
                let zeroRatio = Double(zeroCount) / Double(longWindow.count)
                if zeroRatio >= 0.9 {
                    score[.sleep]! += 2.5
                    reasons.append("持续 \(zeroCount)/\(longWindow.count) 分钟 0 步 (睡眠窗口)")
                } else if zeroRatio >= 0.7 {
                    score[.sleep]! += 1.0
                    reasons.append("长时间低活动 (\(Int(zeroRatio * 100))% 0 步, 睡眠窗口)")
                }
            }
        }

        // === B. 步数信号 (强信号) ===
        if recentSteps > 30 {
            score[.walk]! += 3.0
            reasons.append("5min 步数 \(recentSteps) (强)")
        } else if recentSteps > 10 {
            score[.walk]! += 1.5
            score[.sit]! += 0.5  // 有步数但不多，静坐也有可能
            reasons.append("5min 步数 \(recentSteps) (中)")
        } else if recentSteps > 0 {
            // 步数很少（<10），结合心率判断，不能仅靠步数判定走路
            score[.sit]! += 0.8
            reasons.append("5min 步数 \(recentSteps) (弱，静坐)")
        } else {
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
            } else if delta > 25 && recentSteps > 20 {
                // 心率明显升高 + 有足够步数 → 活动
                score[.walk]! += 2.5
                reasons.append("HR \(Int(hr)) 升高 +\(Int(delta)) + 步数支撑")
            } else if delta > 15 && recentSteps > 10 {
                // 心率略高 + 有步数 → 轻度活动
                score[.walk]! += 1.0
                reasons.append("HR 略高 +\(Int(delta))")
            } else if abs(delta) <= 10 && recentSteps < 5 {
                // 心率稳定 + 几乎没步数 → 久坐（最重要！）
                score[.sit]! += 2.0
                reasons.append("HR 稳定，久坐")
            } else if abs(delta) <= 10 {
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
        // score 字典始终有 3 个 key（.walk/.sit/.sleep），但用 guard 防御未来修改
        guard let best = score.max(by: { $0.value < $1.value }) else {
            return Result(state: .sit, confidence: 0.3, reasons: ["推理异常"])
        }
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
