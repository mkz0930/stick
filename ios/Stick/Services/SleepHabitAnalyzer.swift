//
//  SleepHabitAnalyzer.swift
//  从 HealthStore 的 snapshot 流中提取 sleep 段并统计睡眠习惯
//
//  - 找出 bodyState == "sleep" 的连续 snapshot
//  - 合并连续 sleep 段 → 一个 sleep session
//  - 计算最近 N 天平均时长 / 平均 bedtime (分钟) / 平均 waketime (分钟)
//

import Foundation

@MainActor
enum SleepHabitAnalyzer {
    struct Stats {
        let avgDurationMinutes: Int
        let avgBedtime: Int          // 平均几点睡 (分钟: 22:30 → 1350)
        let avgWakeTime: Int         // 平均几点起 (分钟)
        let sessionCount: Int
    }

    /// 从 snapshot 数组中统计 sleep 习惯
    /// - Parameters:
    ///   - snapshots: HealthStore.all（不需要按 day 分组）
    ///   - days: 取最近 N 天（默认 7）
    static func analyze(snapshots: [HealthSnapshot], days: Int = 7) -> Stats {
        guard !snapshots.isEmpty else {
            return Stats(avgDurationMinutes: 0, avgBedtime: 0, avgWakeTime: 0, sessionCount: 0)
        }

        // 1) 提取 sleep snapshot
        let sleepSnaps = snapshots
            .filter { $0.bodyState == "sleep" }
            .sorted { $0.timestamp < $1.timestamp }
        guard !sleepSnaps.isEmpty else {
            return Stats(avgDurationMinutes: 0, avgBedtime: 0, avgWakeTime: 0, sessionCount: 0)
        }

        // 2) 合并连续段（gap <= 5 分钟视为同段）
        var sessions: [(start: Date, end: Date)] = []
        var curStart = sleepSnaps[0].timestamp
        var curEnd = sleepSnaps[0].timestamp
        for i in 1..<sleepSnaps.count {
            let ts = sleepSnaps[i].timestamp
            if ts.timeIntervalSince(curEnd) <= 5 * 60 {
                curEnd = ts
            } else {
                sessions.append((curStart, curEnd))
                curStart = ts
                curEnd = ts
            }
        }
        sessions.append((curStart, curEnd))

        // 3) 过滤最近 N 天
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let recent = sessions.filter { $0.end >= cutoff }

        guard !recent.isEmpty else {
            return Stats(avgDurationMinutes: 0, avgBedtime: 0, avgWakeTime: 0, sessionCount: 0)
        }

        // 4) 统计平均时长 / 平均 bed / 平均 wake
        var totalDurationMin = 0
        var bedtimeMinutes: [Int] = []
        var wakeMinutes: [Int] = []
        for s in recent {
            let durMin = Int(s.end.timeIntervalSince(s.start) / 60)
            // 过滤掉 <30 分钟或 >16 小时的异常段
            if durMin < 30 || durMin > 16 * 60 { continue }
            totalDurationMin += durMin
            // bedtime 取 session 起点的小时分钟
            let bedC = calendar.dateComponents([.hour, .minute], from: s.start)
            // 如果是凌晨/上午（< 12），算作"昨天"入睡：bedtime = (hour+24)*60 + minute
            var bedMin = (bedC.hour ?? 0) * 60 + (bedC.minute ?? 0)
            if (bedC.hour ?? 0) < 12 {
                bedMin += 24 * 60
            }
            bedtimeMinutes.append(bedMin)
            let wakeC = calendar.dateComponents([.hour, .minute], from: s.end)
            wakeMinutes.append((wakeC.hour ?? 0) * 60 + (wakeC.minute ?? 0))
        }

        let count = bedtimeMinutes.count
        guard count > 0 else {
            return Stats(avgDurationMinutes: 0, avgBedtime: 0, avgWakeTime: 0, sessionCount: 0)
        }

        let avgDur = totalDurationMin / count
        let avgBed = bedtimeMinutes.reduce(0, +) / count
        let avgWake = wakeMinutes.reduce(0, +) / count

        return Stats(
            avgDurationMinutes: avgDur,
            avgBedtime: avgBed,
            avgWakeTime: avgWake,
            sessionCount: count
        )
    }
}
