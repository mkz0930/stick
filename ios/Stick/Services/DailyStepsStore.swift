//
//  DailyStepsStore.swift
//  每日步数累计存储（从 HealthStore 的快照数据中计算每日总计）
//

import Foundation

/// 单日步数记录
struct DailySteps: Codable, Identifiable {
    var id: String { dateString }
    let dateString: String   // "yyyy-MM-dd"
    let steps: Int
    let goal: Int

    var date: Date {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: dateString) ?? Date()
    }

    var achieved: Bool { steps >= goal }
}

/// 跨天持久化：每日累计步数，存储到 UserDefaults
@MainActor
final class DailyStepsStore: ObservableObject {
    static let shared = DailyStepsStore()

    /// 所有日数据（按日期升序）
    @Published private(set) var records: [DailySteps] = []

    private let key = "stick.daily.steps.v1"
    private let goal: Int = 10_000

    private init() {
        load()
        // app 启动时，用已有快照数据恢复今日步数（避免刚启动时今日步数为 0）
        if !HealthStore.shared.all.isEmpty {
            updateTodaySteps(from: HealthStore.shared.all)
        }
    }

    /// 根据 HealthStore 快照数据，更新今日步数
    /// 每次 app 启动或快照追加时调用
    func updateTodaySteps(from snapshots: [HealthSnapshot]) {
        let today = Self.todayString()
        let todayStart = Calendar.current.startOfDay(for: Date())

        // 今日步数: 取今日最后一条 snapshot 的 cumulativeStepCount (已是全天累计)
        // 旧版 bug: 过滤今日所有 snapshot 求和 → 480x 膨胀
        let todayTotal = snapshots
            .filter { $0.timestamp >= todayStart }
            .last?
            .cumulativeStepCount ?? 0

        updateOrInsert(dateString: today, steps: todayTotal)
    }

    /// 取指定日的步数（没有返回 nil）
    func steps(for dateString: String) -> Int? {
        records.first { $0.dateString == dateString }?.steps
    }

    /// 取近 N 天的步数数组
    func stepsLastDays(_ n: Int) -> [Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
        return records
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { $0.steps }
    }

    // MARK: - 私有

    private func updateOrInsert(dateString: String, steps: Int) {
        if let idx = records.firstIndex(where: { $0.dateString == dateString }) {
            records[idx] = DailySteps(dateString: dateString, steps: steps, goal: goal)
        } else {
            records.append(DailySteps(dateString: dateString, steps: steps, goal: goal))
        }
        records.sort { $0.dateString < $1.dateString }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("[DailyStepsStore] save failed: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DailySteps].self, from: data) else {
            return
        }
        records = decoded
    }

    private static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
