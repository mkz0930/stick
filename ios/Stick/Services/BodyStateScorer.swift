import Foundation

struct BodyStateScore {
    let gaitScore: Int
    let sleepScore: Int
    let sedentaryScore: Int
    let total: Int
}

final class BodyStateScorer {
    static let shared = BodyStateScorer()

    /// 步态评分：base 80，速度 1.0-1.4 +10，双脚支撑 25-33% +10，夜间清醒每次 -3
    func computeGaitScore(speed: Double?, doubleSupport: Double?, nightWakeCount: Int) -> Int {
        var score = 80
        if let s = speed, s >= 1.0 && s <= 1.4 { score += 10 }
        if let ds = doubleSupport, ds >= 25 && ds <= 33 { score += 10 }
        score -= nightWakeCount * 3
        return max(0, min(100, score))
    }

    /// 睡眠评分：时长 + 质量
    func computeSleepScore(minutes: Int, quality: String) -> Int {
        let hour = Double(minutes) / 60.0
        let durationScore: Int
        if hour < 5 { durationScore = 40 }
        else if hour < 6 { durationScore = 60 }
        else if hour < 7 { durationScore = 80 }
        else if hour <= 9 { durationScore = 100 }
        else { durationScore = 80 }

        let qualityScore: Int
        switch quality {
        case "连续": qualityScore = 100
        case "轻度中断": qualityScore = 80
        case "中断": qualityScore = 60
        case "碎片化": qualityScore = 40
        default: qualityScore = 60
        }
        return (durationScore + qualityScore) / 2
    }

    /// 久坐评分
    func computeSedentaryScore(minutes: Int) -> Int {
        if minutes < 60 { return 100 }
        else if minutes < 120 { return 80 }
        else if minutes < 240 { return 60 }
        else { return 30 }
    }

    /// 综合得分 = gait×0.4 + sleep×0.3 + sedentary×0.3
    func compute(gait: Int, sleep: Int, sedentary: Int) -> Int {
        return gait * 40 / 100 + sleep * 30 / 100 + sedentary * 30 / 100
    }

    /// 计算恢复指数（基于HRV和静息心率）
    /// - higher HRV = better recovery
    /// - lower resting HR (vs personal baseline) = better fitness
    /// - Returns 0-100 (higher = better recovery)
    func computeRecoveryScore(
        hrv: Double?,
        restingHR: Double?,
        baselineHRV: Double? = nil,
        baselineRHR: Double? = nil
    ) -> Int {
        var score = 60  // Base score

        // HRV bonus: higher HRV indicates better recovery
        if let hrv = hrv {
            if hrv > 40 { score += 20 }
            else if hrv > 30 { score += 10 }
            else if hrv < 20 { score -= 10 }
        }

        // Resting HR bonus: lower RHR indicates better fitness
        if let rhr = restingHR {
            if let baseline = baselineRHR {
                // Compare to personal baseline
                let delta = rhr - baseline
                if delta < -5 { score += 20 }
                else if delta < 0 { score += 10 }
                else if delta > 10 { score -= 10 }
            } else {
                // Absolute value comparison
                if rhr < 60 { score += 20 }
                else if rhr < 70 { score += 10 }
                else if rhr > 80 { score -= 10 }
            }
        }

        return max(0, min(100, score))
    }
}
