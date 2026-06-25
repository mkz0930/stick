//
//  SleepAnalyzer.swift
//  从 HealthKit 抓取昨晚 sleep analysis 类别数据, 聚合成 SleepSession
//

import Foundation
import HealthKit

// MARK: - 数据模型

/// 睡眠阶段 (HealthKit 类别值 + 简化聚合)
enum SleepStage: String, CaseIterable, Codable {
    case awake
    case inBed
    case asleep       // asleepUnspecified
    case rem          // asleepREM
    case core         // asleepCore  (iOS 16+)
    case deep         // asleepDeep
}

/// 单段睡眠样本
struct SleepSegment: Identifiable, Codable {
    let id: UUID
    let stage: SleepStage
    let start: Date
    let end: Date

    init(id: UUID = UUID(), stage: SleepStage, start: Date, end: Date) {
        self.id = id
        self.stage = stage
        self.start = start
        self.end = end
    }

    /// 段长 (分钟)
    var durationMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }
}

/// 一次完整睡眠 (从入睡到醒来)
struct SleepSession: Identifiable, Codable {
    let id: UUID
    let start: Date          // 昨晚入睡
    let end: Date            // 今早醒来
    let segments: [SleepSegment]

    init(id: UUID = UUID(), start: Date, end: Date, segments: [SleepSegment]) {
        self.id = id
        self.start = start
        self.end = end
        self.segments = segments
    }

    // MARK: 聚合 (computed)

    /// 床内总时长 (从 first segment 到 last segment)
    var totalMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    /// 醒着的总分钟
    var awakeMinutes: Int {
        segments
            .filter { $0.stage == .awake }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// REM 总分钟
    var remMinutes: Int {
        segments
            .filter { $0.stage == .rem }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// Core 总分钟
    var coreMinutes: Int {
        segments
            .filter { $0.stage == .core }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// Deep 总分钟
    var deepMinutes: Int {
        segments
            .filter { $0.stage == .deep }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// asleepUnspecified 分钟 (无明确分期的睡眠)
    var unspecifiedMinutes: Int {
        segments
            .filter { $0.stage == .asleep }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// 真正入睡时长 (core + deep + rem + asleep)
    var asleepMinutes: Int {
        coreMinutes + deepMinutes + remMinutes + unspecifiedMinutes
    }

    /// 睡眠效率: asleep / totalInBed  (0.0 ~ 1.0)
    var efficiency: Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1.0, Double(asleepMinutes) / Double(totalMinutes))
    }
}

// MARK: - Analyzer

@MainActor
@Observable
final class SleepAnalyzer {
    static let shared = SleepAnalyzer()

    var lastSession: SleepSession?

    /// HKHealthStore 是 thread-safe reference type，标 nonisolated 让 query helper 脱离 main actor
    private nonisolated let store = HKHealthStore()
    private nonisolated let sleepType: HKCategoryType? = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)

    // MARK: - HKObjectType 查询 helper
    // HKObjectType 系统常量访问是线程安全的，标 `nonisolated` 让 query helper 能在任意 actor 上调用
    private nonisolated func categoryType(_ id: HKCategoryTypeIdentifier) -> HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: id)
    }

    // MARK: - 授权

    /// 请求 sleep analysis 读权限 (应在 app 启动早期调用)
    nonisolated func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), let type = sleepType else {
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
            return true
        } catch {
            #if DEBUG
            print("[SleepAnalyzer] auth failed: \(error)")
            #endif
            return false
        }
    }

    // MARK: - 抓取

    /// 抓取昨晚的 sleep session (委托 HealthKitService 统一入口)
    func fetchLastNight() async -> SleepSession? {
        let session = await HealthKitService.shared.fetchLastNightSession()
        if let session { self.lastSession = session }
        return session
    }

    // MARK: - 内部: 合并相邻同 stage

    /// 合并相邻同 stage 段 (前提: 已按 start 排序)
    static func mergeAdjacent(_ segments: [SleepSegment]) -> [SleepSegment] {
        guard !segments.isEmpty else { return [] }
        var out: [SleepSegment] = []
        var current = segments[0]
        for s in segments.dropFirst() {
            if s.stage == current.stage && s.start <= current.end {
                // 同 stage 且相邻/重叠 → 合并
                current = SleepSegment(
                    id: current.id,
                    stage: current.stage,
                    start: current.start,
                    end: max(current.end, s.end)
                )
            } else {
                out.append(current)
                current = s
            }
        }
        out.append(current)
        return out
    }

    // MARK: - 内部: 挑选最新 session

    /// 从合并后的段里, 找最晚的一段"真正睡眠" (不含 awake/inBed)
    /// 启发式: 扫描, 把 inBed 算前导, 第一个 asleep 类段开始,
    /// 直到遇到 awake 段超过 30 分钟 (醒来) 结束
    /// 取所有这些 session 中"最晚的一个", 长度 > minMinutes
    static func pickLatestSession(
        _ segments: [SleepSegment],
        minDurationMinutes: Int
    ) -> SleepSession? {
        guard !segments.isEmpty else { return nil }

        // 分组: 把相邻 awake/inBed 段视为分隔, 中间连续的"睡眠" 段视为一个 session
        var sessions: [(start: Date, end: Date, segs: [SleepSegment])] = []
        var currentSegs: [SleepSegment] = []
        var sawAsleep = false

        for s in segments {
            let isSleep = (s.stage == .asleep || s.stage == .core
                           || s.stage == .deep || s.stage == .rem)
            if isSleep {
                currentSegs.append(s)
                sawAsleep = true
            } else {
                // awake / inBed
                if sawAsleep {
                    // 当前 session 结束
                    if let first = currentSegs.first, let last = currentSegs.last {
                        let dur = Int(last.end.timeIntervalSince(first.start) / 60)
                        if dur >= minDurationMinutes {
                            sessions.append((first.start, last.end, currentSegs))
                        }
                    }
                    currentSegs = []
                    sawAsleep = false
                }
                // 否则 (纯 awake/inBed 开头) 跳过
            }
        }
        // 尾巴
        if sawAsleep, let first = currentSegs.first, let last = currentSegs.last {
            let dur = Int(last.end.timeIntervalSince(first.start) / 60)
            if dur >= minDurationMinutes {
                sessions.append((first.start, last.end, currentSegs))
            }
        }

        // 取最晚的
        guard let latest = sessions.max(by: { $0.start < $1.start }) else { return nil }

        return SleepSession(
            start: latest.start,
            end: latest.end,
            segments: latest.segs
        )
    }

    // MARK: - 摘要

    /// 生成 "总时长 7h42m · 深睡 1h32m · REM 1h45m" 形式的简短摘要
    func summarize(_ session: SleepSession) -> String {
        let total = formatHM(minutes: session.totalMinutes)
        let deep = formatHM(minutes: session.deepMinutes)
        let rem  = formatHM(minutes: session.remMinutes)
        return "总时长 \(total) · 深睡 \(deep) · REM \(rem)"
    }

    private func formatHM(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h\(String(format: "%02d", m))m"
    }
}
