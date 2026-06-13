import SwiftUI

// MARK: - 睡眠 AI 报告

/// AI 睡眠分析报告（合成）
struct AISleepReport: Equatable {
    enum Risk: String {
        case good, fair, poor

        var label: String {
            switch self {
            case .good: return "良好"
            case .fair: return "一般"
            case .poor: return "较差"
            }
        }
        var englishLabel: String {
            switch self {
            case .good: return "GOOD"
            case .fair: return "FAIR"
            case .poor: return "POOR"
            }
        }
        var color: Color {
            switch self {
            case .good: return Color(red: 0.20, green: 0.65, blue: 0.45)   // 绿
            case .fair: return Color(red: 0.92, green: 0.55, blue: 0.20)   // 橙
            case .poor: return Color(red: 0.90, green: 0.25, blue: 0.25)  // 红
            }
        }
        var icon: String {
            switch self {
            case .good: return "checkmark.seal.fill"
            case .fair: return "exclamationmark.triangle.fill"
            case .poor: return "xmark.octagon.fill"
            }
        }
    }

    /// 1 句话结论
    let headline: String
    /// 分析时间
    let timestamp: Date
    /// 睡眠质量
    let risk: Risk
    /// 关键指标 (用于卡片展示)
    let totalMinutes: Int
    let deepPct: Int        // 深睡占比 %
    let remPct: Int         // REM 占比 %
    let efficiency: Int     // 效率 %
    let awakenings: Int     // 醒来次数
    let hrv: Int            // HRV (ms)
    /// 较 7 日均值偏离
    let deviationPct: Int   // 总时长偏差 % (vs 7d avg)
    /// 多条分析原因 (3-5 条)
    let reasons: [String]
    /// 行动建议 (3-4 条)
    let recommendations: [String]
}

// MARK: - 睡眠 AI 分析器

enum AISleepAnalyzer {

    /// 阈值（合成）
    private static let deepPctLow: Int = 15
    private static let deepPctGood: Int = 20
    private static let efficiencyLow: Int = 80
    private static let efficiencyGood: Int = 88
    private static let awakeningsWarn: Int = 4
    private static let hrvLow: Int = 35
    private static let durationShort: Int = 6 * 60    // < 6h 算偏短
    private static let durationIdealLow: Int = 7 * 60
    private static let durationIdealHigh: Int = 9 * 60

    /// 主入口：给定 SleepSession + 元数据 → 报告（始终返回非 nil，UI 可决定是否显示）
    static func analyze(
        session: SleepSession,
        hrv: Int = 42,
        avg7dMinutes: Int = 7 * 60 + 30
    ) -> AISleepReport {
        let totalMin = session.totalMinutes
        let efficiency = Int((session.efficiency * 100).rounded())
        let breakdown = StageBreakdown(session)
        let total = max(1, breakdown.total)
        let deepPct = Int((Double(breakdown.deep) / Double(total) * 100).rounded())
        let remPct = Int((Double(breakdown.rem) / Double(total) * 100).rounded())
        let awakenings = session.segments.filter {
            $0.stage == .awake && $0.durationMinutes >= 1
        }.count

        // 综合 risk
        var riskScore = 0
        if totalMin < durationShort { riskScore += 3 }
        else if totalMin < durationIdealLow { riskScore += 1 }
        else if totalMin > durationIdealHigh { riskScore += 1 }

        if deepPct < deepPctLow { riskScore += 2 }
        else if deepPct < deepPctGood { riskScore += 1 }

        if efficiency < efficiencyLow { riskScore += 2 }
        else if efficiency < efficiencyGood { riskScore += 1 }

        if awakenings >= awakeningsWarn { riskScore += 1 }
        if hrv < hrvLow { riskScore += 1 }

        let risk: AISleepReport.Risk
        switch riskScore {
        case 0...2:  risk = .good
        case 3...4:  risk = .fair
        default:     risk = .poor
        }

        let devPct = Int(((Double(totalMin) - Double(avg7dMinutes)) / Double(avg7dMinutes) * 100).rounded())
        let h = totalMin / 60
        let m = totalMin % 60

        let headline = makeHeadline(risk: risk, hours: h, mins: m, efficiency: efficiency)
        let reasons = buildReasons(
            totalMin: totalMin, h: h, m: m,
            deepPct: deepPct, efficiency: efficiency,
            awakenings: awakenings, hrv: hrv,
            devPct: devPct, avg7d: avg7dMinutes
        )
        let recs = buildRecommendations(risk: risk, deepPct: deepPct, awakenings: awakenings)

        return AISleepReport(
            headline: headline,
            timestamp: Date(),
            risk: risk,
            totalMinutes: totalMin,
            deepPct: deepPct,
            remPct: remPct,
            efficiency: efficiency,
            awakenings: awakenings,
            hrv: hrv,
            deviationPct: devPct,
            reasons: reasons,
            recommendations: recs
        )
    }

