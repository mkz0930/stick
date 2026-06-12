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

    /// 状态字典 (启动 + 30s 刷新)
    @Published private(set) var statuses: [MetricID: MetricDataStatus] = [:]

    private let store = HKHealthStore()
    private var refreshTask: Task<Void, Never>?

    /// 全部 metric 都"未知"，先占位
    init() {
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
            self.store.execute(q)
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
