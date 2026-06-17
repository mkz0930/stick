// ios/Stick/Services/MorningReportTrigger.swift
import Foundation
import UIKit

@MainActor
final class MorningReportTrigger: ObservableObject {
    static let shared = MorningReportTrigger()

    private var monitorTask: Task<Void, Never>?
    private var lastActiveDate: Date?

    private init() {}

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            await self?.runMonitor()
        }
    }

    private func runMonitor() async {
        // 监听 scenePhase 变化，每次从后台回到前台都检查
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndGenerate()
            }
        }

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

        // 检查昨日是否已有报告
        if MorningReportStore.shared.load(date: yesterdayStr) != nil {
            return  // 昨日报告已生成
        }

        // 检查是否有步数
        let hasData = await HealthKitService.shared.hasStepData()
        guard hasData else { return }

        // 等待 10-20 分钟（模拟步数进来后生成）
        // 实际用 scenePhase 监听，用户解锁后等待
        try? await Task.sleep(nanoseconds: 15 * 60_000_000_000) // 15 分钟

        // 生成昨日报告
        await generateAndNotify(for: yesterday)
    }

    private func generateAndNotify(for date: Date) async {
        do {
            let report = try await MorningReportGenerator.shared.generate(for: date)
            MorningReportStore.shared.save(report)
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