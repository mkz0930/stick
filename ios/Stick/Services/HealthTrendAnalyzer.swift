//
//  HealthTrendAnalyzer.swift
//  基于今日和历史健康数据计算趋势语义
//

import Foundation

/// 健康趋势分析结果
struct HealthTrend {
    /// 连续久坐分钟数（中间行走 ≤1 分钟则断开），nil=无连续段
    let sedentaryStreakMinutes: Int?
    /// 连续久坐超标天数（>2h/天）
    let sedentaryDays: Int
    /// 今日步数 vs 昨日 %
    let stepTrendPct: Int
    /// 今日步数 vs 7日平均 %
    let avgStepDiffPct: Int
    /// 睡眠缺口（目标7.5h），nil=无法计算
    let sleepDebtMinutes: Int?
    /// LLM 可直接引用的语义句数组
    let semanticLines: [String]
}

enum HealthTrendAnalyzer {
    /// 基于今日快照和全部历史计算健康趋势
    static func analyze(today: [HealthSnapshot], all: [HealthSnapshot]) -> HealthTrend {
        let sedentaryStreak = computeSedentaryStreak(today: today)
        let sedentaryDays = computeSedentaryDays(all: all)
        let stepTrendPct = computeStepTrendPct(today: today, all: all)
        let avgStepDiffPct = computeAvgStepDiffPct(today: today, all: all)
        let sleepDebt = computeSleepDebt(today: today, all: all)
        let semanticLines = buildSemanticLines(
            sedentaryStreak: sedentaryStreak,
            sedentaryDays: sedentaryDays,
            stepTrendPct: stepTrendPct,
            avgStepDiffPct: avgStepDiffPct,
            sleepDebt: sleepDebt,
            // 今日步数: 取最后一条 snapshot 的 cumulativeStepCount (已是全天累计)
            todaySteps: today.last?.cumulativeStepCount ?? 0
        )
        return HealthTrend(
            sedentaryStreakMinutes: sedentaryStreak,
            sedentaryDays: sedentaryDays,
            stepTrendPct: stepTrendPct,
            avgStepDiffPct: avgStepDiffPct,
            sleepDebtMinutes: sleepDebt,
            semanticLines: semanticLines
        )
    }

    // MARK: - 连续久坐分钟数

    /// 遍历 today，按 bodyState 累计连续 sit 段（每条 snapshot = 1 分钟），行走 > 1 分钟断开
    private static func computeSedentaryStreak(today: [HealthSnapshot]) -> Int? {
        var maxStreak = 0
        var currentStreak = 0
        var walkGap = 0

        for snapshot in today {
            if snapshot.bodyState == "sit" {
                currentStreak += 1
                walkGap = 0
                maxStreak = max(maxStreak, currentStreak)
            } else if snapshot.bodyState == "walk" {
                walkGap += 1
                if walkGap > 1 {
                    // 行走超过 1 分钟，断开连续段
                    currentStreak = 0
                    walkGap = 0
                }
            } else {
                // stand / sleep 同样断开
                currentStreak = 0
                walkGap = 0
            }
        }
        return maxStreak > 0 ? maxStreak : nil
    }

    // MARK: - 连续久坐超标天数

    /// 从 all 中找连续天数，每天久坐总和 > 120 分钟算超标
    private static func computeSedentaryDays(all: [HealthSnapshot]) -> Int {
        // 按天分组
        let grouped = Dictionary(grouping: all) { snapshot -> Date in
            Calendar.current.startOfDay(for: snapshot.timestamp)
        }
        var count = 0
        for (_, snapshots) in grouped {
            let sitMinutes = snapshots.filter { $0.bodyState == "sit" }.count
            if sitMinutes > 120 {
                count += 1
            }
        }
        return count
    }

    // MARK: - 今日 vs 昨日步数趋势

