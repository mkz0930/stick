//
//  HealthStore.swift
//  本地存储 (JSON 文件) — 一天一条,放在 Documents 目录
//

import Foundation
import Combine

@MainActor
final class HealthStore: ObservableObject {
    static let shared = HealthStore()

    @Published private(set) var all: [HealthSnapshot] = []
    @Published private(set) var today: [HealthSnapshot] = []
    /// 是否已完成 JSON 文件加载（异步）。未完成期间 `all` / `today` 为空，
    /// 调用方（DailyStepsStore / ContentView）应等待 loaded == true 再做统计。
    @Published private(set) var loaded: Bool = false

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = docs.appendingPathComponent("health-snapshots.json")
        // 启动期跳过同步文件 IO；放到后台线程异步加载，
        // 避免 HealthStore.shared 首次访问时阻塞主线程（影响 ContentView 启动）。
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loadFromDisk()
        }
    }

    /// 后台读取 JSON 并在主线程回填数据。`init()` 中启动。
    @MainActor
    private func loadFromDisk() async {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loaded = true
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            self.all = try JSONDecoder().decode([HealthSnapshot].self, from: data)
            refreshToday()
        } catch {
            print("[HealthStore] load failed: \(error)")
        }
        loaded = true
    }

    // MARK: - 增删改

    func append(_ snapshot: HealthSnapshot) {
        all.append(snapshot)
        let key = Calendar.current.startOfDay(for: snapshot.timestamp)
        today = all.filter { Calendar.current.startOfDay(for: $0.timestamp) == key }
        // 同步更新每日步数累计
        DailyStepsStore.shared.updateTodaySteps(from: all)
        save()
    }

    func appendBatch(_ snapshots: [HealthSnapshot]) {
        all.append(contentsOf: snapshots)
        let key = Calendar.current.startOfDay(for: Date())
        today = all.filter { Calendar.current.startOfDay(for: $0.timestamp) == key }
        save()
    }

    func refreshToday() {
        let key = Calendar.current.startOfDay(for: Date())
        today = all.filter { Calendar.current.startOfDay(for: $0.timestamp) == key }
    }

    // MARK: - 持久化

    private func save() {
        do {
            let data = try JSONEncoder().encode(all)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[HealthStore] save failed: \(error)")
        }
    }

    func clearAll() {
        all = []
        today = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - 模拟器调试：注入 Mock 数据
    /// 模拟器无 HealthKit，用 MockHealthDataLoader 注入后通过此方法写入。
    /// 不持久化（下次启动还是空的，除非再注入一次）
    func setAllForMock(_ snapshots: [HealthSnapshot]) {
        all = snapshots
        refreshToday()
    }
}
