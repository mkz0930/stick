//
//  HealthAuthService.swift
//  检查每个 MetricID 对应 HealthKit type 的真实授权 + 数据状态
//
//  行为：对每个 iPhone native metric query 过去 7d 数据
//   - HKError.errorAuthorizationDenied → 拒绝授权
//   - 有 samples  → 已授权 + 有数据
//   - 无 samples  → 已授权 + 无数据
//
//  watch / peripheral 类的 metric 直接标 .notSupported
//

import Foundation
import HealthKit
import Combine

@MainActor
final class HealthAuthService: ObservableObject {
    static let shared = HealthAuthService()

    /// Xcode Canvas Preview 用的 no-op 实例：不构造 HKHealthStore（避开 framework import 卡 preview）
    static let noop = HealthAuthService(isPreview: true)

    /// 状态字典 (启动 + 30s 刷新)
    @Published private(set) var statuses: [MetricID: MetricDataStatus] = [:]

    private let isPreview: Bool
    private let store: HKHealthStore?
    private var refreshTask: Task<Void, Never>?

    private init(isPreview: Bool = false) {
        self.isPreview = isPreview
        self.store = isPreview ? nil : HKHealthStore()
        // 全部 metric 都"未知"，先占位
        for m in MetricID.allCases {
            statuses[m] = .unknown
        }
    }

    /// 启动一次完整检查 (启动时 + 30s + 拉起 sheet 后)
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshAll()
        }
    }

    /// 异步刷新所有 metric 的真实状态
    func refreshAll() async {
        var out: [MetricID: MetricDataStatus] = [:]
        for metric in MetricID.allCases {
            let status = await checkOne(metric)
            out[metric] = status
        }
        self.statuses = out
    }

    /// 查询单个 metric 的真实状态
    private func checkOne(_ metric: MetricID) async -> MetricDataStatus {
        // iPhone 自身没硬件的类型
        guard let type = metric.hkType, let sampleType = type as? HKSampleType else {
            return .notSupported
        }

        // 0. 优先查本地 HealthStore.shared (HealthKitDemoData 降级写入) — 7d 内有数据 → hasData
        if hasLocalData(for: metric) {
            return .hasData
        }

        // 1. 真 query HealthKit
        let now = Date()
        let from = now.addingTimeInterval(-7 * 24 * 3600)
        let pred = HKQuery.predicateForSamples(withStart: from, end: now, options: .strictStartDate)

        return await withCheckedContinuation { (cont: CheckedContinuation<MetricDataStatus, Never>) in
            // 防重入: 用原子标记，callback 只 resume 一次
            let flag = ResumeFlag()
            let q = HKSampleQuery(
                sampleType: sampleType,
                predicate: pred,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                guard flag.tryResume() else { return }   // 多次 callback 防御
                if let hkErr = error as? HKError, hkErr.code == .errorAuthorizationDenied {
                    cont.resume(returning: .notAuthorized)
                } else if error != nil {
                    // 其他 error 也视作未授权 (保守)
                    cont.resume(returning: .notAuthorized)
                } else if let s = samples, !s.isEmpty {
                    cont.resume(returning: .hasData)
                } else {
                    cont.resume(returning: .noData)
                }
            }
            self.store?.execute(q)
        }
    }

    /// 本地 HealthStore.shared 过去 7d 是否有该 metric 的样本 (任何字段非 nil 即算)
    private func hasLocalData(for metric: MetricID) -> Bool {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let snapshots = HealthStore.shared.today.filter { $0.timestamp >= cutoff }
        guard !snapshots.isEmpty else { return false }
        switch metric {
        case .steps:           return snapshots.contains { $0.stepCount != nil }
        case .distance:        return snapshots.contains { $0.distance != nil }
        case .activeEnergy:    return snapshots.contains { $0.activeEnergy != nil }
        case .standHours:      return snapshots.contains { $0.standHours != nil }
        case .exerciseMinutes: return snapshots.contains { $0.exerciseMinutes != nil }
        case .flightsClimbed:   return snapshots.contains { $0.flightsClimbed != nil }
        default: return false
        }
    }

    /// 防"checked continuation 多次 resume"的小工具
    private final class ResumeFlag: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func tryResume() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}