    // MARK: - 合成

    private static func makeHeadline(risk: AISleepReport.Risk, hours: Int, mins: Int, efficiency: Int) -> String {
        let duration = "\(hours)h\(String(format: "%02d", mins))m"
        switch risk {
        case .good:
            return "昨晚 \(duration) 睡眠质量良好，深睡比例达标，今天精力有保障。"
        case .fair:
            return "昨晚 \(duration) 睡眠质量一般（效率 \(efficiency)%），建议优化睡前习惯。"
        case .poor:
            return "昨晚 \(duration) 睡眠质量较差（效率 \(efficiency)%），连续多日累积将影响恢复。"
        }
    }

    private static func buildReasons(
        totalMin: Int, h: Int, m: Int,
        deepPct: Int, efficiency: Int,
        awakenings: Int, hrv: Int,
        devPct: Int, avg7d: Int
    ) -> [String] {
        var rs: [String] = []

        // 时长
        if totalMin < 6 * 60 {
            rs.append("总时长 \(h)h\(String(format: "%02d", m))m，少于推荐下限 6h，神经恢复不足")
        } else if totalMin < 7 * 60 {
            rs.append("总时长 \(h)h\(String(format: "%02d", m))m，未达推荐 7-9h 区间")
        } else {
            let h2 = avg7d / 60
            let m2 = avg7d % 60
            let sign = devPct >= 0 ? "+" : ""
            rs.append("总时长 \(h)h\(String(format: "%02d", m))m，较 7 日均值 (\(h2)h\(String(format: "%02d", m2))m) \(sign)\(devPct)%")
        }

        // 深睡
        if deepPct < 15 {
            rs.append("深睡占比仅 \(deepPct)%，远低于推荐 20-25%，肌肉/免疫恢复受限")
        } else if deepPct < 20 {
            rs.append("深睡占比 \(deepPct)%，略低于推荐 20-25%")
        }

        // 效率
        if efficiency < 80 {
            rs.append("睡眠效率 \(efficiency)%，低于健康阈值 85%")
        } else if efficiency < 88 {
            rs.append("睡眠效率 \(efficiency)%，在 85-88% 临界区间")
        }

        // 醒来
        if awakenings >= 4 {
            rs.append("夜间醒来 \(awakenings) 次，睡眠连续性明显受损")
        }

        // HRV
        if hrv < 35 {
            rs.append("HRV \(hrv) ms 偏低，副交感恢复力下降")
        }

        return rs
    }

    private static func buildRecommendations(
        risk: AISleepReport.Risk, deepPct: Int, awakenings: Int
    ) -> [String] {
        var recs: [String] = []

        if risk == .poor {
            recs.append("今晚 22:30 前关闭屏幕，启动勿扰模式")
            recs.append("卧室温度控制在 18-22°C，必要时使用遮光帘")
        } else if risk == .fair {
            recs.append("保持规律作息，连续 3 晚 22:30 入睡即可回稳")
        } else {
            recs.append("保持当前睡眠节律，本周固定起床时间 ±30 分钟")
        }

        if deepPct < 18 {
            recs.append("下午 3 点后避免咖啡因；晚上热水澡（10 分钟）助眠")
        }

        if awakenings >= 3 {
            recs.append("睡前 90 分钟避免大量饮水，减少起夜次数")
        }

        if recs.count < 3 {
            recs.append("4-7-8 呼吸法：4s 吸 / 7s 屏 / 8s 呼，循环 4 次")
        }
        return recs
    }
}
