//
//  SleepFeedbackStats.swift
//  统计近 N 天睡眠准确度反馈，用于检测算法是否需要校准
//

import Foundation

/// 统计结果
struct SleepFeedbackSummary {
    /// 已反馈总数
    let totalCount: Int
    /// 不准确数量（feedback == 0）
    let inaccurateCount: Int
    /// 不准确比例（0.0-1.0）
    let inaccuracyRate: Double

    static let empty = SleepFeedbackSummary(totalCount: 0, inaccurateCount: 0, inaccuracyRate: 0.0)
}

enum SleepFeedbackStats {
    /// 晨报 JSON 存储目录
    private static var reportsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("MorningReports", isDirectory: true)
    }

    /// 计算最近 N 天睡眠反馈的不准确率
    /// - Parameter days: 统计窗口（默认 7 天）
    /// - Returns: 包含总数/不准确数/比例的汇总
    static func recentSummary(days: Int = 7) -> SleepFeedbackSummary {
        guard let files = try? FileManager.default.contentsOfDirectory(at: reportsDir, includingPropertiesForKeys: nil) else {
            return .empty
        }

        // 1. 计算 cutoff 日期（yyyy-MM-dd 字符串），N 天前的日期
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffStr = dateString(from: cutoffDate)

        var total = 0
        var inaccurate = 0

        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let report = try? JSONDecoder().decode(MorningReport.self, from: data) else {
                continue
            }
            // 2. 只看 cutoff 之后的报告
            guard report.date >= cutoffStr else { continue }
            // 3. 只统计已反馈的（feedback != nil）
            guard let feedback = report.sleepAccuracyFeedback else { continue }
            total += 1
            if feedback == 0 {
                inaccurate += 1
            }
        }

        let rate = total > 0 ? Double(inaccurate) / Double(total) : 0.0
        return SleepFeedbackSummary(totalCount: total, inaccurateCount: inaccurate, inaccuracyRate: rate)
    }

    private static func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