    /// (今日步数 - 昨日步数) / 昨日步数 * 100，保留整数
    private static func computeStepTrendPct(today: [HealthSnapshot], all: [HealthSnapshot]) -> Int {
        let todaySteps = today.last?.cumulativeStepCount ?? 0

        // 找昨日
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStart = calendar.startOfDay(for: yesterday)
        let yesterdayEnd = calendar.date(byAdding: .day, value: 1, to: yesterdayStart)!

        let yesterdaySnapshots = all.filter { snapshot in
            let ts = snapshot.timestamp
            return ts >= yesterdayStart && ts < yesterdayEnd
        }
        let yesterdaySteps = yesterdaySnapshots.last?.cumulativeStepCount ?? 0

        guard yesterdaySteps > 0 else { return 0 }
        return Int((Double(todaySteps - yesterdaySteps) / Double(yesterdaySteps)) * 100)
    }

    // MARK: - 今日 vs 7日平均

    /// 今日 vs all 里过去 7 天平均值的偏差
    private static func computeAvgStepDiffPct(today: [HealthSnapshot], all: [HealthSnapshot]) -> Int {
        let todaySteps = today.last?.cumulativeStepCount ?? 0

        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        let recentSnapshots = all.filter { snapshot in
            snapshot.timestamp >= sevenDaysAgo && snapshot.timestamp < calendar.startOfDay(for: Date())
        }
        guard !recentSnapshots.isEmpty else { return 0 }

        // 按天取最后一条 snapshot 的 cumulativeStepCount 作为当日总步数
        let grouped = Dictionary(grouping: recentSnapshots) { snapshot -> Date in
            calendar.startOfDay(for: snapshot.timestamp)
        }
        let dailySteps = grouped.mapValues { snapshots in
            snapshots.last?.cumulativeStepCount ?? 0
        }
        guard !dailySteps.isEmpty else { return 0 }

        let avgSteps = dailySteps.values.reduce(0, +) / dailySteps.count
        guard avgSteps > 0 else { return 0 }
        return Int((Double(todaySteps - avgSteps) / Double(avgSteps)) * 100)
    }

    // MARK: - 睡眠债务

    /// 目标 450 分钟（7.5h），取 all 里今日睡眠 snapshot 累加，不足 450 取缺口
    private static func computeSleepDebt(today: [HealthSnapshot], all: [HealthSnapshot]) -> Int? {
        let targetMinutes = 450

        let todaySleep = today.filter { $0.bodyState == "sleep" }.count
        if todaySleep >= targetMinutes { return nil } // 无债务

        return targetMinutes - todaySleep
    }

    // MARK: - 语义句生成

    private static func buildSemanticLines(
        sedentaryStreak: Int?,
        sedentaryDays: Int,
        stepTrendPct: Int,
        avgStepDiffPct: Int,
        sleepDebt: Int?,
        todaySteps: Int
    ) -> [String] {
        var lines: [String] = []

        if let streak = sedentaryStreak, streak >= 30 {
            let hours = streak / 60
            let mins = streak % 60
            if hours > 0 {
                lines.append("已连续久坐 \(hours) 小时 \(mins) 分钟")
            } else {
                lines.append("已连续久坐 \(streak) 分钟")
            }
        }

        if sedentaryDays >= 3 {
            lines.append("近 \(sedentaryDays) 天每日久坐超过 2 小时")
        }

        if stepTrendPct >= 20 {
            lines.append("今日步数比昨日高 \(stepTrendPct)%，活动量明显增加")
        } else if stepTrendPct <= -20 {
            lines.append("今日步数比昨日低 \(abs(stepTrendPct))%，活动量有所减少")
        }

        if avgStepDiffPct >= 30 {
            lines.append("今日步数显著高于近 7 日平均水平")
        } else if avgStepDiffPct <= -30 {
            lines.append("今日步数明显低于近 7 日平均水平")
        }

        if let debt = sleepDebt, debt > 0 {
            let hours = debt / 60
            let mins = debt % 60
            if hours > 0 {
                lines.append("睡眠缺口约 \(hours) 小时 \(mins) 分钟")
            } else {
                lines.append("睡眠缺口约 \(mins) 分钟")
            }
        }

        return lines
    }
}
