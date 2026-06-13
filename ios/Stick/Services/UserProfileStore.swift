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

    /// 自上次总结以来的 user 消息计数
    @Published private(set) var userMessageCount: Int = 0

    /// 多少条 user 消息触发一次总结
    let summaryInterval: Int = 10

    private let profileKey = "stick.userprofile.v1"
    private let countKey = "stick.userprofile.count.v1"

    init() {
        profile = UserDefaults.standard.string(forKey: profileKey) ?? "职场白领"
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

    /// 总结完成后清零（下一轮 3 条重新计数）
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
}
