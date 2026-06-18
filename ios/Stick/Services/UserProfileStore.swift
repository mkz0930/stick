//
//  UserProfileStore.swift
//  用户画像累计 + 周期总结 + 睡眠习惯追踪
//
//  - 每次用户发送消息 → counter++
//  - counter % 50 == 0 → 异步调 LLM 总结最近 50 条对话，更新 profile
//  - 下次发消息时把 profile 作为 context 灌给 LLM
//
//  持久化: UserDefaults (profile 文本 + counter 整数 + 睡眠习惯 JSON)
//

import Foundation
import SwiftUI

/// 用户睡眠习惯画像（出差/在家分别维护；滑动平均更新）
struct UserSleepHabit: Codable, Equatable {
    /// 常驻作息
    var usualBedtime: Int?            // 分钟 (22:00 → 1320)，>24h 时加 24 (凌晨算昨天)
    var usualWakeTime: Int?           // 分钟 (7:00 → 420)
    var usualDurationMinutes: Int?    // 平均睡眠分钟
    var sampleCount: Int              // 样本数
    var lastUpdated: Date?            // 最后更新时间

    /// 出差作息
    var travelBedtime: Int?
    var travelWakeTime: Int?
    var travelDurationMinutes: Int?
    var travelSampleCount: Int

    /// 当前位置状态
    var homeCity: String?             // 常驻城市
    var isTravel: Bool                // 是否在出差
    var isTravelUntil: Date?          // 出差状态保持到什么时候

    static let empty = UserSleepHabit(
        usualBedtime: nil,
        usualWakeTime: nil,
        usualDurationMinutes: nil,
        sampleCount: 0,
        lastUpdated: nil,
        travelBedtime: nil,
        travelWakeTime: nil,
        travelDurationMinutes: nil,
        travelSampleCount: 0,
        homeCity: nil,
        isTravel: false,
        isTravelUntil: nil
    )
}

@MainActor
@Observable
final class UserProfileStore {
    static let shared = UserProfileStore()

    /// 当前用户画像（LLM 总结的简短文字）
    private(set) var profile: String = ""

    /// 自上次总结以来的 user 消息计数（用于触发下次总结）
    private(set) var userMessageCount: Int = 0

    /// 用户睡眠习惯画像（含常驻 + 出差）
    private(set) var sleepHabit: UserSleepHabit = .empty

    /// 短期标签分数（委托 UserInterestTagStore 管理，这里只作代理访问）
    private var shortTermScores: [String: Double] {
        UserInterestTagStore.shared.shortTermScores
    }

    /// 多少条 user 消息触发一次总结
    let summaryInterval: Int = 50

    private let profileKey = "stick.userprofile.v1"
    private let countKey = "stick.userprofile.count.v1"
    private let sleepHabitKey = "stick.userprofile.sleephabit.v1"

    init() {
        profile = UserDefaults.standard.string(forKey: profileKey) ?? ""
        userMessageCount = UserDefaults.standard.integer(forKey: countKey)
        sleepHabit = loadSleepHabit()
    }

    // MARK: - 计数

    /// 记录一条 user 消息。返回 true 表示**应该**触发总结（调用方负责 async 拉 LLM）
    @discardableResult
    func recordUserMessage() -> Bool {
        userMessageCount += 1
        UserDefaults.standard.set(userMessageCount, forKey: countKey)
        return userMessageCount % summaryInterval == 0
    }

    /// 总结完成后清零（只清零触发计数器，保留累计消息数用于年判断）
    func resetCounter() {
        userMessageCount = 0
        UserDefaults.standard.set(0, forKey: countKey)
    }

    // MARK: - 画像

    /// 用 LLM 返回的新总结覆盖当前 profile
    func updateProfile(_ newProfile: String) {
        profile = newProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(profile, forKey: profileKey)
    }

    /// 记录用户对睡眠时长的准确度反馈。追加到 profile 末尾，不覆盖原内容。
    func recordSleepAccuracy(accurate: Bool, date: Date) {
        let dateStr = Self.feedbackDateFormatter.string(from: date)
        let label = accurate ? "准确" : "不准确"
        appendProfileLine("睡眠时长反馈 \(dateStr): \(label)")
    }

    /// 记录算法校准提示（来自历史反馈统计）。追加到 profile 末尾。
    func recordCalibrationHint(_ hint: String) {
        let dateStr = Self.feedbackDateFormatter.string(from: Date())
        appendProfileLine("校准提示 \(dateStr): \(hint)")
    }

    /// 追加一行到 profile，自动加换行
    private func appendProfileLine(_ line: String) {
        if profile.isEmpty {
            profile = line
        } else {
            profile += "\n" + line
        }
        UserDefaults.standard.set(profile, forKey: profileKey)
    }

