// ios/Stick/Services/MorningReportTrigger.swift
import Foundation
import UIKit

@MainActor
@Observable
final class MorningReportTrigger {
    static let shared = MorningReportTrigger()

    private var monitorTask: Task<Void, Never>?
    private var lastActiveDate: Date?
    /// 持有 NotificationCenter observer token，避免闭包被释放后悬空
    private var didBecomeActiveObserver: NSObjectProtocol?
    /// single-flight 锁：同一时刻只允许一个 `checkAndGenerate` 任务在跑，
    /// 避免「上午多次解锁屏 → 5 份同一份昨天报告 → 5 条本地通知轰炸」。
    private var pendingCheck: Task<Void, Never>?
    /// 「上一次成功生成报告所对应的昨日日期字符串」缓存，
    /// 兜底防止 store 写盘前被并发 check 抢跑（load 还没落地，下一次 unlock 又开始一次）。
    private var lastGeneratedDateKey: String?

    private init() {}

    // 单例永生；停止监听请显式调用 stopMonitoring()。

    func startMonitoring() {
        guard monitorTask == nil else { return }
        // 注册一次 scenePhase 监听，token 必须持有
        if didBecomeActiveObserver == nil {
            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // single-flight：如果已有 Task 在跑，直接复用，不再 fork 新的
                guard let self else { return }
                if self.pendingCheck == nil {
                    self.pendingCheck = Task { @MainActor [weak self] in
                        await self?.checkAndGenerate()
                        self?.pendingCheck = nil  // 释放锁，下次 unlock 才会重新 fork
                    }
                }
            }
        }
        monitorTask = Task { [weak self] in
            await self?.runMonitor()
        }
    }

    func stopMonitoring() {
        pendingCheck?.cancel()
        pendingCheck = nil
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
            didBecomeActiveObserver = nil
        }
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func runMonitor() async {
        // 保持运行
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 1 分钟检查一次
        }
    }

    /// 检查是否需要生成报告
    /// 条件：时间 >= 07:00，昨日有步数，未生成过昨日报告
    /// 晨报内容是"昨天"的数据汇总（生成函数内部全部查 yesterday），
    /// 所以存档键和检查键都必须用"昨天"日期，否则连续两天打开 App 时
    /// 会把"昨日的报告"误判为"今日的报告"已生成，从而漏生成；或者
    /// 用今天的键去查，命中不到昨天刚存的那一份。
    func checkAndGenerate() async {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        // 只在 07:00 后检查
        guard hour >= 7 else { return }

        // 晨报对应的日期是昨天（生成函数语义）
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return }
        let yesterdayStr = Self.dateFormatter.string(from: yesterday)

        // 内存级去重：同进程内本次 unlock 触发的 sleep 15min 期间再 unlock 不会重复进 sleep
        if lastGeneratedDateKey == yesterdayStr {
            return
        }

        // 检查昨日是否已有报告（持久层去重）
        if MorningReportStore.shared.load(date: yesterdayStr) != nil {
            lastGeneratedDateKey = yesterdayStr
            return  // 昨日报告已生成
        }

        // 检查是否有步数
        let hasData = await HealthKitService.shared.hasStepData()
        guard hasData else { return }

        // 等待 10-20 分钟（模拟步数进来后生成）
        // 实际用 scenePhase 监听，用户解锁后等待
        try? await Task.sleep(nanoseconds: 15 * 60_000_000_000) // 15 分钟

        // 二次校验：sleep 完再查一次 store + 内存缓存，并发 unlock 可能已经在另一路径生成
        if lastGeneratedDateKey == yesterdayStr {
            return
        }
        if MorningReportStore.shared.load(date: yesterdayStr) != nil {
            lastGeneratedDateKey = yesterdayStr
            return
        }

        // 生成昨日报告
        await generateAndNotify(for: yesterday, dateKey: yesterdayStr)
    }

    private func generateAndNotify(for date: Date, dateKey: String) async {
        do {
            let report = try await MorningReportGenerator.shared.generate(for: date)
            MorningReportStore.shared.save(report)
            // 写盘成功后立刻标记内存缓存，避免其他 unlock 路径再次 fork
            lastGeneratedDateKey = dateKey
            await NotificationService.shared.scheduleMorningReport(report)
        } catch {
            print("[MorningReportTrigger] 生成失败: \(error)")
        }
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}