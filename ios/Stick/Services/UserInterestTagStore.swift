//
//  UserInterestTagStore.swift
//  用户兴趣标签短期/长期权重管理
//
//  - 短期：按周衰减，每次 record 同标签 +1.0 分，超过 7 天自动清零
//  - 长期：按年重置，只增不减，App 启动时检查是否超过 365 天
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class UserInterestTagStore {
    static let shared = UserInterestTagStore()

    /// 短期标签分数（周衰减）
    private(set) var shortTermScores: [String: Double] = [:]

    /// 长期标签分数（年重置）
    private(set) var longTermScores: [String: Double] = [:]

    private let shortTermKey = "stick.tags.shortterm.v1"
    private let longTermKey  = "stick.tags.longterm.v1"
    private let shortTermResetKey = "stick.tags.shortterm.reset.v1"
    private let longTermResetKey  = "stick.tags.longterm.reset.v1"

    private init() {
        loadShortTerm()
        loadLongTerm()
    }

    // MARK: - 记录

    /// 每次用户发消息时调用，标签加1分
    func record(tags: [String]) {
        for tag in tags {
            shortTermScores[tag, default: 0] += 1.0
            longTermScores[tag, default: 0] += 1.0
        }
        saveShortTerm()
        saveLongTerm()
    }

    /// 返回短期权重最高的标签
    func topShortTermTags(limit: Int = 5) -> [String] {
        sortByScore(shortTermScores, limit: limit)
    }

    /// 返回长期权重最高的标签
    func topLongTermTags(limit: Int = 5) -> [String] {
        sortByScore(longTermScores, limit: limit)
    }

    /// 检查是否超过7天，是则重置短期
    func resetShortTermIfExpired() {
        guard let lastReset = UserDefaults.standard.object(forKey: shortTermResetKey) as? Date else {
            // 从未重置过，设为现在
            UserDefaults.standard.set(Date(), forKey: shortTermResetKey)
            return
        }
        let daysDiff = Calendar.current.dateComponents([.day], from: lastReset, to: Date()).day ?? 0
        if daysDiff >= 7 {
            resetShortTerm()
        }
    }

    /// 重置短期（周重置）
    func resetShortTerm() {
        shortTermScores = [:]
        UserDefaults.standard.set(Date(), forKey: shortTermResetKey)
        saveShortTerm()
    }

    /// 重置长期（年重置）
    func resetLongTerm() {
        longTermScores = [:]
        UserDefaults.standard.set(Date(), forKey: longTermResetKey)
        saveLongTerm()
    }

    // MARK: - App 启动检查

    /// 在 App 启动时调用，检查长期标签是否超过 365 天需重置
    func checkLongTermExpiry() {
        guard let lastReset = UserDefaults.standard.object(forKey: longTermResetKey) as? Date else {
            UserDefaults.standard.set(Date(), forKey: longTermResetKey)
            return
        }
        let daysDiff = Calendar.current.dateComponents([.day], from: lastReset, to: Date()).day ?? 0
        if daysDiff >= 365 {
            resetLongTerm()
        }
    }

    // MARK: - 排序

    private func sortByScore(_ scores: [String: Double], limit: Int) -> [String] {
        scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    // MARK: - 持久化

    private func saveShortTerm() {
        do {
            let data = try JSONEncoder().encode(shortTermScores)
            UserDefaults.standard.set(data, forKey: shortTermKey)
        } catch {
            print("[UserInterestTagStore] saveShortTerm failed: \(error)")
        }
    }

    private func loadShortTerm() {
        guard let data = UserDefaults.standard.data(forKey: shortTermKey) else { return }
        do {
            shortTermScores = try JSONDecoder().decode([String: Double].self, from: data)
        } catch {
            print("[UserInterestTagStore] loadShortTerm failed: \(error)")
        }
    }

    private func saveLongTerm() {
        do {
            let data = try JSONEncoder().encode(longTermScores)
            UserDefaults.standard.set(data, forKey: longTermKey)
        } catch {
            print("[UserInterestTagStore] saveLongTerm failed: \(error)")
        }
    }

    private func loadLongTerm() {
        guard let data = UserDefaults.standard.data(forKey: longTermKey) else { return }
        do {
            longTermScores = try JSONDecoder().decode([String: Double].self, from: data)
        } catch {
            print("[UserInterestTagStore] loadLongTerm failed: \(error)")
        }
    }
}
