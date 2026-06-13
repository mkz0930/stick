//
//  ChatHistoryStore.swift
//  持久化 chat messages 到 UserDefaults — ChatOverlay 关闭时存, 启动时读
//
//  简化模型: 最多保留 50 条最近消息
//

import Foundation
import SwiftUI

/// 一条持久化的 chat 消息 (UserDefaults JSON)
struct PersistedChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: String         // "user" / "assistant"
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

@MainActor
final class ChatHistoryStore: ObservableObject {
    static let shared = ChatHistoryStore()

    private let key = "stick.chat.history.v1"
    private let maxMessages = 50

    @Published private(set) var messages: [PersistedChatMessage] = []

    init() {
        load()
        // 首次启动 (无历史) 时 demo 注入示例对话 — 让用户能看到 ChatOverlay 历史区
        if messages.isEmpty {
            messages = demoSeed()
            save()
        }
    }

    /// 示例对话 (首次启动 demo)
    private func demoSeed() -> [PersistedChatMessage] {
        let now = Date()
        return [
            PersistedChatMessage(
                role: "user",
                content: "我刚坐了一上午，怎么办？",
                timestamp: now.addingTimeInterval(-3600)
            ),
            PersistedChatMessage(
                role: "assistant",
                content: """
                久坐超过 1 小时颈椎和腰椎压力骤增。建议：

                · 立即起身活动 5 分钟（去接水/上厕所）
                · 做 3 次颈部米字操（每个方向停留 3 秒）
                · 调整坐姿：屏幕与眼睛同高，肘部 90°

                长期建议：每坐 45 分钟设闹钟强制起身。
                """,
                timestamp: now.addingTimeInterval(-3580)
            ),
            PersistedChatMessage(
                role: "user",
                content: "眼睛干涩怎么缓解？",
                timestamp: now.addingTimeInterval(-1800)
            ),
            PersistedChatMessage(
                role: "assistant",
                content: """
                屏幕盯久了泪膜蒸发过快，试试 20-20-20 法则：

                · 每 20 分钟看 20 英尺（约 6 米）外
                · 持续 20 秒以上
                · 主动多眨眼（每分钟 15-20 次）

                物理缓解：温毛巾敷眼 1 分钟 / 桌面放加湿器。
                """,
                timestamp: now.addingTimeInterval(-1780)
            ),
        ]
    }

    // MARK: - 增删改

    func append(_ msg: PersistedChatMessage) {
        messages.append(msg)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
        save()
    }

    func clear() {
        messages = []
        save()
    }

    /// 用新消息列表整体替换 (用于 ChatOverlay.onDisappear 写回)
    func replaceAll(with newMessages: [PersistedChatMessage]) {
        messages = Array(newMessages.suffix(maxMessages))
        save()
    }

    // MARK: - 持久化

    private func save() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: key)
            print("[ChatHistoryStore] save(): \(messages.count) msgs, user msgs: \(messages.filter { $0.role == "user" }.count)")
        } catch {
            print("[ChatHistoryStore] save failed: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            messages = try JSONDecoder().decode([PersistedChatMessage].self, from: data)
            print("[ChatHistoryStore] load(): \(messages.count) msgs loaded, user msgs: \(messages.filter { $0.role == "user" }.count)")
        } catch {
            print("[ChatHistoryStore] load failed: \(error)")
        }
    }
}
