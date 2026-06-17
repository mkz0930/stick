//
//  UserProfileStore.swift
//  用户画像累计 + 周期总结
//
//  - 每次用户发送消息 → counter++
//  - counter % 3 == 0 → 异步调 LLM 总结最近 3 条对话，更新 profile
//  - 下次发消息时把 profile 作为 context 灌给 LLM
//
//  持久化: UserDefaults (profile 文本 + counter 整数)
//

import Foundation
import SwiftUI

@MainActor
final class UserProfileStore: ObservableObject {
    static let shared = UserProfileStore()

    /// 当前用户画像（LLM 总结的简短文字）
    @Published private(set) var profile: String = ""

    /// 自上次总结以来的 user 消息计数（用于触发下次总结）
    @Published private(set) var userMessageCount: Int = 0

    /// 短期标签分数（委托 UserInterestTagStore 管理，这里只作代理访问）
    private var shortTermScores: [String: Double] {
        UserInterestTagStore.shared.shortTermScores
    }

    /// 多少条 user 消息触发一次总结
    let summaryInterval: Int = 50

    private let profileKey = "stick.userprofile.v1"
    private let countKey = "stick.userprofile.count.v1"

    init() {
        profile = UserDefaults.standard.string(forKey: profileKey) ?? ""
        userMessageCount = UserDefaults.standard.integer(forKey: countKey)
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
}