    private static let feedbackDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 调试用：清空画像
    func clear() {
        profile = ""
        userMessageCount = 0
        UserDefaults.standard.removeObject(forKey: profileKey)
        UserDefaults.standard.removeObject(forKey: countKey)
    }

    /// 给 LLM 的 prompt 拼一段: "用户画像: {profile}\n" (profile 为空时返回空串)
    func profileContextBlock() -> String {
        guard !profile.isEmpty else { return "" }
        return "【用户画像 (历史对话累计总结)】\n\(profile)\n"
    }

    /// 返回短期权重最高的标签
    func topShortTermTags(limit: Int = 5) -> [String] {
        UserInterestTagStore.shared.topShortTermTags(limit: limit)
    }

    // MARK: - 睡眠习惯

    private func loadSleepHabit() -> UserSleepHabit {
        guard let data = UserDefaults.standard.data(forKey: sleepHabitKey),
              let decoded = try? JSONDecoder().decode(UserSleepHabit.self, from: data) else {
            return .empty
        }
        return decoded
    }

    private func persistSleepHabit() {
        guard let data = try? JSONEncoder().encode(sleepHabit) else { return }
        UserDefaults.standard.set(data, forKey: sleepHabitKey)
    }

    /// 滑动平均更新睡眠习惯（权重 0.3 新样本 / 0.7 旧值）
    func updateSleepHabit(from info: SleepInfo) {
        let isTravel = sleepHabit.isTravel || sleepHabit.isTravelUntil.map { $0 > Date() } ?? false
        var h = sleepHabit
        h.lastUpdated = Date()
        h.isTravel = isTravel

        if isTravel {
            h.travelBedtime = info.bedTime.map { minuteOfDay24h(from: $0) } ?? h.travelBedtime
            h.travelWakeTime = info.wakeTime.map { minuteOfDay24h(from: $0) } ?? h.travelWakeTime
            if let dur = info.durationMinutes {
                h.travelDurationMinutes = blendInt(old: h.travelDurationMinutes, new: dur)
            }
            h.travelSampleCount += 1
        } else {
            h.usualBedtime = info.bedTime.map { minuteOfDay24h(from: $0) } ?? h.usualBedtime
            h.usualWakeTime = info.wakeTime.map { minuteOfDay24h(from: $0) } ?? h.usualWakeTime
            if let dur = info.durationMinutes {
                h.usualDurationMinutes = blendInt(old: h.usualDurationMinutes, new: dur)
            }
            h.sampleCount += 1
        }

        sleepHabit = h
        persistSleepHabit()
    }

    /// 设置出差状态
    func updateTravelStatus(isTravel: Bool, until: Date?) {
        var h = sleepHabit
        h.isTravel = isTravel
        h.isTravelUntil = until
        sleepHabit = h
        persistSleepHabit()
    }

    /// 给 LLM 的 prompt 拼一段："【睡眠习惯】…" (无数据时返回空串)
    func sleepHabitContextBlock(isTravel: Bool) -> String {
        let h = sleepHabit
        let (bed, wake, dur, count) = isTravel
            ? (h.travelBedtime, h.travelWakeTime, h.travelDurationMinutes, h.travelSampleCount)
            : (h.usualBedtime, h.usualWakeTime, h.usualDurationMinutes, h.sampleCount)
        if bed == nil && wake == nil && dur == nil { return "" }
        var lines: [String] = []
        if let bed = bed {
            lines.append("平均入睡: \(formatMinute24(bed))")
        }
        if let wake = wake {
            lines.append("平均起床: \(formatMinute24(wake))")
        }
        if let dur = dur {
            let hours = Double(dur) / 60.0
            lines.append(String(format: "平均时长: %.1f 小时", hours))
        }
        let tag = isTravel ? "出差作息" : "常驻作息"
        let countStr = count > 0 ? "（\(count) 个样本）" : ""
        return "【\(tag)】\(countStr)\n" + lines.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
    }

    // MARK: - helpers

    /// 把 Date 转换成"分钟内数"（>24h 表示凌晨+24h，便于滑动平均）
    private func minuteOfDay24h(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return m < 12 * 60 ? m + 24 * 60 : m
    }

    /// 滑动平均：old*0.7 + new*0.3
    private func blendInt(old: Int?, new: Int) -> Int {
        if let o = old {
            return Int(Double(o) * 0.7 + Double(new) * 0.3)
        }
        return new
    }

    /// 把"分钟内数"格式化为 HH:MM（支持 24h+）
    private func formatMinute24(_ minute: Int) -> String {
        let normalized = minute % (24 * 60)
        let h = normalized / 60
        let m = normalized % 60
        return String(format: "%02d:%02d", h, m)
    }
}
